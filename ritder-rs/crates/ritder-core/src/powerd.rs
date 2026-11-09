//! Port của device/trimui/powerd.lua: tìm pin trong /sys/class/power_supply.
use std::fs;
use std::path::{Path, PathBuf};

pub const SUPPLY_DIR: &str = "/sys/class/power_supply";

fn read_line(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.lines().next().unwrap_or("").to_string())
}

/// Chọn supply đầu tiên có type == "Battery" và có file capacity.
pub fn find_battery_in(dir: &Path) -> Option<PathBuf> {
    let mut names: Vec<PathBuf> = fs::read_dir(dir).ok()?.flatten().map(|e| e.path()).collect();
    names.sort();
    for p in names {
        if read_line(&p.join("type")).as_deref() == Some("Battery") && p.join("capacity").exists() {
            return Some(p);
        }
    }
    None
}

pub struct PowerD { pub battery_dir: Option<PathBuf> }
impl PowerD {
    pub fn new() -> Self { Self { battery_dir: find_battery_in(Path::new(SUPPLY_DIR)) } }
    pub fn with_dir(d: Option<PathBuf>) -> Self { Self { battery_dir: d } }
    pub fn capacity(&self) -> i64 {
        match &self.battery_dir {
            Some(d) => read_line(&d.join("capacity")).and_then(|v| v.trim().parse().ok()).unwrap_or(0),
            None => 0,
        }
    }
    pub fn is_charging(&self) -> bool {
        self.battery_dir.as_ref().and_then(|d| read_line(&d.join("status"))).as_deref() == Some("Charging")
    }
    pub fn is_charged(&self) -> bool {
        self.battery_dir.as_ref().and_then(|d| read_line(&d.join("status"))).as_deref() == Some("Full")
    }
}
impl Default for PowerD { fn default() -> Self { Self::new() } }
