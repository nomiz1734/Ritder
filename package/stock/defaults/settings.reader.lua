-- Ritder first-run settings, copied to userdata/settings.reader.lua by launch.sh
-- only when that file does not exist yet (updates never overwrite the user's settings).
return {
    ["language"] = "vi",
    ["home_dir"] = "@HOME_DIR@",
    ["lastdir"] = "@HOME_DIR@",
    ["left_right_keys_turn_pages"] = true,
    -- The Brick has a color LCD: skip KOReader's first-run notice about color rendering.
    ["color_rendering"] = true,
    -- Skip KOReader's quickstart document on first start (Ritder's guide is in the Help menu).
    ["quickstart_shown_version"] = 9999999999,
}
