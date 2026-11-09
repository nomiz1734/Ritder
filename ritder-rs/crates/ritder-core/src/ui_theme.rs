//! Port logic thuần của frontend/ritder/ui_theme.lua (397 dòng):
//! màu focus, tint trong night mode, chuyển tab trái/phải, repaint từng phần,
//! focus nút xác nhận trong ConfirmBox. Phần monkey-patch widget của KOReader
//! là điểm móc LuaJIT — ngoài runtime Rust; logic quyết định nằm ở đây.

pub const FOCUS_BACKGROUND: (u8, u8, u8, u8) = (0xD8, 0xE6, 0xFA, 0xFF);
pub const FOCUS_ACCENT: (u8, u8, u8, u8) = (0x2B, 0x5C, 0xB8, 0xFF);
pub const CURSOR_BOX: (u8, u8, u8, u8) = (0xFF, 0xEE, 0x8C, 0xFF);
pub const CURSOR_LINE: (u8, u8, u8, u8) = (0xE0, 0x46, 0x2C, 0xFF);

/// tint(): trong night mode (buffer đã đảo, inverse==1) không tint — chỉ vẽ khung.
pub fn should_tint(inverse: i32) -> bool { inverse != 1 }

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RowStyle { Row, Tile, TopMenu, Button }

/// Style "row" luôn có accent bar bên trái; khung được vẽ khi không tint được hoặc không phải row.
pub fn draws_frame(style: RowStyle, tinted: bool) -> bool {
    style != RowStyle::Row || !tinted
}
pub fn draws_accent_bar(style: RowStyle) -> bool { style == RowStyle::Row }

/// Điều hướng tab bằng LEFT/RIGHT ở tầng trên cùng (patchTouchMenuKeys):
/// dx = -1/+1, bỏ qua tab có remember == false (tab "+" là hành động).
/// cur_tab dùng chỉ số 1-based như Lua. Trả tab mới (1-based) hoặc None nếu không đổi.
pub fn next_tab(cur_tab: usize, count: usize, dx: i64, remember: &[bool]) -> Option<usize> {
    if count == 0 { return None; }
    let mut tab = cur_tab;
    for _ in 0..count {
        tab = ((tab as i64 - 1 + dx).rem_euclid(count as i64) + 1) as usize;
        if remember.get(tab - 1).copied().unwrap_or(true) { break; }
    }
    if tab != cur_tab { Some(tab) } else { None }
}

/// Khi mở trang/tab/submenu: đáp xuống mục đầu tiên (hàng 2 trong layout của TouchMenu),
/// trừ khi đang rebuild tại chỗ (stay = hàng đang chọn cũ).
pub fn focus_row_after_update(stay: Option<usize>, has_layout_row2: bool) -> Option<usize> {
    if !has_layout_row2 { return None; }
    match stay { Some(y) if y > 1 => Some(y), _ => Some(2) }
}

/// repaintFocusChange có an toàn không: host phải ở trên cùng, mọi item thuộc
/// partial_classes, có dimen hợp lệ, không nằm trong cropping widget cuộn.
#[derive(Debug, Clone, Copy)]
pub struct ItemInfo { pub is_partial_class: bool, pub has_valid_dimen: bool, pub in_cropping: bool }
pub fn can_repaint_focus(host_on_top: bool, items: &[ItemInfo]) -> bool {
    if !host_on_top || items.is_empty() { return false; }
    items.iter().all(|i| i.is_partial_class && i.has_valid_dimen && !i.in_cropping)
}

/// ConfirmBox: tìm nút có text == ok_text để focus trước (A = đồng ý, B = hủy).
pub fn confirm_focus(layout: &[Vec<String>], ok_text: &str) -> Option<(usize, usize)> {
    for (y, row) in layout.iter().enumerate() {
        for (x, text) in row.iter().enumerate() {
            if text == ok_text { return Some((x + 1, y + 1)); } // 1-based như Lua
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn tab_skips_action_tabs() {
        assert_eq!(next_tab(1, 3, 1, &[true, false, true]), Some(3));
        assert_eq!(next_tab(1, 1, 1, &[true]), None);
    }
    #[test] fn night_skips_tint() { assert!(!should_tint(1)); assert!(should_tint(0)); }
}
