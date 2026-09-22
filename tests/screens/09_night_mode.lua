-- Night mode: the focus highlight must stay visible on the inverted screen.
local function night()
    local Event = require("ui/event")
    require("ui/uimanager"):broadcastEvent(Event:new("ToggleNightMode"))
end
return {
    { "lua", night, 1.5 },
    { "keys", "DOWN DOWN" },
    { "shot", "01_list" },
    { "key", "START", 1 },
    { "key", "DOWN" },
    { "shot", "02_menu" },
    { "key", "B" }, { "key", "X", 1 }, { "key", "DOWN" },
    { "shot", "03_dialog" },
}
