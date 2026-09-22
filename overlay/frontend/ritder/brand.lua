--[[--
Ritder branding on top of KOReader.

Every user-visible string goes through gettext, so wrapping gettext once is enough to show
"Ritder" wherever KOReader's UI says "KOReader" (file browser title, exit/restart entries,
dialogs...), in every language. Lower-case "koreader" (paths, URLs) is left alone.

Called from the device init, before any menu or dialog is built.

@module ritder.brand
]]

local Brand = {
    name = "Ritder",
    repo_url = "https://github.com/nomiz1734/Ritder",
}

local function rebrand(s)
    if type(s) == "string" and s:find("KOReader", 1, true) then
        return (s:gsub("KOReader", Brand.name))
    end
    return s
end
Brand.rebrand = rebrand

function Brand.install()
    if Brand.installed then return end
    Brand.installed = true
    local gettext = require("gettext")
    local mt = getmetatable(gettext)
    local call = mt.__call
    mt.__call = function(g, msgid)
        return rebrand(call(g, msgid))
    end
    for _, name in ipairs{ "ngettext", "pgettext", "npgettext" } do
        local fn = mt.__index[name]
        if fn then
            mt.__index[name] = function(...) return rebrand(fn(...)) end
        end
    end
end

return Brand
