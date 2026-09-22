-- Ritder's own dialogs: guide, about, version, update check.
local function fm() return require("apps/filemanager/filemanager").instance end
local function info(id)
    return function()
        local items = {}
        require("ritderinfo").addToMainMenu(items)
        items[id].callback()
    end
end
return {
    { "lua", info("quickstart_guide"), 1.5 },
    { "shot", "01_guide" },
    { "key", "B" },
    { "lua", info("about"), 1 },
    { "shot", "02_about" },
    { "key", "B" },
    { "lua", info("version"), 1 },
    { "shot", "03_version" },
    { "key", "B" },
    { "lua", function() fm().ritderupdate:manualCheck() end, 0.3 },
    { "shot", "04_update_checking" },
    { "wait", 8 },
    { "shot", "05_update_result" },
}
