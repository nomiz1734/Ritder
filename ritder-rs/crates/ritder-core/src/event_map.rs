//! Port của device/trimui/event_map.lua (bảng mặc định) + bảng phím của emulator.lua.
use crate::input_evdev::*;
use std::collections::HashMap;

pub fn default_event_map() -> HashMap<u16, String> {
    let pairs: [(u16, &str); 13] = [
        (103, "Up"), (108, "Down"), (105, "Left"), (106, "Right"),
        (305, "Press"), (304, "Back"), (308, "ContextMenu"), (307, "Home"),
        (310, "LPgBack"), (311, "RPgFwd"), (312, "LPgBack"), (313, "RPgFwd"),
        (315, "Menu"),
    ];
    let mut m: HashMap<u16, String> = pairs.iter().map(|(c, n)| (*c, n.to_string())).collect();
    m.insert(314, "Menu".into()); // SELECT
    // 316 (MENU) và phím âm lượng/nguồn cố ý không map: để Stock OS xử lý.
    m
}

/// Gộp bản đồ người dùng (userdata/settings/event_map) đè lên mặc định.
pub fn merged(user: &HashMap<u16, String>) -> HashMap<u16, String> {
    let mut m = default_event_map();
    for (k, v) in user { m.insert(*k, v.clone()); }
    m
}

/// Bảng phím giả lập (emulator.lua KEYS/HATS/TRIGGERS).
pub fn emulator_key_code(name: &str) -> Option<u16> {
    match name.to_ascii_uppercase().as_str() {
        "A" => Some(305), "B" => Some(304), "X" => Some(308), "Y" => Some(307),
        "L1" => Some(310), "R1" => Some(311), "SELECT" => Some(314), "START" => Some(315), "MENU" => Some(316),
        _ => None,
    }
}
/// Raw evdev events cho một lần nhấn+nhả (Emulator.eventsFor).
pub fn events_for(name: &str) -> Result<Vec<RawEvent>, String> {
    let up = name.to_ascii_uppercase();
    if let Some(code) = emulator_key_code(&up) {
        return Ok(vec![
            RawEvent { ev_type: EV_KEY, code, value: 1 },
            RawEvent { ev_type: EV_KEY, code, value: 0 },
        ]);
    }
    let hat = match up.as_str() {
        "UP" => Some((ABS_HAT0Y, -1)), "DOWN" => Some((ABS_HAT0Y, 1)),
        "LEFT" => Some((ABS_HAT0X, -1)), "RIGHT" => Some((ABS_HAT0X, 1)),
        _ => None,
    };
    if let Some((axis, value)) = hat {
        return Ok(vec![
            RawEvent { ev_type: EV_ABS, code: axis, value },
            RawEvent { ev_type: EV_ABS, code: axis, value: 0 },
        ]);
    }
    let trig = match up.as_str() { "L2" => Some(ABS_Z), "R2" => Some(ABS_RZ), _ => None };
    if let Some(axis) = trig {
        return Ok(vec![
            RawEvent { ev_type: EV_ABS, code: axis, value: 255 },
            RawEvent { ev_type: EV_ABS, code: axis, value: 0 },
        ]);
    }
    Err(format!("unknown button {name}"))
}
