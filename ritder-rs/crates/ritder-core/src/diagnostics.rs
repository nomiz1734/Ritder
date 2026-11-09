//! Port của frontend/ritder/diagnostics.lua: gom log tail có giới hạn + device info.
use std::fs;
use std::path::{Path, PathBuf};

pub const REPORT_NAME: &str = "ritder-log.txt";
pub const MAX_READ_BYTES: usize = 256 * 1024;
pub struct TailSpec { pub file: &'static str, pub lines: usize, pub title: &'static str }
pub const TAILS: [TailSpec; 4] = [
    TailSpec { file: "ritder.log", lines: 120, title: "lịch sử chạy" },
    TailSpec { file: "update.log", lines: 60, title: "lịch sử cập nhật" },
    TailSpec { file: "crash.log", lines: 250, title: "log lần chạy này" },
    TailSpec { file: "crash.log.1", lines: 250, title: "log lần chạy trước" },
];

/// N dòng cuối của text (port của tailLines; Lua giữ tối đa count+1 phần tử khi tách).
pub fn tail_lines_text(data: &str, count: usize) -> String {
    let lines: Vec<&str> = data.split('\n').collect();
    let start = lines.len().saturating_sub(count + 1).min(lines.len());
    // Lua: gmatch "[^\n]*" cho thêm một phần tử rỗng cuối khi text kết thúc bằng \n;
    // hành vi tương đương: giữ count dòng nội dung cuối cùng.
    let kept: Vec<&str> = lines[start..].to_vec();
    let kept: Vec<&str> = kept.into_iter().filter(|l| !l.is_empty() || true).collect();
    let _ = kept;
    let content: Vec<&str> = data.lines().collect();
    let s = content.len().saturating_sub(count);
    content[s..].join("\n")
}

pub fn tail_lines(path: &Path, count: usize) -> Option<String> {
    let data = fs::read(path).ok()?;
    let slice = if data.len() > MAX_READ_BYTES { &data[data.len() - MAX_READ_BYTES..] } else { &data[..] };
    Some(tail_lines_text(&String::from_utf8_lossy(slice), count))
}

pub fn mb(bytes: u64) -> String { format!("{:.1} MB", bytes as f64 / 1024.0 / 1024.0) }

/// Thông tin máy từ /proc/meminfo (port phần RAM của deviceReport).
pub fn parse_meminfo(text: &str) -> Option<(u64, u64)> {
    let get = |key: &str| -> Option<u64> {
        text.lines().find(|l| l.starts_with(key))
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|v| v.parse().ok())
    };
    Some((get("MemTotal:")?, get("MemAvailable:").unwrap_or(0)))
}

#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub version: String, pub koreader_version: String, pub model: String,
    pub screen_w: u32, pub screen_h: u32, pub fb_bpp: u32, pub swap_rb: bool, pub rotation: String,
    pub app_dir: String, pub home_dir: String, pub input_devices: Vec<String>,
    pub free_bytes: Option<u64>, pub mem_total_kb: Option<u64>, pub mem_avail_kb: Option<u64>,
}
pub fn device_report_lines(info: &DeviceInfo, timestamp: &str, uname: &str) -> Vec<String> {
    let mut out = vec![
        format!("Ritder {} (KOReader {})", info.version, info.koreader_version),
        format!("Thời điểm: {timestamp}"),
        format!("Thiết bị: {}", info.model),
        format!("Hệ thống: {uname}"),
        format!("Màn hình: {}x{} @ {} bpp, đổi R/B: {}, xoay: {}",
            info.screen_w, info.screen_h, info.fb_bpp, info.swap_rb, info.rotation),
        format!("Thư mục app: {}", info.app_dir),
        format!("Thư mục sách: {}", info.home_dir),
    ];
    if !info.input_devices.is_empty() {
        let mut names = info.input_devices.clone(); names.sort();
        out.push(format!("Nút bấm: {}", names.join(", ")));
    }
    if let Some(f) = info.free_bytes { out.push(format!("Thẻ nhớ còn trống: {}", mb(f))); }
    if let Some(t) = info.mem_total_kb {
        out.push(format!("RAM: {} MB tổng, {} MB còn trống", t / 1024, info.mem_avail_kb.unwrap_or(0) / 1024));
    }
    out
}

/// Viết ritder-log.txt: khối thiết bị + tail của từng log. Trả (path, size).
pub fn collect(data_dir: &Path, device_block: &[String]) -> std::io::Result<(PathBuf, u64)> {
    let path = data_dir.join(REPORT_NAME);
    let mut text = String::from("===== Ritder =====\n");
    text.push_str(&device_block.join("\n")); text.push('\n');
    for t in TAILS {
        text.push_str(&format!("\n===== {} ({}, {} dòng cuối) =====\n", t.file, t.title, t.lines));
        text.push_str(&tail_lines(&data_dir.join(t.file), t.lines).unwrap_or_else(|| "(không có)".into()));
        text.push('\n');
    }
    fs::write(&path, &text)?;
    Ok((path.clone(), fs::metadata(&path).map(|m| m.len()).unwrap_or(0)))
}

/// Đọc mã crash một lần rồi xóa file (takeCrashCode).
pub fn take_crash_code(data_dir: &Path) -> Option<i64> {
    let p = data_dir.join("crashed");
    let data = fs::read_to_string(&p).ok()?;
    let _ = fs::remove_file(&p);
    let digits: String = data.chars().skip_while(|c| !c.is_ascii_digit()).take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn tail_limit() {
        let data: Vec<String> = (1..=2000).map(|i| format!("dòng {i}")).collect();
        let t = tail_lines_text(&data.join("\n"), 250);
        assert!(t.contains("dòng 2000")); assert!(!t.contains("dòng 100\n"));
    }
}
