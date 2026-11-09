//! Port của overlay/frontend/ritder/update.lua (642 dòng) — lõi OTA phía thiết bị.
//! Logic thuần: version compare, safe/protected paths, manifest validation,
//! ARM64 ELF check, staging state machine. HTTP thật (HTTPS + redirect) được
//! giữ ở dạng hàm có kiểm tra URL; tải mạng là host-dependent (xem MIGRATION.md).
use serde::Deserialize;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub const MAX_REDIRECTS: u32 = 8;
pub const TIMEOUT_SECS: u64 = 30;
pub const PACKAGE_NAME: &str = "package.tar.gz";
pub const REQUIRED: [&str; 5] = ["launch.sh", "install.sh", "logging.sh", "reader.lua", "luajit"];
pub const ARCH_CHECK: &str = "luajit";

/// Port của PROTECTED = { "^userdata/", "^userdata$", "^settings%.json$" } (không dùng regex).
pub fn is_protected(rel: &str) -> bool {
    rel == "userdata" || rel.starts_with("userdata/") || rel == "settings.json"
}

/// "v0.10.0-rc1" -> [0,10,0,1]; mỗi phần lấy số đầu tiên, không có số thì 0.
pub fn parse_version(v: &str) -> Vec<i64> {
    let v = v.trim();
    let v = v.strip_prefix(['v', 'V']).unwrap_or(v);
    v.split(|c| c == '.' || c == '-' || c == '+')
        .filter(|s| !s.is_empty())
        .map(|part| {
            // Theo docstring của bản Lua: "v0.10.0-rc1" -> {0,10,0,1}, tức lấy
            // cụm số đầu tiên trong phần ("rc1" -> 1); không có số thì 0.
            let digits: String = part.chars().skip_while(|c| !c.is_ascii_digit())
                .take_while(|c| c.is_ascii_digit()).collect();
            digits.parse().unwrap_or(0)
        })
        .collect()
}

/// Chỉ true khi candidate mới hơn hẳn current (không bao giờ hạ cấp).
pub fn is_newer(candidate: &str, current: &str) -> bool {
    let a = parse_version(candidate);
    let b = parse_version(current);
    for i in 0..a.len().max(b.len()) {
        let x = a.get(i).copied().unwrap_or(0);
        let y = b.get(i).copied().unwrap_or(0);
        if x != y { return x > y; }
    }
    false
}

/// Đường dẫn tương đối an toàn trong gói: không tuyệt đối, không "..", không '\\', không NUL.
pub fn is_safe_path(rel: &str) -> bool {
    if rel.is_empty() || rel.starts_with('/') || rel.contains('\\') || rel.contains('\0') {
        return false;
    }
    !rel.split('/').any(|p| p == "..")
}

/// ELF 64-bit little-endian AArch64 (e_machine 0xB7).
pub fn is_arm64_elf_bytes(head: &[u8]) -> bool {
    if head.len() < 20 || &head[0..4] != b"\x7fELF" { return false; }
    if head[4] != 2 || head[5] != 1 { return false; }
    (head[18] as u16) + (head[19] as u16) * 256 == 0xB7
}
pub fn is_arm64_elf(path: &Path) -> bool {
    match fs::read(path) {
        Ok(d) => is_arm64_elf_bytes(&d),
        Err(_) => false,
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct Manifest {
    pub version: String,
    pub sha256: String,
    pub url: Option<String>,
    pub file: Option<String>,
    pub notes: Option<String>,
    pub size: Option<u64>,
    #[serde(skip)]
    pub package_url: String,
}

/// Port của Update.fetchManifest phần validate (không gồm tải mạng).
pub fn validate_manifest(text: &str, manifest_url: &str) -> Result<Manifest, String> {
    let mut m: Manifest = serde_json::from_str(text).map_err(|_| "update.json không đọc được".to_string())?;
    if m.version.trim().is_empty() { return Err("update.json thiếu trường version".into()); }
    let sha_ok = m.sha256.len() == 64 && m.sha256.chars().all(|c| c.is_ascii_hexdigit());
    if !sha_ok { return Err("update.json thiếu hoặc sai trường sha256".into()); }
    m.sha256 = m.sha256.to_lowercase();
    if let Some(u) = &m.url {
        if !u.is_empty() { m.package_url = u.clone(); }
    }
    if m.package_url.is_empty() {
        match &m.file {
            Some(f) if !f.is_empty() && !f.contains("..") => {
                let base = manifest_url.split(['?', '#']).next().unwrap_or(manifest_url);
                let dir = match base.rfind('/') { Some(i) => &base[..=i], None => base };
                m.package_url = format!("{dir}{f}");
            }
            _ => return Err("update.json thiếu trường file hoặc url".into()),
        }
    }
    if !m.package_url.starts_with("https://") {
        return Err("gói cập nhật phải tải qua HTTPS".into());
    }
    if m.notes.is_none() { m.notes = Some(String::new()); }
    Ok(m)
}

/// Mọi hop redirect đều phải là HTTPS (port của Update.httpGet guard).
pub fn check_https(url: &str) -> Result<(), String> {
    if url.starts_with("https://") { Ok(()) } else { Err(format!("chỉ chấp nhận địa chỉ HTTPS: {url}")) }
}

/// Đồng hồ sai nếu năm < 2026 (port của clockLooksWrong).
pub fn clock_looks_wrong(year: i64) -> bool { year < 2026 }

/// Trạng thái job nền: file `status` gồm "state\nmessage".
pub fn set_status(work: &Path, state: &str, message: &str) -> std::io::Result<()> {
    fs::create_dir_all(work)?;
    fs::write(work.join("status"), format!("{state}\n{message}"))
}
pub fn read_status(work: &Path) -> Option<(String, String)> {
    let data = fs::read_to_string(work.join("status")).ok()?;
    let mut it = data.splitn(2, '\n');
    Some((it.next()?.to_string(), it.next().unwrap_or("").to_string()))
}

fn read_trimmed(work: &Path, name: &str) -> Option<String> {
    let d = fs::read_to_string(work.join(name)).ok()?;
    let t = d.trim().to_string();
    if t.is_empty() { None } else { Some(t) }
}
pub fn pending_version(work: &Path) -> Option<String> { read_trimmed(work, "pending") }
pub fn ready_version(work: &Path) -> Option<String> { read_trimmed(work, "ready") }
pub fn take_failed_version(work: &Path) -> Option<String> {
    let v = read_trimmed(work, "failed");
    let _ = fs::remove_file(work.join("failed"));
    v
}
pub fn discard(work: &Path) {
    let _ = fs::remove_dir_all(work.join("staging"));
    for n in ["ready", "status", PACKAGE_NAME] { let _ = fs::remove_file(work.join(n)); }
}
pub fn confirm(work: &Path) {
    let _ = fs::remove_file(work.join("pending"));
    let _ = fs::remove_dir_all(work.join("backup"));
    for n in ["added.txt", "status"] { let _ = fs::remove_file(work.join(n)); }
}

/// Giải nén .tar.gz vào dest, từ chối path traversal / link / mục đặc biệt.
/// Trả về số file đã ghi. Port của Update.unpack (qua tar+flate2 thay libarchive).
pub fn unpack(archive_path: &Path, dest: &Path, progress: &mut dyn FnMut(usize)) -> Result<usize, String> {
    let f = fs::File::open(archive_path).map_err(|_| "không mở được gói cập nhật".to_string())?;
    let gz = flate2::read::GzDecoder::new(f);
    let mut ar = tar::Archive::new(gz);
    let mut count = 0usize;
    let entries = ar.entries().map_err(|_| "gói cập nhật bị hỏng".to_string())?;
    for entry in entries {
        let mut e = entry.map_err(|_| "gói cập nhật bị hỏng".to_string())?;
        let rel = e.path().map_err(|_| "gói cập nhật bị hỏng".to_string())?
            .to_string_lossy().replace('\\', "/");
        let rel = rel.trim_start_matches("./").trim_end_matches('/').to_string();
        if rel.is_empty() || rel == "." { continue; }
        if !is_safe_path(&rel) {
            return Err(format!("gói cập nhật chứa đường dẫn không hợp lệ: {rel}"));
        }
        let kind = e.header().entry_type();
        let target = dest.join(&rel);
        if kind.is_dir() {
            fs::create_dir_all(&target).map_err(|e| e.to_string())?;
        } else if kind.is_file() {
            if let Some(p) = target.parent() { fs::create_dir_all(p).map_err(|e| e.to_string())?; }
            let mut out = fs::File::create(&target).map_err(|_| format!("không ghi được {rel}"))?;
            std::io::copy(&mut e, &mut out).map_err(|_| "gói cập nhật bị hỏng".to_string())?;
            count += 1;
            if count % 64 == 0 { progress(count); }
        } else {
            return Err(format!("gói cập nhật chứa mục không được phép (link/thiết bị): {rel}"));
        }
    }
    if count == 0 { return Err("gói cập nhật rỗng".into()); }
    Ok(count)
}

/// Port của Update.stage: giải nén vào staging, kiểm REQUIRED + kiến trúc, ghi ready.
/// Không đụng gì vào app dir.
pub fn stage(work: &Path, package_path: &Path, version: &str) -> Result<usize, String> {
    let staging = work.join("staging");
    let _ = fs::remove_dir_all(&staging);
    fs::create_dir_all(&staging).map_err(|e| e.to_string())?;
    let mut noop = |_: usize| {};
    let count = match unpack(package_path, &staging, &mut noop) {
        Ok(c) => c,
        Err(e) => { let _ = fs::remove_dir_all(&staging); return Err(e); }
    };
    for rel in REQUIRED {
        if !staging.join(rel).exists() {
            let _ = fs::remove_dir_all(&staging);
            return Err(format!("gói cập nhật thiếu {rel}"));
        }
    }
    if !is_arm64_elf(&staging.join(ARCH_CHECK)) {
        let _ = fs::remove_dir_all(&staging);
        return Err("gói cập nhật không đúng kiến trúc ARM64".into());
    }
    let _ = fs::remove_file(package_path);
    fs::write(work.join("ready"), version).map_err(|e| e.to_string())?;
    Ok(count)
}

/// Liệt kê file tương đối dưới root, đã sort (port của listFiles).
pub fn list_files(root: &Path) -> Vec<String> {
    let mut out = Vec::new();
    fn walk(dir: &Path, prefix: &str, out: &mut Vec<String>) {
        if let Ok(rd) = fs::read_dir(dir) {
            for e in rd.flatten() {
                let name = e.file_name().to_string_lossy().into_owned();
                let rel = if prefix.is_empty() { name.clone() } else { format!("{prefix}/{name}") };
                match e.file_type() {
                    Ok(t) if t.is_dir() => walk(&e.path(), &rel, out),
                    Ok(t) if t.is_file() => out.push(rel),
                    _ => {}
                }
            }
        }
    }
    walk(root, "", &mut out);
    out.sort();
    out
}

pub type Settings = BTreeMap<String, String>;
/// URL manifest: settings override (rỗng = tắt OTA), không có thì dùng build_info.
pub fn manifest_url(settings: Option<&Settings>, build_url: &str) -> String {
    match settings.and_then(|s| s.get("ritder_update_url")) {
        Some(v) => v.clone(),
        None => build_url.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn version_numeric() { assert!(is_newer("0.10.0", "0.9.9")); assert!(!is_newer("1.0", "1.0.0")); }
    #[test] fn safe() { assert!(is_safe_path("a..b/c")); assert!(!is_safe_path("a/../../b")); }
    #[test] fn protected_paths() { assert!(is_protected("userdata/x")); assert!(is_protected("settings.json")); assert!(!is_protected("frontend/x.lua")); }
}
