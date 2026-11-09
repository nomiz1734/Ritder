//! Port logic thuần của overlay/plugins/ritderupdate.koplugin/
//! (_meta.lua, main.lua, progressdialog.lua, ritderinfo.lua).
//! Phần widget/giao diện là điểm móc LuaJIT của KOReader; tại đây giữ:
//! hằng số vòng đời OTA, format tiến trình, cắt ghi chú, nội dung guide/about.

pub const PLUGIN_NAME: &str = "ritderupdate";
pub const PLUGIN_FULLNAME: &str = "Ritder updates";
pub const PLUGIN_DESCRIPTION: &str = "Checks GitHub Releases for a newer Ritder and installs it over the air.";
pub const AUTO_CHECK_DELAY_S: u64 = 8;
pub const CONFIRM_AFTER_S: u64 = 10;
pub const POLL_S: f64 = 0.5;
pub const STALLED_S: u64 = 180;
pub const RESTART_EXIT_CODE: i32 = 42;
pub const MAX_NOTES_LINES: usize = 6;
pub const REPO: &str = "https://github.com/nomiz1734/Ritder";

pub fn format_mb(bytes: u64) -> String { format!("{:.1}", bytes as f64 / 1024.0 / 1024.0) }

/// Cắt release notes còn tối đa 6 dòng + "…" (trimNotes của main.lua).
pub fn trim_notes(notes: &str) -> String {
    let mut lines: Vec<&str> = Vec::new();
    for line in notes.lines().filter(|l| !l.is_empty()) {
        if lines.len() == MAX_NOTES_LINES { lines.push("…"); break; }
        lines.push(line);
    }
    lines.join("\n")
}

/// Tiến trình tải: (phần trăm 0.0..=1.0, dòng "x / y MB") cho ProgressDialog.
pub fn progress_state(downloaded: u64, total: Option<u64>) -> (f64, String) {
    match total {
        Some(t) if t > 0 => ((downloaded as f64 / t as f64).clamp(0.0, 1.0),
                             format!("{} / {} MB", format_mb(downloaded), format_mb(t))),
        _ => (0.0, format!("{} MB", format_mb(downloaded))),
    }
}
/// Chiều rộng hộp thoại tiến trình = 70% bề ngang màn hình (progressdialog.lua).
pub fn dialog_width(screen_w: u32) -> u32 { (screen_w as f64 * 0.7) as u32 }

pub fn version_text(version: &str) -> String { format!("Ritder {version}") }

/// Nội dung Hướng dẫn nhanh (GUIDE của ritderinfo.lua, rút gọn hằng số dữ liệu).
pub const GUIDE_SECTIONS: [&str; 6] = [
    "SÁCH: chép sách vào thư mục Books ở gốc thẻ nhớ. Đọc được PDF, CBZ, CBR, EPUB, MOBI, FB2, DjVu, TXT, HTML.",
    "NÚT BẤM: D-pad di chuyển; A mở/chọn; B quay lại; START/SELECT menu chính; X menu thao tác; Y về thư mục sách.",
    "KHI ĐỌC: ← → hoặc L1/R1, L2/R2 lật trang; ↑ ↓ hiện con trỏ chọn chữ; START menu đọc.",
    "BAN ĐÊM: START → Cài đặt → Chế độ ban đêm; mục 'Giữ nguyên màu trang' ngay bên dưới.",
    "CẬP NHẬT: START → Kiểm tra cập nhật; cần Wi-Fi và đồng hồ đúng giờ; dữ liệu trong userdata được giữ nguyên.",
    "KHI CÓ LỖI: START → Giúp đỡ → Gom log để gửi; file Apps/Ritder/userdata/ritder-log.txt.",
];

/// Job nền bị coi là treo khi không có tiến triển quá STALLED_S giây.
pub fn is_stalled(seconds_since_progress: u64) -> bool { seconds_since_progress >= STALLED_S }
