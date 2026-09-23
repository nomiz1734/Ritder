-- Reading a black-and-white comic with night mode on: the page is inverted by default,
-- and "Giữ nguyên màu trang" (ritder/night_pages.lua) puts it back to black on white.
local books = os.getenv("RITDER_EMU_BOOKS")
local function ui() return require("apps/reader/readerui").instance end
local function night()
    require("ui/uimanager"):broadcastEvent(require("ui/event"):new("ToggleNightMode"))
end
local function keepPages(keep)
    return function()
        require("ritder/night_pages").set(keep, ui())
    end
end
local function assertState(keep)
    return function()
        local NightPages = require("ritder/night_pages")
        assert(NightPages.isKept() == keep, "isKept() should be " .. tostring(keep))
        assert(ui().document.configurable.nightmode_document == (keep and 1 or 0),
            "nightmode_document should follow the switch")
    end
end
return {
    { "open", books .. "/Truyen tranh/Manga den trang.cbz", 4 },
    { "shot", "01_day" },
    { "lua", night, 2 },
    { "shot", "02_night_inverted" },       -- the problem: white lines on black
    { "lua", keepPages(true), 2 },
    { "lua", assertState(true) },
    { "shot", "03_night_pages_kept" },     -- the fix: black on white, UI still dark
    { "key", "START", 1.5 },
    { "shot", "04_menu" },
    { "keys", "RIGHT RIGHT", 1.5 },
    { "shot", "05_menu_settings_tab" },   -- right under "Chế độ ban đêm", ticked
    { "keys", "DOWN" },
    { "shot", "06_menu_item_focused" },
    { "key", "A", 1.5 },                  -- the real path: toggle it from the menu
    { "lua", assertState(false) },
    { "shot", "07_menu_toggled_off" },
}
