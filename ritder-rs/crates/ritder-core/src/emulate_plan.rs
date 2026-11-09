//! Port phần phân tích kịch bản của tools/emulate.py + device/trimui/emulator.lua:
//! đọc tests/screens/*.lua thành danh sách bước có cấu trúc + kế hoạch chạy/chụp.
//! Phần chạy thật trong WSL1 / trên thiết bị là host-dependent (xem MIGRATION.md).
use std::path::Path;

pub const DISTRO: &str = "RitderEmu";
pub const TIMEOUT_S: u64 = 900;
pub const STEP_DELAY: f64 = 0.6;
pub const START_DELAY: f64 = 5.0;

#[derive(Debug, Clone, PartialEq)]
pub enum Step {
    Key(String, Option<f64>),
    Keys(Vec<String>, Option<f64>),
    Wait(f64),
    Shot(String),
    Open(String),
    Lua(String),
    Unknown(String),
}

/// Trích các chuỗi trong dấu ngoặc kép của một dòng bước.
fn quoted(line: &str) -> Vec<String> {
    let mut out = Vec::new(); let mut cur = String::new(); let mut inside = false;
    for c in line.chars() {
        match c { '"' if inside => { out.push(cur.clone()); cur.clear(); inside = false; }
                  '"' => inside = true,
                  _ if inside => cur.push(c), _ => {} }
    }
    out
}
fn delay_of(line: &str) -> Option<f64> {
    // Số thập phân cuối dòng dạng ", 1.5 }" hoặc ", 4 }"
    let t = line.trim_end_matches(['}', ' ', ',']);
    let last = t.rsplit(',').next()?.trim();
    last.parse::<f64>().ok().filter(|v| *v > 0.0 && *v < 100.0)
}

/// Phân tích một file kịch bản .lua (dạng bảng bước của emulator.lua).
pub fn parse_script(text: &str) -> Vec<Step> {
    let mut steps = Vec::new();
    for raw in text.lines() {
        let line = raw.trim();
        if !line.starts_with('{') { continue; }
        let q = quoted(line);
        if q.is_empty() { continue; }
        let delay = delay_of(line);
        match q[0].as_str() {
            "key" if q.len() >= 2 => steps.push(Step::Key(q[1].clone(), delay)),
            "keys" if q.len() >= 2 => steps.push(Step::Keys(q[1].split_whitespace().map(|s| s.to_string()).collect(), delay)),
            "wait" => {
                let secs = line.split(',').nth(1).and_then(|s| s.trim().trim_end_matches(['}', ' ']).parse().ok()).unwrap_or(STEP_DELAY);
                steps.push(Step::Wait(secs));
            }
            "shot" if q.len() >= 2 => steps.push(Step::Shot(q[1].clone())),
            "open" => {
                // Đường dẫn thường nối từ biến books (RITDER_EMU_BOOKS): giữ nguyên biểu thức rút gọn.
                let expr = line.split(',').nth(1).map(|s| s.trim().to_string()).unwrap_or_default();
                steps.push(Step::Open(expr));
            }
            "lua" => steps.push(Step::Lua(line.to_string())),
            other => steps.push(Step::Unknown(other.to_string())),
        }
    }
    steps
}

#[derive(Debug, Clone)]
pub struct RunPlan { pub script: String, pub steps: Vec<Step>, pub shots: Vec<String>, pub out_dir: String }
pub fn plan_for(script_path: &Path, shots_root: &Path) -> std::io::Result<RunPlan> {
    let text = std::fs::read_to_string(script_path)?;
    let steps = parse_script(&text);
    let shots = steps.iter().filter_map(|s| match s { Step::Shot(n) => Some(n.clone()), _ => None }).collect();
    let name = script_path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    Ok(RunPlan { script: name.clone(), steps, shots, out_dir: shots_root.join(&name).to_string_lossy().into_owned() })
}

/// Biến môi trường mà emulate.py đặt cho tiến trình giả lập (dạng dữ liệu).
pub fn emu_env(app: &str, script: &str, out: &str, books: &str, package: &str) -> Vec<(String, String)> {
    vec![
        ("RITDER_DIR".into(), app.into()), ("RITDER_DEVICE".into(), "trimui-brick-pro".into()),
        ("RITDER_EMULATOR".into(), "1".into()), ("RITDER_EMU_SCRIPT".into(), script.into()),
        ("RITDER_EMU_OUT".into(), out.into()), ("RITDER_EMU_BOOKS".into(), books.into()),
        ("RITDER_HOME_DIR".into(), books.into()), ("KO_HOME".into(), "/tmp/ritder-emu-userdata".into()),
        ("RITDER_EMU_PACKAGE".into(), package.into()), ("LC_ALL".into(), "C.UTF-8".into()),
    ]
}
/// Windows path -> WSL path (port của wsl_path()).
pub fn wsl_path(path: &str) -> String {
    let p = path.replace('\\', "/");
    if p.len() >= 3 && p.as_bytes()[1] == b':' {
        format!("/mnt/{}{}", p[0..1].to_lowercase(), &p[2..])
    } else { p }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn parse_basic() {
        let s = parse_script("return {\n { \"shot\", \"01_start\" },\n { \"keys\", \"DOWN A\" },\n { \"wait\", 2 },\n}\n");
        assert_eq!(s.len(), 3);
        assert!(matches!(&s[1], Step::Keys(v, _) if v.len() == 2));
    }
}
