//! Port của device/trimui/input_evdev.lua (344 dòng):
//! HAT -> phím mũi tên, trigger analog -> nút, software repeat, bỏ sự kiện khác.
use std::collections::BTreeMap;

pub const EV_SYN: u16 = 0; pub const EV_KEY: u16 = 1; pub const EV_ABS: u16 = 3;
pub const ABS_Z: u16 = 0x02; pub const ABS_RZ: u16 = 0x05; pub const ABS_GAS: u16 = 0x09; pub const ABS_BRAKE: u16 = 0x0a;
pub const ABS_HAT0X: u16 = 0x10; pub const ABS_HAT0Y: u16 = 0x11;
pub const KEY_UP: u16 = 103; pub const KEY_LEFT: u16 = 105; pub const KEY_RIGHT: u16 = 106; pub const KEY_DOWN: u16 = 108;
pub const BTN_TL: u16 = 310; pub const BTN_TR: u16 = 311; pub const BTN_TL2: u16 = 312; pub const BTN_TR2: u16 = 313;
pub const KEY_RELEASE: i32 = 0; pub const KEY_PRESS: i32 = 1; pub const KEY_REPEAT: i32 = 2;
pub const REPEAT_DELAY: f64 = 0.40; pub const REPEAT_PERIOD: f64 = 0.10;

pub fn is_repeatable(code: u16) -> bool {
    matches!(code, KEY_UP | KEY_DOWN | KEY_LEFT | KEY_RIGHT | BTN_TL | BTN_TR | BTN_TL2 | BTN_TR2)
}
pub fn trigger_key(abs: u16) -> Option<u16> {
    match abs { ABS_Z | ABS_BRAKE => Some(BTN_TL2), ABS_RZ | ABS_GAS => Some(BTN_TR2), _ => None }
}
/// Ngưỡng trigger: giữa khoảng [min,max], mặc định 0.5 khi không đọc được absinfo.
pub fn trigger_threshold(min: i32, max: i32) -> f64 {
    if max > min { min as f64 + (max - min) as f64 / 2.0 } else { 0.5 }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RawEvent { pub ev_type: u16, pub code: u16, pub value: i32 }
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct KeyEvent { pub code: u16, pub value: i32, pub t: f64 }

#[derive(Debug, Clone)]
pub struct DeviceState {
    pub thresholds: BTreeMap<u16, f64>,
    pub triggers: BTreeMap<u16, bool>,
}
impl Default for DeviceState {
    fn default() -> Self {
        let mut thresholds = BTreeMap::new();
        for a in [ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE] { thresholds.insert(a, 127.5); }
        Self { thresholds, triggers: BTreeMap::new() }
    }
}

#[derive(Debug, Default)]
pub struct Translator {
    pub held: BTreeMap<u16, f64>, // code -> thời điểm repeat tiếp theo
    pub hat: BTreeMap<u16, i32>,
    pub unmapped_log: Vec<u16>,
}
impl Translator {
    pub fn new() -> Self {
        let mut hat = BTreeMap::new(); hat.insert(ABS_HAT0X, 0); hat.insert(ABS_HAT0Y, 0);
        Self { held: BTreeMap::new(), hat, unmapped_log: Vec::new() }
    }
    fn press(&mut self, out: &mut Vec<KeyEvent>, code: u16, value: i32, t: f64) {
        out.push(KeyEvent { code, value, t });
        if is_repeatable(code) {
            if value == KEY_PRESS { self.held.insert(code, t + REPEAT_DELAY); }
            else if value == KEY_RELEASE { self.held.remove(&code); }
        }
    }
    fn translate_hat(&mut self, out: &mut Vec<KeyEvent>, code: u16, value: i32, t: f64) {
        let old = self.hat.get(&code).copied().unwrap_or(0);
        if value == old { return; }
        self.hat.insert(code, value);
        let (neg, pos) = if code == ABS_HAT0X { (KEY_LEFT, KEY_RIGHT) } else { (KEY_UP, KEY_DOWN) };
        if old < 0 { self.press(out, neg, KEY_RELEASE, t); }
        if old > 0 { self.press(out, pos, KEY_RELEASE, t); }
        if value < 0 { self.press(out, neg, KEY_PRESS, t); }
        if value > 0 { self.press(out, pos, KEY_PRESS, t); }
    }
    /// Port của translate(): chỉ EV_KEY lọt qua; EV_SYN/MSC/ABS khác bị bỏ.
    pub fn translate(&mut self, dev: &mut DeviceState, ev: RawEvent, t: f64, event_map: Option<&std::collections::HashMap<u16, String>>, out: &mut Vec<KeyEvent>) {
        match ev.ev_type {
            EV_KEY => {
                if ev.value == KEY_REPEAT && is_repeatable(ev.code) { return; } // tự sinh repeat đều
                if ev.value == KEY_PRESS {
                    if let Some(m) = event_map { if !m.contains_key(&ev.code) { self.unmapped_log.push(ev.code); } }
                }
                self.press(out, ev.code, ev.value, t);
            }
            EV_ABS => {
                if ev.code == ABS_HAT0X || ev.code == ABS_HAT0Y {
                    let v = if ev.value < 0 { -1 } else if ev.value > 0 { 1 } else { 0 };
                    self.translate_hat(out, ev.code, v, t);
                } else if let Some(key) = trigger_key(ev.code) {
                    let thr = dev.thresholds.get(&ev.code).copied().unwrap_or(0.5);
                    let pressed = (ev.value as f64) > thr;
                    if pressed != dev.triggers.get(&ev.code).copied().unwrap_or(false) {
                        dev.triggers.insert(ev.code, pressed);
                        self.press(out, key, if pressed { KEY_PRESS } else { KEY_RELEASE }, t);
                    }
                }
            }
            _ => {} // bỏ EV_SYN, EV_MSC...
        }
    }
    /// Port của dueRepeats.
    pub fn due_repeats(&mut self, t: f64, out: &mut Vec<KeyEvent>) {
        let codes: Vec<u16> = self.held.keys().copied().collect();
        for code in codes {
            if let Some(&due) = self.held.get(&code) {
                if t >= due {
                    out.push(KeyEvent { code, value: KEY_REPEAT, t });
                    self.held.insert(code, t + REPEAT_PERIOD);
                }
            }
        }
    }
    pub fn next_repeat(&self) -> Option<f64> { self.held.values().copied().reduce(f64::min) }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn run(tr: &mut Translator, evs: &[(u16, u16, i32)]) -> Vec<KeyEvent> {
        let mut dev = DeviceState::default(); let mut out = Vec::new();
        for &(ty, c, v) in evs { tr.translate(&mut dev, RawEvent{ev_type:ty, code:c, value:v}, 100.0, None, &mut out); }
        out
    }
    #[test] fn hat_arrows() {
        let mut tr = Translator::new();
        let out = run(&mut tr, &[(EV_ABS, ABS_HAT0Y, -1), (EV_SYN, 0, 0), (EV_ABS, ABS_HAT0Y, 0)]);
        assert_eq!(out.iter().map(|e| (e.code, e.value)).collect::<Vec<_>>(), vec![(103, 1), (103, 0)]);
    }
}
