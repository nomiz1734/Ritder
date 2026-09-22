-- Linux evdev key codes of the TrimUI Brick Pro gamepad -> KOReader key names.
-- The D-pad and L2/R2 are axes on this device; input_evdev.lua turns them into
-- KEY_UP/DOWN/LEFT/RIGHT and BTN_TL2/BTN_TR2 before they reach this map.
-- To remap without rebuilding, put an event_map.lua in userdata/settings/
-- (same format); KOReader merges it over this one.
return {
    [103] = "Up",          -- D-pad
    [108] = "Down",
    [105] = "Left",
    [106] = "Right",
    [305] = "Press",       -- A (BTN_EAST): open / confirm
    [304] = "Back",        -- B (BTN_SOUTH): back / close
    [308] = "ContextMenu", -- X (BTN_WEST, top face button): long-press actions
    [307] = "Home",        -- Y (BTN_NORTH, left face button): file browser
    [310] = "LPgBack",     -- L1: previous page
    [311] = "RPgFwd",      -- R1: next page
    [312] = "LPgBack",     -- L2 (analog trigger)
    [313] = "RPgFwd",      -- R2 (analog trigger)
    [315] = "Menu",        -- START: main menu
    [314] = "Menu",        -- SELECT: main menu
    -- 316 (MENU) and the volume/power keys are left to the stock OS
    -- (brightness, volume, sleep), so they are not mapped here.
}
