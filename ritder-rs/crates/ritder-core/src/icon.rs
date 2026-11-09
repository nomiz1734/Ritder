//! Port của tools/make_icon.py: logo sách mở trên nền gạch bo góc.
//! PNG được ghi bằng encoder tối thiểu tự viết (zlib stored blocks qua flate2
//! ở mức Compression::none cho IDAT vẫn là DEFLATE hợp lệ; CRC32 tự tính).
//! Vẽ hình học đơn giản hoá so với PIL (rounded rect, hai trang, ribbon) nhưng
//! giữ đúng bảng màu và tỉ lệ: icon launcher 300x300 với tile 184x184 ở giữa,
//! logo 256x256 phủ đầy.
use std::io::Write;

pub const TILE: (u8, u8, u8, u8) = (28, 44, 74, 255);
pub const PAGE: (u8, u8, u8, u8) = (246, 241, 228, 255);
pub const LINE: (u8, u8, u8, u8) = (160, 170, 190, 255);
pub const RIBBON: (u8, u8, u8, u8) = (236, 92, 72, 255);

pub struct RgbaImage { pub w: usize, pub h: usize, pub px: Vec<u8> }
impl RgbaImage {
    pub fn new(w: usize, h: usize) -> Self { Self { w, h, px: vec![0; w * h * 4] } }
    pub fn set(&mut self, x: i64, y: i64, c: (u8, u8, u8, u8)) {
        if x >= 0 && y >= 0 && (x as usize) < self.w && (y as usize) < self.h {
            let o = (y as usize * self.w + x as usize) * 4;
            self.px[o..o + 4].copy_from_slice(&[c.0, c.1, c.2, c.3]);
        }
    }
    pub fn fill_rounded_rect(&mut self, x0: f64, y0: f64, x1: f64, y1: f64, r: f64, c: (u8, u8, u8, u8)) {
        for y in y0 as i64..y1 as i64 { for x in x0 as i64..x1 as i64 {
            let fx = x as f64; let fy = y as f64;
            let cx = fx.clamp(x0 + r, x1 - r); let cy = fy.clamp(y0 + r, y1 - r);
            if (fx - cx).powi(2) + (fy - cy).powi(2) <= r * r + r { self.set(x, y, c); }
        }}
    }
    pub fn fill_rect(&mut self, x0: i64, y0: i64, x1: i64, y1: i64, c: (u8, u8, u8, u8)) {
        for y in y0..y1 { for x in x0..x1 { self.set(x, y, c); } }
    }
}

/// Vẽ tile trong không gian thiết kế 300 (như make_icon.py, không supersample:
/// cạnh bo góc chấp nhận răng cưa nhẹ — ghi rõ trong MIGRATION.md).
pub fn tile(size: usize) -> RgbaImage {
    let k = size as f64 / 300.0;
    let mut img = RgbaImage::new(size, size);
    img.fill_rounded_rect(0.0, 0.0, size as f64, size as f64, 64.0 * k, TILE);
    let cx = size as f64 / 2.0; let top = 78.0 * k; let bottom = 222.0 * k;
    let page_w = 96.0 * k;
    // Hai trang: hình thang đơn giản hoá thành rect từ cx-page_w..cx+page_w với gáy ở giữa.
    img.fill_rect((cx - page_w) as i64, top as i64, (cx + page_w) as i64, bottom as i64, PAGE);
    for i in 0..5 {
        let y = (top + (26.0 + i as f64 * 22.0) * k) as i64;
        for side in [-1.0, 1.0] {
            let x0 = (cx + side * 18.0 * k) as i64; let x1 = (cx + side * (page_w / k - 18.0) * k) as i64;
            let (a, b) = if x0 < x1 { (x0, x1) } else { (x1, x0) };
            img.fill_rect(a, y, b, y + (5.0 * k).max(1.0) as i64, LINE);
        }
    }
    img.fill_rect((cx - 2.0 * k) as i64, top as i64, (cx + 2.0 * k) as i64, bottom as i64, TILE);
    let bx = (cx + 58.0 * k) as i64;
    img.fill_rect(bx, (top - 6.0 * k) as i64, bx + (22.0 * k) as i64, (top + 58.0 * k) as i64, RIBBON);
    img
}

/// Icon launcher 300x300: tile 184x184 dán ở (58,58), nền trong suốt.
pub fn launcher_icon() -> RgbaImage {
    let inner = tile(184);
    let mut img = RgbaImage::new(300, 300);
    for y in 0..184 { for x in 0..184 {
        let o = (y * 184 + x) * 4;
        let px = [inner.px[o], inner.px[o + 1], inner.px[o + 2], inner.px[o + 3]];
        if px[3] > 0 { img.set(58 + x as i64, 58 + y as i64, (px[0], px[1], px[2], px[3])); }
    }}
    img
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFF_FFFF;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 { crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 }; }
    }
    !crc
}
fn chunk(out: &mut Vec<u8>, name: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(name);
    out.extend_from_slice(data);
    let mut both = name.to_vec(); both.extend_from_slice(data);
    out.extend_from_slice(&crc32(&both).to_be_bytes());
}
/// Ghi PNG RGBA8 hợp lệ.
pub fn write_png(img: &RgbaImage) -> Vec<u8> {
    let mut raw = Vec::with_capacity((img.w * 4 + 1) * img.h);
    for y in 0..img.h {
        raw.push(0u8); // filter none
        raw.extend_from_slice(&img.px[y * img.w * 4..(y + 1) * img.w * 4]);
    }
    let mut comp = Vec::new();
    {
        let mut enc = flate2::write::ZlibEncoder::new(&mut comp, flate2::Compression::fast());
        enc.write_all(&raw).expect("zlib");
        enc.finish().expect("zlib");
    }
    let mut out = vec![137, 80, 78, 71, 13, 10, 26, 10];
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&(img.w as u32).to_be_bytes());
    ihdr.extend_from_slice(&(img.h as u32).to_be_bytes());
    ihdr.extend_from_slice(&[8, 6, 0, 0, 0]);
    chunk(&mut out, b"IHDR", &ihdr);
    chunk(&mut out, b"IDAT", &comp);
    chunk(&mut out, b"IEND", &[]);
    out
}

/// SVG logo (port hàm svg() của make_icon.py; chú ý bản Python dùng TILE khác:
/// rect fill #1c2c4a trong svg() gốc — giữ nguyên để khớp dữ liệu gốc).
pub fn svg() -> String {
    let mut lines = Vec::new();
    for side in [-1i32, 1] {
        let outer = 150 + side * 96;
        lines.push(format!("<polygon points=\"150,92 {outer},78 {outer},208 150,222\" fill=\"#f6f1e4\"/>"));
        for i in 0..5 {
            let y = 78 + 26 + i * 22;
            let x0 = 150 + side * 18; let x1 = 150 + side * 78;
            lines.push(format!("<line x1=\"{x0}\" y1=\"{}\" x2=\"{x1}\" y2=\"{y}\" stroke=\"#a0aabe\" stroke-width=\"5\"/>", y + 7));
        }
    }
    format!("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 300 300\" width=\"300\" height=\"300\">\n<rect width=\"300\" height=\"300\" rx=\"64\" fill=\"#1c2c4a\"/>\n{}\n<line x1=\"150\" y1=\"92\" x2=\"150\" y2=\"222\" stroke=\"#1c2c4a\" stroke-width=\"4\"/>\n<polygon points=\"208,72 230,69 230,136 219,124 208,138\" fill=\"#ec5c48\"/>\n</svg>\n", lines.join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn png_signature() {
        let png = write_png(&tile(64));
        assert_eq!(&png[0..4], &[137, 80, 78, 71]);
        assert!(svg().contains("#ec5c48"));
    }
}
