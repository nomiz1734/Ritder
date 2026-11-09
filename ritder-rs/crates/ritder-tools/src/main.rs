//! ritder-tools — port của tools/*.py của Ritder:
//!   build           (build.py)        ghép dist từ upstream đã ghim SHA-256 + overlay + 5 patch
//!   make-update     (make_update.py)  gói OTA tar.gz + update.json
//!   publish-release (publish_release.py) tạo GitHub Release (dry-run mặc định)
//!   make-icon       (make_icon.py)    sinh icon.png / koreader.png / koreader.svg
//!   emulate         (emulate.py)      phân tích tests/screens/*.lua -> kế hoạch chạy/chụp
//! Tải mạng / giải nén .tar.xz / WSL dùng công cụ hệ thống (curl, tar, wsl) khi có;
//! phần đó là host-dependent và được ghi rõ trong MIGRATION.md.
use ritder_core::buildtools;
use ritder_core::{emulate_plan, icon, sha256_file, sha256_hex};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

fn arg(args: &[String], name: &str) -> Option<String> {
    args.windows(2).find(|w| w[0] == name).map(|w| w[1].clone())
}
fn has(args: &[String], name: &str) -> bool { args.iter().any(|a| a == name) }
fn pos(args: &[String], skip: usize) -> Vec<String> {
    args.iter().skip(skip).filter(|a| !a.starts_with("--")).cloned().collect()
}

fn copy_tree(src: &Path, dst: &Path) -> std::io::Result<usize> {
    let mut count = 0;
    if !src.is_dir() { return Ok(0); }
    for e in fs::read_dir(src)? {
        let e = e?; let p = e.path(); let out = dst.join(e.file_name());
        if e.file_type()?.is_dir() { count += copy_tree(&p, &out)?; }
        else if !e.file_name().to_string_lossy().ends_with(".pyc") {
            if let Some(par) = out.parent() { fs::create_dir_all(par)?; }
            fs::copy(&p, &out)?; count += 1;
        }
    }
    Ok(count)
}

fn fetch_pinned(entry: &serde_json::Value, cache: &Path) -> Result<PathBuf, String> {
    let file = entry["file"].as_str().ok_or("upstream entry thiếu file")?;
    let want = entry["sha256"].as_str().ok_or("upstream entry thiếu sha256")?;
    let path = cache.join(file);
    if path.exists() && sha256_file(&path).as_deref() == Some(want) { return Ok(path); }
    fs::create_dir_all(cache).map_err(|e| e.to_string())?;
    let mut errors = Vec::new();
    for url in entry["urls"].as_array().cloned().unwrap_or_default() {
        let url = url.as_str().unwrap_or("");
        println!("  downloading {url}");
        let tmp = cache.join(format!("{file}.part"));
        let ok = Command::new("curl").args(["-fL", "--retry", "2", "-o"]).arg(&tmp).arg(url)
            .status().map(|s| s.success()).unwrap_or(false);
        if !ok { errors.push(format!("{url}: curl failed")); continue; }
        match sha256_file(&tmp) {
            Some(got) if got == want => { fs::rename(&tmp, &path).map_err(|e| e.to_string())?; return Ok(path); }
            Some(got) => { let _ = fs::remove_file(&tmp); errors.push(format!("{url}: SHA-256 {got} does not match upstream.json")); }
            None => errors.push(format!("{url}: cannot read download")),
        }
    }
    Err(format!("cannot fetch {file}:\n  {}", errors.join("\n  ")))
}

fn cmd_build(args: &[String]) -> Result<(), String> {
    let root = PathBuf::from(arg(args, "--root").unwrap_or_else(|| ".".into()));
    let dist_root = PathBuf::from(arg(args, "--out").unwrap_or_else(|| root.join("dist").to_string_lossy().into_owned()));
    let dist = dist_root.join("Ritder");
    let version = fs::read_to_string(root.join("VERSION")).map_err(|e| e.to_string())?.trim().to_string();
    let update_url = arg(args, "--update-url").or_else(|| {
        fs::read_to_string(root.join("update-url.txt")).ok().map(|s| s.trim().to_string())
    }).unwrap_or_default();
    let pins: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(root.join("upstream.json")).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    if dist_root.exists() { fs::remove_dir_all(&dist_root).map_err(|e| e.to_string())?; }
    fs::create_dir_all(&dist).map_err(|e| e.to_string())?;
    println!("Fetching upstream files");
    let cache = root.join("vendor/cache");
    let ko = fetch_pinned(&pins["koreader"], &cache)?;
    // Giải nén KOReader: prefix lib/koreader/ -> dist (dùng tar hệ thống cho .tar.xz).
    let stage = dist_root.join(".ko-stage");
    fs::create_dir_all(&stage).map_err(|e| e.to_string())?;
    let st = Command::new("tar").arg("-xJf").arg(&ko).arg("-C").arg(&stage).status().map_err(|e| e.to_string())?;
    if !st.success() { return Err("tar -xJf KOReader failed (cần xz trong tar hệ thống)".into()); }
    let count = copy_tree(&stage.join("lib/koreader"), &dist).map_err(|e| e.to_string())?;
    println!("  KOReader: {count} files");
    let _ = fs::remove_dir_all(&stage);
    // Runtime .deb: tách data.tar bằng parser ar của ritder-core rồi trích các file `extract`.
    if let Some(rt) = pins["runtime"].as_array() {
        for entry in rt {
            let deb = fetch_pinned(entry, &cache)?;
            let raw = fs::read(&deb).map_err(|e| e.to_string())?;
            let data_tar = buildtools::deb_data_member(&raw)?;
            let tmp = dist_root.join(".deb-data.tar");
            fs::write(&tmp, &data_tar).map_err(|e| e.to_string())?;
            let dstage = dist_root.join(".deb-stage");
            let st = Command::new("tar").arg("-xf").arg(&tmp).arg("-C").arg(&dstage).status();
            // tar cần thư mục đích tồn tại:
            if !dstage.exists() { fs::create_dir_all(&dstage).map_err(|e| e.to_string())?; }
            let st = if st.is_err() || !st.unwrap().success() {
                Command::new("tar").arg("-xf").arg(&tmp).arg("-C").arg(&dstage).status().map_err(|e| e.to_string())?
            } else { Command::new("true").status().map_err(|e| e.to_string())? };
            if !st.success() { return Err("tar extract .deb data failed".into()); }
            for want in entry["extract"].as_array().cloned().unwrap_or_default() {
                let want = want.as_str().unwrap_or("");
                let srcf = dstage.join(want);
                if !srcf.exists() { return Err(format!("{}: {want} not found", entry["file"])); }
                let base = Path::new(want).file_name().unwrap();
                fs::create_dir_all(dist.join("sys")).map_err(|e| e.to_string())?;
                fs::copy(&srcf, dist.join("sys").join(base)).map_err(|e| e.to_string())?;
            }
            println!("  runtime: {}", entry["file"]);
            let _ = fs::remove_file(&tmp); let _ = fs::remove_dir_all(&dstage);
        }
    }
    // sdcv wrapper
    let sdcv = dist.join("sdcv");
    if sdcv.exists() {
        fs::rename(&sdcv, dist.join("sdcv.bin")).map_err(|e| e.to_string())?;
        fs::write(&sdcv, buildtools::sdcv_wrapper()).map_err(|e| e.to_string())?;
    }
    println!("Applying the Ritder overlay");
    let overlay = root.join("overlay");
    println!("  overlay: {} files", copy_tree(&overlay, &dist).map_err(|e| e.to_string())?);
    for patch in buildtools::PATCHES {
        let p = dist.join(patch.file);
        let content = fs::read_to_string(&p).map_err(|_| format!("patch target missing: {}", patch.file))?;
        let patched = buildtools::apply_patch(&content, &patch)?;
        fs::write(&p, patched).map_err(|e| e.to_string())?;
        println!("  patched {}", patch.file);
    }
    let bi_dir = dist.join("frontend/ritder");
    fs::create_dir_all(&bi_dir).map_err(|e| e.to_string())?;
    let ko_ver = pins["koreader"]["version"].as_str().unwrap_or("?");
    fs::write(bi_dir.join("build_info.json"), buildtools::build_info_json(&version, &update_url, ko_ver)).map_err(|e| e.to_string())?;
    copy_tree(&root.join("package/stock"), &dist).map_err(|e| e.to_string())?;
    // Zip Ritder-stock.zip bằng crate zip (thay zipfile của build.py).
    let zip_path = dist_root.join("Ritder-stock.zip");
    {
        let f = fs::File::create(&zip_path).map_err(|e| e.to_string())?;
        let mut zw = zip::ZipWriter::new(f);
        let opts = zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
        let mut files: Vec<PathBuf> = Vec::new();
        fn walk(d: &Path, o: &mut Vec<PathBuf>) { if let Ok(rd) = fs::read_dir(d) { for e in rd.flatten() { if e.file_type().map(|t| t.is_dir()).unwrap_or(false) { walk(&e.path(), o); } else { o.push(e.path()); } } } }
        walk(&dist, &mut files); files.sort();
        for full in files {
            let rel = full.strip_prefix(&dist).unwrap().to_string_lossy().replace('\\', "/");
            let mode = buildtools::file_mode(&rel);
            zw.start_file(format!("Ritder/{rel}"), opts.unix_permissions(0o100000 | mode)).map_err(|e| e.to_string())?;
            let data = fs::read(&full).map_err(|e| e.to_string())?;
            std::io::Write::write_all(&mut zw, &data).map_err(|e| e.to_string())?;
        }
        zw.finish().map_err(|e| e.to_string())?;
    }
    println!("Package ready: {} (Ritder {version}, KOReader {ko_ver})", dist.display());
    Ok(())
}

fn cmd_make_update(args: &[String]) -> Result<(), String> {
    let p = pos(args, 1);
    if p.len() < 3 { return Err("usage: ritder-tools make-update <dist/Ritder> <out dir> <version> [notes|notes-file]".into()); }
    let (src, out, version) = (PathBuf::from(&p[0]), PathBuf::from(&p[1]), p[2].clone());
    let mut notes = p.get(3).cloned().unwrap_or_default();
    if !notes.is_empty() && Path::new(&notes).is_file() {
        notes = fs::read_to_string(&notes).map_err(|e| e.to_string())?.trim().to_string();
    }
    fs::create_dir_all(&out).map_err(|e| e.to_string())?;
    let pkg = out.join("ritder-update.tar.gz");
    let mut count = 0usize;
    {
        let f = fs::File::create(&pkg).map_err(|e| e.to_string())?;
        let gz = flate2::write::GzEncoder::new(f, flate2::Compression::best());
        let mut tb = tar::Builder::new(gz);
        let mut files: Vec<PathBuf> = Vec::new();
        fn walk(d: &Path, o: &mut Vec<PathBuf>) { if let Ok(rd) = fs::read_dir(d) { for e in rd.flatten() { if e.file_type().map(|t| t.is_dir()).unwrap_or(false) { walk(&e.path(), o); } else { o.push(e.path()); } } } }
        walk(&src, &mut files); files.sort();
        for full in files {
            let rel = full.strip_prefix(&src).unwrap().to_string_lossy().replace('\\', "/");
            if !buildtools::ota_included(&rel) { continue; }
            let data = fs::read(&full).map_err(|e| e.to_string())?;
            let mut h = tar::Header::new_gnu();
            h.set_size(data.len() as u64); h.set_mode(buildtools::file_mode(&rel)); h.set_uid(0); h.set_gid(0);
            h.set_cksum();
            tb.append_data(&mut h, &rel, data.as_slice()).map_err(|e| e.to_string())?;
            count += 1;
        }
        tb.finish().map_err(|e| e.to_string())?;
    }
    let data = fs::read(&pkg).map_err(|e| e.to_string())?;
    let manifest = serde_json::json!({"version": version, "notes": notes, "file": "ritder-update.tar.gz",
        "sha256": sha256_hex(&data), "size": data.len()});
    fs::write(out.join("update.json"), serde_json::to_string_pretty(&manifest).unwrap()).map_err(|e| e.to_string())?;
    println!("OTA package: {} ({count} files, {} bytes)", pkg.display(), data.len());
    Ok(())
}

fn cmd_publish(args: &[String]) -> Result<(), String> {
    let root = PathBuf::from(arg(args, "--root").unwrap_or_else(|| ".".into()));
    let dry = !has(args, "--execute");
    let url_txt = fs::read_to_string(root.join("update-url.txt")).map_err(|e| e.to_string())?;
    let repo = url_txt.trim().trim_start_matches("https://github.com/")
        .split("/releases").next().unwrap_or("").to_string();
    if !repo.contains('/') { return Err("update-url.txt phải trỏ tới https://github.com/<user>/<repo>/releases/...".into()); }
    let version = fs::read_to_string(root.join("VERSION")).map_err(|e| e.to_string())?.trim().to_string();
    let manifest: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(root.join("dist/update/update.json")).map_err(|_| "thiếu dist/update/update.json: hãy chạy build trước".to_string())?)
        .map_err(|e| e.to_string())?;
    if manifest["version"].as_str() != Some(version.as_str()) {
        return Err(format!("dist/ là bản {}, VERSION là {version}: hãy build lại", manifest["version"]));
    }
    let assets = ["dist/update/update.json", "dist/update/ritder-update.tar.gz", "dist/Ritder-stock.zip"];
    for a in assets { if !root.join(a).exists() { return Err(format!("thiếu {a}: hãy build trước")); } }
    let notes = fs::read_to_string(root.join("release-notes.txt")).unwrap_or_default();
    let body = format!("{}\n\n**Cài lần đầu:** giải nén `Ritder-stock.zip`, chép thư mục `Ritder` vào `Apps/` trên thẻ nhớ.\n**Đã cài rồi:** mở Ritder → MENU → Kiểm tra cập nhật (OTA).\n\n`update.json` và `ritder-update.tar.gz` là file dùng cho OTA.", notes.trim());
    println!("repo={repo} tag=v{version} assets={assets:?}");
    if dry {
        println!("DRY-RUN (mặc định an toàn): chưa tạo release. Body:\n{body}");
        println!("Chạy lại với --execute và biến môi trường GH_TOKEN (hoặc `gh auth login`) để phát hành thật.");
        return Ok(());
    }
    let token = std::env::var("GH_TOKEN").map_err(|_| "cần GH_TOKEN khi --execute (bản gốc lấy token qua git credential fill)".to_string())?;
    let payload = serde_json::json!({"tag_name": format!("v{version}"), "target_commitish": "main",
        "name": format!("Ritder {version}"), "body": body, "make_latest": "true"}).to_string();
    let tmp = std::env::temp_dir().join("ritder-release.json");
    fs::write(&tmp, &payload).map_err(|e| e.to_string())?;
    let out = Command::new("curl").args(["-sf", "-X", "POST",
        "-H", &format!("Authorization: Bearer {token}"), "-H", "Accept: application/vnd.github+json",
        "--data-binary", &format!("@{}", tmp.display())])
        .arg(format!("https://api.github.com/repos/{repo}/releases"))
        .output().map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err(format!("GitHub trả lỗi: {}", String::from_utf8_lossy(&out.stderr)));
    }
    let rel: serde_json::Value = serde_json::from_slice(&out.stdout).map_err(|e| e.to_string())?;
    let upload = rel["upload_url"].as_str().unwrap_or("").split('{').next().unwrap_or("").to_string();
    for a in assets {
        let name = Path::new(a).file_name().unwrap().to_string_lossy().into_owned();
        let st = Command::new("curl").args(["-sf", "-X", "POST",
            "-H", &format!("Authorization: Bearer {token}"), "-H", "Content-Type: application/octet-stream",
            "--data-binary", &format!("@{}", root.join(a).display())])
            .arg(format!("{upload}?name={name}")).status().map_err(|e| e.to_string())?;
        if !st.success() { return Err(format!("upload {name} failed")); }
        println!("  uploaded {name}");
    }
    println!("Đã phát hành {version}: {}", rel["html_url"].as_str().unwrap_or(""));
    Ok(())
}

fn cmd_make_icon(args: &[String]) -> Result<(), String> {
    let root = PathBuf::from(arg(args, "--root").unwrap_or_else(|| ".".into()));
    let icon_path = root.join("package/stock/icon.png");
    if let Some(p) = icon_path.parent() { fs::create_dir_all(p).map_err(|e| e.to_string())?; }
    fs::write(&icon_path, icon::write_png(&icon::launcher_icon())).map_err(|e| e.to_string())?;
    println!("wrote {}", icon_path.display());
    let res = root.join("overlay/resources");
    fs::create_dir_all(&res).map_err(|e| e.to_string())?;
    fs::write(res.join("koreader.png"), icon::write_png(&icon::tile(256))).map_err(|e| e.to_string())?;
    fs::write(res.join("koreader.svg"), icon::svg()).map_err(|e| e.to_string())?;
    println!("wrote {}\\koreader.png, koreader.svg", res.display());
    Ok(())
}

fn cmd_emulate(args: &[String]) -> Result<(), String> {
    if has(args, "--setup") {
        println!("HOST-DEPENDENT: tạo WSL1 distro {} cần máy Windows + wsl --import (xem MIGRATION.md). Trên máy này chỉ sinh kế hoạch.", emulate_plan::DISTRO);
        return Ok(());
    }
    let scripts_dir = PathBuf::from(arg(args, "--scripts").unwrap_or_else(|| "tests/screens".into()));
    let shots = PathBuf::from(arg(args, "--out").unwrap_or_else(|| "dist/emulator/shots".into()));
    // Tham số vị trí = tên kịch bản lọc; loại giá trị của --scripts/--out.
    let mut filter: Vec<String> = Vec::new();
    {
        let mut it = args.iter().skip(1).peekable();
        while let Some(a) = it.next() {
            if a == "--scripts" || a == "--out" { it.next(); }
            else if !a.starts_with("--") { filter.push(a.clone()); }
        }
    }
    let mut names: Vec<PathBuf> = fs::read_dir(&scripts_dir).map_err(|e| e.to_string())?
        .flatten().map(|e| e.path()).filter(|p| p.extension().map(|x| x == "lua").unwrap_or(false)).collect();
    names.sort();
    let mut failed = 0;
    for p in names {
        let stem = p.file_stem().unwrap().to_string_lossy().into_owned();
        if !filter.is_empty() && !filter.iter().any(|f| stem.contains(f)) { continue; }
        match emulate_plan::plan_for(&p, &shots) {
            Ok(plan) => {
                println!("== {} : {} bước, {} ảnh chụp -> {}", plan.script, plan.steps.len(), plan.shots.len(), plan.out_dir);
                for s in &plan.steps { println!("   {s:?}"); }
                println!("   env: {:?}", emulate_plan::emu_env("dist/emulator/Ritder", &p.to_string_lossy(), &plan.out_dir, "dist/emulator/Books", "dist/update/ritder-update.tar.gz"));
                println!("   (chạy thật cần WSL1/KOReader x86_64 — host-dependent)");
            }
            Err(e) => { failed += 1; println!("== {stem}: LỖI {e}"); }
        }
    }
    if failed > 0 { Err(format!("{failed} kịch bản lỗi")) } else { Ok(()) }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let sub = args.first().cloned().unwrap_or_default();
    let rest = &args;
    let result = match sub.as_str() {
        "build" => cmd_build(rest),
        "make-update" => cmd_make_update(rest),
        "publish-release" => cmd_publish(rest),
        "make-icon" => cmd_make_icon(rest),
        "emulate" => cmd_emulate(rest),
        _ => Err("usage: ritder-tools <build|make-update|publish-release|make-icon|emulate> [options]".into()),
    };
    match result { Ok(()) => ExitCode::from(0), Err(e) => { eprintln!("ritder-tools: {e}"); ExitCode::from(1) } }
}

// Giữ BTreeMap được dùng (map phụ trợ cho mở rộng sau).
#[allow(dead_code)]
fn _unused(_: BTreeMap<String, String>) {}
