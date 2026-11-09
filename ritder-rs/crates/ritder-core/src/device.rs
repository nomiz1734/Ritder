//! Port của device/trimui/device.lua: capabilities của TrimUI Brick Pro.
pub const MUPDF_STORE_MB: usize = 32;
pub const MODEL: &str = "TrimUI Brick Pro";
pub const DISPLAY_DPI: u32 = 324;
pub const SCREEN_W: u32 = 1024;
pub const SCREEN_H: u32 = 768;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Capabilities {
    pub is_touch_device: bool, pub has_keys: bool, pub has_dpad: bool,
    pub use_dpad_as_action_keys: bool, pub has_few_keys: bool, pub has_keyboard: bool,
    pub has_eink_screen: bool, pub has_color_screen: bool, pub can_hw_dither: bool,
    pub can_hw_invert: bool, pub needs_screen_refresh_after_resume: bool,
    pub has_frontlight: bool, pub has_wifi_toggle: bool, pub has_seamless_wifi_toggle: bool,
    pub has_ota_updates: bool, // OTA của KOReader tắt; Ritder dùng OTA riêng
    pub can_restart: bool, pub can_suspend: bool, pub can_standby: bool,
    pub can_reboot: bool, pub can_power_off: bool, pub supports_screensaver: bool,
}
pub const BRICK_PRO: Capabilities = Capabilities {
    is_touch_device: false, has_keys: true, has_dpad: true,
    use_dpad_as_action_keys: true, has_few_keys: false, has_keyboard: false,
    has_eink_screen: false, has_color_screen: true, can_hw_dither: false,
    can_hw_invert: false, needs_screen_refresh_after_resume: false,
    has_frontlight: false, has_wifi_toggle: false, has_seamless_wifi_toggle: false,
    has_ota_updates: false, can_restart: true, can_suspend: false, can_standby: false,
    can_reboot: false, can_power_off: false, supports_screensaver: false,
};
pub fn home_dir(env: Option<String>) -> String { env.unwrap_or_else(|| "/mnt/SDCARD".into()) }
pub fn mupdf_cache_bytes() -> usize { MUPDF_STORE_MB * 1024 * 1024 }
