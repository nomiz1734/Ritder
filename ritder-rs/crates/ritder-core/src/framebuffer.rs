//! Port của device/trimui/framebuffer.lua + emu_framebuffer.lua:
//! double buffering, chép vùng (region copy), đổi RGB->BGR khi panel là BGR.

/// Công thức Lua: bor(band(v,0xFF00FF00), band(rshift(v,16),0xFF), lshift(band(v,0xFF),16))
/// trên word little-endian RGBA (0xAABBGGRR) -> BGRA (0xAARRGGBB).
pub fn swap_rb_word(v: u32) -> u32 {
    (v & 0xFF00_FF00) | ((v >> 16) & 0xFF) | ((v & 0xFF) << 16)
}

/// Cần swap khi bpp==32 và red.offset != 0 (điều kiện trong framebuffer:init).
pub fn needs_swap(fb_bpp: u32, red_offset: u32) -> bool { fb_bpp == 32 && red_offset != 0 }

#[derive(Debug, Clone)]
pub struct Buffer {
    pub w: usize, pub h: usize, pub stride: usize, // stride tính bằng byte
    pub data: Vec<u8>,
}
impl Buffer {
    pub fn new(w: usize, h: usize, stride: usize) -> Self {
        Self { w, h, stride, data: vec![0; stride * h] }
    }
    pub fn tight(w: usize, h: usize) -> Self { Self::new(w, h, w * 4) }
    pub fn fill_white(&mut self) { for b in self.data.iter_mut() { *b = 0xFF; } }
    pub fn set_px(&mut self, x: usize, y: usize, px: [u8; 4]) {
        let o = y * self.stride + x * 4;
        self.data[o..o + 4].copy_from_slice(&px);
    }
    pub fn px(&self, x: usize, y: usize) -> [u8; 4] {
        let o = y * self.stride + x * 4;
        [self.data[o], self.data[o + 1], self.data[o + 2], self.data[o + 3]]
    }
}

/// getBoundedRect: kẹp rect vào trong buffer; rect rỗng trả None.
pub fn bounded_rect(w: usize, h: usize, x: i64, y: i64, rw: i64, rh: i64) -> Option<(usize, usize, usize, usize)> {
    let x0 = x.max(0); let y0 = y.max(0);
    let x1 = (x + rw).min(w as i64); let y1 = (y + rh).min(h as i64);
    if x1 <= x0 || y1 <= y0 { return None; }
    Some((x0 as usize, y0 as usize, (x1 - x0) as usize, (y1 - y0) as usize))
}

/// Port của copyToScreen: chép rect từ shadow (bb) sang panel (fb_bb).
pub fn copy_to_screen(src: &Buffer, dst: &mut Buffer, x: usize, y: usize, w: usize, h: usize, swap_rb: bool) {
    let bpp = 4usize;
    for row in 0..h {
        let so = (y + row) * src.stride + x * bpp;
        let dof = (y + row) * dst.stride + x * bpp;
        if swap_rb {
            for i in 0..w {
                let s = so + i * 4; let d = dof + i * 4;
                let v = u32::from_le_bytes([src.data[s], src.data[s + 1], src.data[s + 2], src.data[s + 3]]);
                dst.data[d..d + 4].copy_from_slice(&swap_rb_word(v).to_le_bytes());
            }
        } else {
            dst.data[dof..dof + w * bpp].copy_from_slice(&src.data[so..so + w * bpp]);
        }
    }
}

/// Mô hình double-buffer: shadow bb + panel fb_bb.
pub struct Framebuffer {
    pub bb: Buffer, pub fb_bb: Buffer, pub fb_bpp: u32, pub swap_rb: bool,
}
impl Framebuffer {
    pub fn new(w: usize, h: usize, swap_rb: bool) -> Self {
        let mut bb = Buffer::tight(w, h); bb.fill_white();
        Self { bb, fb_bb: Buffer::tight(w, h), fb_bpp: 32, swap_rb }
    }
    /// refreshFullImp: bounded -> physical (không xoay trong model này) -> copy.
    pub fn refresh(&mut self, x: i64, y: i64, w: i64, h: i64) {
        if let Some((bx, by, bw, bh)) = bounded_rect(self.bb.w, self.bb.h, x, y, w, h) {
            // Tránh vay mượn kép: clone hàng cần thiết qua hàm tự do với tách trường.
            let (bb, fb) = (&self.bb, &mut self.fb_bb);
            copy_to_screen(bb, fb, bx, by, bw, bh, self.swap_rb);
        }
    }
}

/// Emu framebuffer: panel trong RAM + đếm refreshed_pixels (emu_framebuffer.lua).
pub struct EmuFramebuffer { pub bb: Buffer, pub panel: Buffer, pub refreshed_pixels: usize }
impl EmuFramebuffer {
    pub fn new(w: usize, h: usize) -> Self {
        let mut bb = Buffer::tight(w, h); bb.fill_white();
        let mut panel = Buffer::tight(w, h); panel.fill_white();
        Self { bb, panel, refreshed_pixels: 0 }
    }
    pub fn refresh(&mut self, x: i64, y: i64, w: i64, h: i64) {
        if let Some((bx, by, bw, bh)) = bounded_rect(self.bb.w, self.bb.h, x, y, w, h) {
            copy_to_screen(&self.bb.clone(), &mut self.panel, bx, by, bw, bh, false);
            self.refreshed_pixels += bw * bh;
        }
    }
    pub fn env_size(get: impl Fn(&str) -> Option<String>) -> (usize, usize) {
        (get("RITDER_EMU_W").and_then(|v| v.parse().ok()).unwrap_or(1024),
         get("RITDER_EMU_H").and_then(|v| v.parse().ok()).unwrap_or(768))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn bgr_swap() {
        let mut src = Buffer::tight(2, 1); src.set_px(0, 0, [0xD8, 0xE6, 0xFA, 0xFF]);
        let mut dst = Buffer::tight(2, 1);
        copy_to_screen(&src, &mut dst, 0, 0, 2, 1, true);
        assert_eq!(dst.px(0, 0), [0xFA, 0xE6, 0xD8, 0xFF]);
    }
    #[test] fn verbatim() {
        let mut src = Buffer::tight(1, 1); src.set_px(0, 0, [1, 2, 3, 4]);
        let mut dst = Buffer::tight(1, 1);
        copy_to_screen(&src, &mut dst, 0, 0, 1, 1, false);
        assert_eq!(dst.px(0, 0), [1, 2, 3, 4]);
    }
}
