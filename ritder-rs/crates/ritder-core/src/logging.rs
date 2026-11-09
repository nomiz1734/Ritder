//! Port của package/stock/logging.sh: lịch sử chạy giữ 800 dòng, crash.log rotation.
use std::fs;
use std::path::Path;

pub const KEEP_LINES: usize = 800;
pub const UPDATE_EXIT: i32 = 42;
pub const RESTART_EXIT: i32 = 85;

/// ritder_rotate_logs: crash.log -> crash.log.1; ritder.log cắt còn 800 dòng cuối.
pub fn rotate_logs(userdata: &Path) {
    let crash = userdata.join("crash.log");
    if crash.exists() { let _ = fs::rename(&crash, userdata.join("crash.log.1")); }
    trim_history(&userdata.join("ritder.log"), KEEP_LINES);
}
pub fn trim_history(path: &Path, keep: usize) {
    if let Ok(data) = fs::read_to_string(path) {
        let lines: Vec<&str> = data.lines().collect();
        if lines.len() > keep {
            let kept = &lines[lines.len() - keep..];
            let _ = fs::write(path, kept.join("\n") + "\n");
        }
    }
}
pub fn note(userdata: &Path, timestamp: &str, message: &str) {
    crate::install::append_line(&userdata.join("ritder.log"), &format!("{timestamp} {message}"));
}

/// Trích version từ nội dung build_info (bản Rust ghi build_info.json; vẫn đọc được dạng version = "x").
pub fn extract_version(build_info_text: &str) -> Option<String> {
    for line in build_info_text.lines() {
        if let Some(i) = line.find("version") {
            let rest = &line[i + "version".len()..];
            let start = rest.find('"')? + 1;
            let end = rest[start..].find('"')? + start;
            // Bỏ qua koreader_version khi cần version chính: ưu tiên dòng không chứa koreader.
            if !line.contains("koreader") { return Some(rest[start..end].to_string()); }
        }
    }
    // Fallback JSON: "version": "x"
    let v: serde_json::Value = serde_json::from_str(build_info_text).ok()?;
    v.get("version")?.as_str().map(|s| s.to_string())
}

pub fn session_start_message(version: &str, kernel: &str, ram_note: &str) -> String {
    format!("mở app: Ritder {version}, kernel {kernel}, {ram_note}")
}
/// (thông điệp, có phải crash không) — port của ritder_session_end.
pub fn session_end_message(code: i32) -> (String, bool) {
    match code {
        0 => ("thoát bình thường".into(), false),
        42 => ("thoát để cài bản cập nhật (mã 42)".into(), false),
        85 => ("khởi động lại theo yêu cầu (mã 85)".into(), false),
        c => (format!("thoát bất thường (mã {c})"), true),
    }
}
/// Ghi kết thúc phiên: crash thì ghi file `crashed` + 40 dòng cuối crash.log vào lịch sử.
pub fn session_end(userdata: &Path, timestamp: &str, code: i32) {
    let (msg, crashed) = session_end_message(code);
    note(userdata, timestamp, &msg);
    if crashed {
        let _ = fs::write(userdata.join("crashed"), format!("{code}"));
        if let Some(tail) = crate::diagnostics::tail_lines(&userdata.join("crash.log"), 40) {
            crate::install::append_line(&userdata.join("ritder.log"), "--- 40 dòng cuối của crash.log ---");
            for l in tail.lines() { crate::install::append_line(&userdata.join("ritder.log"), l); }
            crate::install::append_line(&userdata.join("ritder.log"), "--- hết ---");
        }
    }
}
