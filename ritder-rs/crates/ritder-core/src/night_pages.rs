//! Port của overlay/frontend/ritder/night_pages.lua — "Giữ nguyên màu trang".
use std::collections::BTreeMap;

pub type Settings = BTreeMap<String, i64>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DocKind { Paged, Reflowable, None }

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NightEvent {
    ConfigChange { key: String, value: i64 },       // PDF/CBZ/CBR/DjVu
    ToggleNightmodeImages(bool),                    // EPUB & co
}

/// isKept(): kopt_nightmode_document == 1.
pub fn is_kept(s: &Settings) -> bool { s.get("kopt_nightmode_document").copied() == Some(1) }

/// Quyết định áp dụng cho tài liệu đang mở (bảng quyết định của applyTo).
/// configurable: (có nightmode_document?, có nightmode_images?, giá trị hiện tại)
pub fn plan_apply(keep: bool, kind: DocKind, current: Option<i64>) -> Option<NightEvent> {
    let want: i64 = if keep { 1 } else { 0 };
    match kind {
        DocKind::None => None,
        DocKind::Paged => {
            if current == Some(want) { None }
            else { Some(NightEvent::ConfigChange { key: "nightmode_document".into(), value: want }) }
        }
        DocKind::Reflowable => {
            if current == Some(want) { None }
            else { Some(NightEvent::ToggleNightmodeImages(want == 1)) }
        }
    }
}

/// set(): ghi cả hai khóa mặc định cho sách mở sau này, trả về event cần áp ngay.
pub fn set(s: &mut Settings, keep: bool, kind: DocKind, current: Option<i64>) -> Option<NightEvent> {
    s.insert("kopt_nightmode_document".into(), if keep { 1 } else { 0 });
    s.insert("copt_nightmode_images".into(), if keep { 1 } else { 0 });
    plan_apply(keep, kind, current)
}

/// Mục menu chỉ bật khi đang ở night mode (enabled_func của bản Lua).
pub fn menu_enabled(night_mode: bool) -> bool { night_mode }
pub const MENU_TEXT: &str = "Giữ nguyên màu trang";

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn decision_table() {
        assert_eq!(plan_apply(true, DocKind::Paged, Some(0)), Some(NightEvent::ConfigChange{key:"nightmode_document".into(), value:1}));
        assert_eq!(plan_apply(true, DocKind::Paged, Some(1)), None);
        assert_eq!(plan_apply(false, DocKind::Reflowable, Some(1)), Some(NightEvent::ToggleNightmodeImages(false)));
        assert_eq!(plan_apply(true, DocKind::None, None), None);
    }
}
