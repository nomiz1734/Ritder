//! Ritder native supervisor — giữ nguyên hành vi của rust/ritder-launcher/src/main.rs gốc
//! (193 dòng: install staged update an toàn, backup/rollback, exit codes 42/85,
//! pending/rolled_back) và hấp thụ thêm package/stock/launch.sh + logging.sh:
//! vòng đời tiến trình, ritder.log giữ 800 dòng, crash.log rotation, cài staged
//! update trước khi chạy. Logic giao dịch nằm ở ritder_core::install (port của
//! install.sh + launcher gốc), logic log ở ritder_core::logging (port của logging.sh).
use ritder_core::install::{install_staged, restore_backup, write_text};
use ritder_core::logging;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, ExitCode};
use std::time::{SystemTime, UNIX_EPOCH};

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

/// Timestamp "YYYY-MM-DD HH:MM:SS" (UTC) từ SystemTime — thay `date` của shell.
fn now_string() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    let days = secs.div_euclid(86400);
    let rem = secs.rem_euclid(86400);
    let (h, m, s) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    // Thuật toán civil-from-days (Howard Hinnant).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let yr = if mo <= 2 { y + 1 } else { y };
    format!("{yr:04}-{mo:02}-{d:02} {h:02}:{m:02}:{s:02}")
}

fn run_reader(cfg: &Config) -> std::io::Result<i32> {
    // Đầu ra của reader được launch shell (hoặc tiến trình cha) chuyển vào crash.log
    // như bản gốc; supervisor không tự mở file log cho tiến trình con.
    let status = Command::new(&cfg.loader)
        .arg("--library-path").arg(&cfg.libpath)
        .arg(&cfg.luajit).arg(&cfg.reader)
        .status()?;
    Ok(status.code().unwrap_or(1))
}

fn parse_config() -> std::io::Result<Config> {
    let args: Vec<std::ffi::OsString> = env::args_os().skip(1).collect();
    // Hỗ trợ cả hai dạng: cờ --app-dir <path> ... (API gốc) và 6 tham số vị trí
    // như launch.sh gọi: <progdir> <userdata> <loader> <libpath> <luajit> <reader>.
    let mut values: Vec<PathBuf> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].to_string_lossy().into_owned();
        if a.starts_with("--") {
            i += 1;
            if i >= args.len() {
                return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, format!("missing value for {a}")));
            }
            values.push(PathBuf::from(&args[i]));
        } else {
            values.push(PathBuf::from(&args[i]));
        }
        i += 1;
    }
    if values.len() < 6 {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,
            "usage: ritder-launcher [--app-dir] <dir> [--userdata] <dir> [--loader] <p> [--libpath] <s> [--luajit] <p> [--reader] <p>"));
    }
    Ok(Config {
        app_dir: values[0].clone(), userdata: values[1].clone(), loader: values[2].clone(),
        libpath: values[3].to_string_lossy().into_owned(), luajit: values[4].clone(), reader: values[5].clone(),
    })
}

fn reader_version(app_dir: &std::path::Path) -> String {
    // Ưu tiên build_info.json (bản Rust); tương thích build_info.lua cũ.
    for name in ["frontend/ritder/build_info.json", "frontend/ritder/build_info.lua"] {
        if let Ok(text) = fs::read_to_string(app_dir.join(name)) {
            if let Some(v) = logging::extract_version(&text) { return v; }
        }
    }
    "?".into()
}

fn main() -> ExitCode {
    let cfg = match parse_config() {
        Ok(v) => v,
        Err(e) => { eprintln!("ritder-launcher: {e}"); return ExitCode::from(1); }
    };
    let upd = cfg.userdata.join("update");
    let _ = fs::create_dir_all(&cfg.userdata);
    // launch.sh gốc: seed thư mục update phải tồn tại trước install/rollback.
    let _ = fs::create_dir_all(&upd);
    if upd.join("installing").exists() {
        let _ = restore_backup(&cfg.app_dir, &cfg.userdata);
    }
    if upd.join("ready").exists() && upd.join("staging").is_dir() {
        if let Err(e) = install_staged(&cfg.app_dir, &cfg.userdata) {
            eprintln!("ritder-launcher: update install failed: {e}");
        }
    }
    loop {
        logging::rotate_logs(&cfg.userdata);
        let version = reader_version(&cfg.app_dir);
        logging::note(&cfg.userdata, &now_string(),
            &logging::session_start_message(&version, "?", ""));
        let code = match run_reader(&cfg) {
            Ok(v) => v,
            Err(e) => { eprintln!("ritder-launcher: {e}"); 1 }
        };
        logging::session_end(&cfg.userdata, &now_string(), code);
        if code == UPDATE_EXIT || code == RESTART_EXIT { continue; }
        if code != 0 && upd.join("pending").exists() && upd.join("backup").is_dir() {
            let _ = restore_backup(&cfg.app_dir, &cfg.userdata);
            let _ = write_text(&upd.join("rolled_back"), "1");
            continue;
        }
        return ExitCode::from(code.clamp(0, 255) as u8);
    }
}

#[cfg(test)]
mod tests {
    // Tên test giữ từ launcher gốc (safe_relative nay ở ritder_core::install).
    use ritder_core::install::safe_relative;
    use std::path::Path;
    #[test] fn rejects_escape_paths() { assert!(safe_relative(Path::new("../x")).is_err()); assert!(safe_relative(Path::new("/x")).is_err()); }
    #[test] fn accepts_nested_paths() { assert!(safe_relative(Path::new("frontend/ui.lua")).is_ok()); }
    #[test] fn timestamp_shape() { let s = super::now_string(); assert_eq!(s.len(), 19); assert_eq!(&s[4..5], "-"); }
}
