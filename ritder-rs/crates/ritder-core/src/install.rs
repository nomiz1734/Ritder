//! Port của package/stock/install.sh + logic giao dịch của rust/ritder-launcher gốc:
//! cài staged update với backup/rollback. Dùng chung cho launcher và ritder-tools.
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Component, Path, PathBuf};

/// Từ launcher gốc: chỉ chấp nhận đường dẫn tương đối gồm các component Normal.
pub fn safe_relative(path: &Path) -> io::Result<()> {
    if path.is_absolute() {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "absolute update path"));
    }
    for part in path.components() {
        match part { Component::Normal(_) => {}, _ => return Err(io::Error::new(io::ErrorKind::InvalidData, "unsafe update path")) }
    }
    Ok(())
}

/// Kiểm tra dạng chuỗi như install.sh: rỗng / tuyệt đối / chứa ".." đều không an toàn.
/// Lưu ý: shell gốc dùng case *..* nên "a..b" cũng bị loại ở tầng shell; giữ đúng hành vi đó
/// cho restore từ added.txt, còn safe_relative (Path) là kiểm tra của launcher gốc.
pub fn shell_path_unsafe(s: &str) -> bool { s.is_empty() || s.starts_with('/') || s.contains("..") }

pub fn write_text(path: &Path, value: &str) -> io::Result<()> {
    if let Some(p) = path.parent() { fs::create_dir_all(p)?; }
    let mut f = File::create(path)?; f.write_all(value.as_bytes())
}
pub fn append_line(path: &Path, message: &str) {
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(f, "{message}");
    }
}

pub fn files_under(root: &Path, current: &Path, out: &mut Vec<PathBuf>) -> io::Result<()> {
    for entry in fs::read_dir(current)? {
        let entry = entry?; let kind = entry.file_type()?; let path = entry.path();
        if kind.is_symlink() { return Err(io::Error::new(io::ErrorKind::InvalidData, "symlink in update")); }
        if kind.is_dir() { files_under(root, &path, out)?; }
        else if kind.is_file() {
            let rel = path.strip_prefix(root).map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "staging path escaped"))?.to_path_buf();
            safe_relative(&rel)?; out.push(rel);
        } else { return Err(io::Error::new(io::ErrorKind::InvalidData, "special file in update")); }
    }
    Ok(())
}

fn move_tree(root: &Path, target: &Path) -> io::Result<()> {
    if !target.exists() { return Ok(()); }
    let mut files = Vec::new(); files_under(target, target, &mut files)?; files.sort();
    for rel in files {
        let src = target.join(&rel); let dst = root.join(&rel);
        if let Some(p) = dst.parent() { fs::create_dir_all(p)?; }
        if dst.exists() { fs::remove_file(&dst)?; }
        fs::rename(src, dst)?;
    }
    Ok(())
}

/// Port của ritder_restore_backup / restore_backup của launcher gốc.
pub fn restore_backup(app_dir: &Path, userdata: &Path) -> io::Result<()> {
    let upd = userdata.join("update");
    let added = upd.join("added.txt");
    if added.exists() {
        let mut text = String::new(); File::open(&added)?.read_to_string(&mut text)?;
        for line in text.lines() {
            if line.is_empty() { continue; }
            let rel = Path::new(line); safe_relative(rel)?;
            let _ = fs::remove_file(app_dir.join(rel));
        }
    }
    let backup = upd.join("backup");
    if backup.exists() { move_tree(app_dir, &backup)?; }
    let _ = fs::remove_dir_all(upd.join("backup"));
    let _ = fs::remove_dir_all(upd.join("staging"));
    for name in ["added.txt", "installing", "pending", "ready", "restore.txt"] {
        let _ = fs::remove_file(upd.join(name));
    }
    Ok(())
}

/// Port của ritder_install_staged / install_staged của launcher gốc.
/// Lỗi giữa chừng -> rollback ngay + ghi file `failed`.
pub fn install_staged(app_dir: &Path, userdata: &Path) -> io::Result<()> {
    let upd = userdata.join("update");
    let staging = upd.join("staging");
    if !staging.is_dir() { return Err(io::Error::new(io::ErrorKind::NotFound, "staging directory missing")); }
    let version = fs::read_to_string(upd.join("ready")).unwrap_or_else(|_| "?".into());
    let version = version.trim().to_string();
    append_line(&userdata.join("update.log"), &format!("installing update {version}"));
    let backup = upd.join("backup");
    let _ = fs::remove_dir_all(&backup); fs::create_dir_all(&backup)?;
    write_text(&upd.join("installing"), &version)?;
    write_text(&upd.join("added.txt"), "")?;
    let mut files = Vec::new(); files_under(&staging, &staging, &mut files)?; files.sort();
    let result = (|| -> io::Result<()> {
        for rel in &files {
            let src = staging.join(rel); let dst = app_dir.join(rel);
            if dst.exists() {
                let old = backup.join(rel);
                if let Some(p) = old.parent() { fs::create_dir_all(p)?; }
                fs::rename(&dst, &old)?;
            } else {
                let mut f = OpenOptions::new().append(true).open(upd.join("added.txt"))?;
                writeln!(f, "{}", rel.to_string_lossy())?;
            }
            if let Some(p) = dst.parent() { fs::create_dir_all(p)?; }
            fs::rename(src, dst)?;
        }
        Ok(())
    })();
    if let Err(err) = result {
        append_line(&userdata.join("update.log"), &format!("update failed: {err}"));
        let _ = restore_backup(app_dir, userdata);
        let _ = write_text(&upd.join("failed"), &version);
        return Err(err);
    }
    write_text(&upd.join("pending"), &version)?;
    let _ = fs::remove_dir_all(staging);
    for name in ["ready", "installing", "package.tar.gz"] { let _ = fs::remove_file(upd.join(name)); }
    append_line(&userdata.join("update.log"), &format!("update {version} installed"));
    Ok(())
}
