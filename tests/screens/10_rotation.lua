-- Rotated screen (portrait reading): refresh rectangles must land in the right place.
local books = os.getenv("RITDER_EMU_BOOKS")
local function rotate(mode)
    return function()
        local Event = require("ui/event")
        require("ui/uimanager"):broadcastEvent(Event:new("SetRotationMode", mode))
    end
end
return {
    { "lua", rotate(1), 2 },
    { "keys", "DOWN DOWN" },
    { "shot", "01_list_rotated" },
    { "key", "START", 1 }, { "key", "DOWN" },
    { "shot", "02_menu_rotated" },
    { "key", "B" },
    { "open", books .. "/Sach mau.pdf", 4 },
    { "shot", "03_pdf_rotated" },
}
