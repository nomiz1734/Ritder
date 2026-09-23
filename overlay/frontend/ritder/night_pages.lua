--[[--
"Giữ nguyên màu trang" in night mode.

Night mode inverts everything that is painted, artwork included, so a black-and-white comic
turns into white-on-black line art. KOReader can pre-invert the page so the two inversions
cancel out and it keeps its own colors: `nightmode_document` for PDF/CBZ/CBR/DjVu (default
0, page inverted) and `nightmode_images` for EPUB and friends (default 1, images kept).
Both live in the per-document option bar and only appear while night mode is on, which is
why they are hard to find. This is the same thing as one switch under "Chế độ ban đêm":
it applies to the open book, to the ones opened later, and wins over what a book was last
read with.

@module ritder.night_pages
]]

local Event = require("ui/event")

local NightPages = {}

--- True when pages and artwork keep their own colors in night mode (only the UI is inverted).
function NightPages.isKept()
    return G_reader_settings:readSetting("kopt_nightmode_document") == 1
end

--- Applies the current choice to an open document. Does nothing in the file browser.
function NightPages.applyTo(ui)
    local document = ui and ui.document
    local configurable = document and document.configurable
    if not configurable then return end
    local want = NightPages.isKept() and 1 or 0
    if configurable.nightmode_document ~= nil then -- PDF, CBZ, CBR, DjVu
        if configurable.nightmode_document ~= want then
            ui:handleEvent(Event:new("ConfigChange", "nightmode_document", want))
        end
    elseif configurable.nightmode_images ~= nil then -- EPUB and other reflowable formats
        if configurable.nightmode_images ~= want then
            ui:handleEvent(Event:new("ToggleNightmodeImages", want == 1))
        end
    end
end

--- @param keep true to leave pages and artwork alone, false for KOReader's behavior.
-- @param ui the reader UI, to apply it to the open book as well (optional).
function NightPages.set(keep, ui)
    -- The default for every book opened from now on: Configurable:loadDefaults() reads these.
    G_reader_settings:saveSetting("kopt_nightmode_document", keep and 1 or 0)
    G_reader_settings:saveSetting("copt_nightmode_images", keep and 1 or 0)
    NightPages.applyTo(ui)
end

--- The menu entry, shown right under "Chế độ ban đêm".
-- @param get_ui returns the reader UI when a book is open, nil in the file browser.
function NightPages.menuItem(get_ui)
    return {
        text = "Giữ nguyên màu trang",
        help_text = "Chế độ ban đêm đảo màu mọi thứ, nên truyện tranh đen trắng thành nền đen nét trắng. "
            .. "Bật mục này để trang sách và hình ảnh giữ nguyên màu gốc, chỉ giao diện bị đảo. "
            .. "Áp dụng cho cả sách đang đọc lẫn sách mở sau này.",
        checked_func = NightPages.isKept,
        -- Greyed out in day mode: it changes nothing there, but it stays visible so the
        -- entry is where the reader looks for it, right under the night mode switch.
        enabled_func = function() return require("device").screen.night_mode end,
        callback = function()
            NightPages.set(not NightPages.isKept(), get_ui and get_ui())
        end,
    }
end

return NightPages
