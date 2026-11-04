use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Component, Path, PathBuf};
use std::process::{Command, ExitCode};

const UPDATE_EXIT: i32 = 42;
const RESTART_EXIT: i32 = 85;

struct Config {
    app_dir: PathBuf,
    userdata: PathBuf,
    loader: PathBuf,
    libpath: String,
    luajit: PathBuf,
    reader: PathBuf,
}

fn safe_relative(path: &Path) -> io::Result<()> {
    if path.is_absolute() {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "absolute update path"));
    }
    for part in path.components() {
        match part {
            Component::Normal(_) => {}
            _ => return Err(io::Error::new(io::ErrorKind::InvalidData, "unsafe update path")),
        }
    }
    Ok(())
}

fn write_text(path: &Path, value: &str) -> io::Result<()> {
    if let Some(parent) = path.parent() { fs::create_dir_all(parent)?; }
    let mut f = File::create(path)?;
    f.write_all(value.as_bytes())
}

fn append_log(userdata: &Path, message: &str) {
    let path = userdata.join("update.log");
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(f, "{}", message);
    }
}

fn files_under(root: &Path, current: &Path, out: &mut Vec<PathBuf>) -> io::Result<()> {
    for entry in fs::read_dir(current)? {
        let entry = entry?;
        let kind = entry.file_type()?;
        let path = entry.path();
        if kind.is_symlink() {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "symlink in update"));
        }
        if kind.is_dir() {
            files_under(root, &path, out)?;
        } else if kind.is_file() {
            let rel = path.strip_prefix(root).map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "staging path escaped"))?.to_path_buf();
            safe_relative(&rel)?;
            out.push(rel);
        } else {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "special file in update"));
        }
    }
    Ok(())
}

fn move_tree(root: &Path, target: &Path) -> io::Result<()> {
    if !target.exists() { return Ok(()); }
    let mut files = Vec::new();
    files_under(target, target, &mut files)?;
    files.sort();
    for rel in files {
        let src = target.join(&rel);
        let dst = root.join(&rel);
        if let Some(parent) = dst.parent() { fs::create_dir_all(parent)?; }
        fs::rename(src, dst)?;
    }
    Ok(())
}

fn restore_backup(cfg: &Config) -> io::Result<()> {
    let upd = cfg.userdata.join("update");
    let added = upd.join("added.txt");
    if added.exists() {
        let mut text = String::new(); File::open(&added)?.read_to_string(&mut text)?;
        for line in text.lines() {
            let rel = Path::new(line);
            if line.is_empty() { continue; }
            safe_relative(rel)?;
            let _ = fs::remove_file(cfg.app_dir.join(rel));
        }
    }
    let backup = upd.join("backup");
    if backup.exists() { move_tree(&cfg.app_dir, &backup)?; }
    let _ = fs::remove_dir_all(upd.join("backup"));
    let _ = fs::remove_dir_all(upd.join("staging"));
    for name in ["added.txt", "installing", "pending", "ready", "restore.txt"] {
        let _ = fs::remove_file(upd.join(name));
    }
    Ok(())
}

fn install_staged(cfg: &Config) -> io::Result<()> {
    let upd = cfg.userdata.join("update");
    let staging = upd.join("staging");
    if !staging.is_dir() { return Err(io::Error::new(io::ErrorKind::NotFound, "staging directory missing")); }
    let version = fs::read_to_string(upd.join("ready")).unwrap_or_else(|_| "?".into());
    append_log(&cfg.userdata, &format!("installing update {}", version.trim()));
    let backup = upd.join("backup");
    let _ = fs::remove_dir_all(&backup);
    fs::create_dir_all(&backup)?;
    write_text(&upd.join("installing"), version.trim())?;
    write_text(&upd.join("added.txt"), "")?;

    let mut files = Vec::new(); files_under(&staging, &staging, &mut files)?; files.sort();
    let result = (|| -> io::Result<()> {
        for rel in files {
            let src = staging.join(&rel); let dst = cfg.app_dir.join(&rel);
            if dst.exists() {
                let old = backup.join(&rel);
                if let Some(parent) = old.parent() { fs::create_dir_all(parent)?; }
                fs::rename(&dst, &old)?;
            } else {
                let mut f = OpenOptions::new().append(true).open(upd.join("added.txt"))?;
                writeln!(f, "{}", rel.to_string_lossy())?;
            }
            if let Some(parent) = dst.parent() { fs::create_dir_all(parent)?; }
            fs::rename(src, dst)?;
        }
        Ok(())
    })();
    if let Err(err) = result {
        append_log(&cfg.userdata, &format!("update failed: {}", err));
        let _ = restore_backup(cfg);
        let _ = write_text(&upd.join("failed"), version.trim());
        return Err(err);
    }
    write_text(&upd.join("pending"), version.trim())?;
    let _ = fs::remove_dir_all(staging);
    for name in ["ready", "installing", "package.tar.gz"] { let _ = fs::remove_file(upd.join(name)); }
    append_log(&cfg.userdata, &format!("update {} installed", version.trim()));
    Ok(())
}

fn run_reader(cfg: &Config) -> io::Result<i32> {
    let status = Command::new(&cfg.loader)
        .arg("--library-path").arg(&cfg.libpath)
        .arg(&cfg.luajit).arg(&cfg.reader)
        .status()?;
    Ok(status.code().unwrap_or(1))
}

fn parse_config() -> io::Result<Config> {
    let mut args = env::args_os().skip(1);
    let next = |args: &mut dyn Iterator<Item = std::ffi::OsString>, name: &str| -> io::Result<PathBuf> {
        match args.next() { Some(v) => Ok(PathBuf::from(v)), None => Err(io::Error::new(io::ErrorKind::InvalidInput, format!("missing {}", name))) }
    };
    let app_dir = next(&mut args, "--app-dir")?;
    let userdata = next(&mut args, "--userdata")?;
    let loader = next(&mut args, "--loader")?;
    let libpath = next(&mut args, "--libpath")?.to_string_lossy().into_owned();
    let luajit = next(&mut args, "--luajit")?;
    let reader = next(&mut args, "--reader")?;
    Ok(Config { app_dir, userdata, loader, libpath, luajit, reader })
}

fn main() -> ExitCode {
    let cfg = match parse_config() { Ok(v) => v, Err(e) => { eprintln!("ritder-launcher: {}", e); return ExitCode::from(1); } };
    let upd = cfg.userdata.join("update");
    if upd.join("installing").exists() {
        let _ = restore_backup(&cfg);
    }
    if upd.join("ready").exists() && upd.join("staging").is_dir() {
        if let Err(e) = install_staged(&cfg) { eprintln!("ritder-launcher: update install failed: {}", e); }
    }
    loop {
        let code = match run_reader(&cfg) { Ok(v) => v, Err(e) => { eprintln!("ritder-launcher: {}", e); 1 } };
        if code == UPDATE_EXIT || code == RESTART_EXIT { continue; }
        if code != 0 && upd.join("pending").exists() && upd.join("backup").is_dir() {
            let _ = restore_backup(&cfg);
            let _ = write_text(&upd.join("rolled_back"), "1");
            continue;
        }
        return ExitCode::from((code.clamp(0, 255)) as u8);
    }
}

#[cfg(test)]
mod tests {
    use super::safe_relative;
    use std::path::Path;
    #[test] fn rejects_escape_paths() { assert!(safe_relative(Path::new("../x")).is_err()); assert!(safe_relative(Path::new("/x")).is_err()); }
    #[test] fn accepts_nested_paths() { assert!(safe_relative(Path::new("frontend/ui.lua")).is_ok()); }
}
