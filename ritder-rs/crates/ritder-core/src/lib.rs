//! ritder-core: toàn bộ logic thuần port từ code Lua/Python/Shell của Ritder.
//! KOReader upstream không nằm trong repo Ritder nên ngoài phạm vi (xem MIGRATION.md).
pub mod brand;
pub mod buildtools;
pub mod device;
pub mod diagnostics;
pub mod emulate_plan;
pub mod event_map;
pub mod framebuffer;
pub mod icon;
pub mod input_evdev;
pub mod install;
pub mod logging;
pub mod night_pages;
pub mod plugin;
pub mod powerd;
pub mod ui_theme;
pub mod update;

use sha2::{Digest, Sha256};
use std::io::Read;
use std::path::Path;

/// SHA-256 hex chữ thường của dữ liệu (port của hashlib / Update.sha256File).
pub fn sha256_hex(data: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(data);
    hex(&h.finalize())
}
pub fn sha256_file(path: &Path) -> Option<String> {
    let mut f = std::fs::File::open(path).ok()?;
    let mut h = Sha256::new();
    let mut buf = [0u8; 65536];
    loop {
        let n = f.read(&mut buf).ok()?;
        if n == 0 { break; }
        h.update(&buf[..n]);
    }
    Some(hex(&h.finalize()))
}
pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
