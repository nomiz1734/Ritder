-- The log report the user sends: the Help entry, the file it writes, and the notice
-- shown when the previous run ended badly.
local Diagnostics = require("ritder/diagnostics")
return {
    { "lua", function()
        -- Pretend launch.sh recorded a bad exit and a run history.
        local dir = require("datastorage"):getDataDir()
        local f = io.open(dir .. "/crashed", "w") f:write("139\n") f:close()
        f = io.open(dir .. "/ritder.log", "w")
        f:write("2026-09-23 10:00:00 mở app: Ritder 0.1.4, kernel 4.9.170\n")
        f:write("2026-09-23 10:20:11 thoát bất thường (mã 139)\n")
        f:close()
        require("apps/filemanager/filemanager").instance.ritderupdate:onStartup()
    end, 2 },
    { "shot", "01_crash_notice" },
    { "key", "A", 2 },
    { "shot", "02_collected" },
    { "lua", function()
        local path = require("datastorage"):getDataDir() .. "/" .. Diagnostics.REPORT_NAME
        local f = io.open(path)
        local text = f and f:read("*a") or "(không có)"
        if f then f:close() end
        io.stdout:write("EMU report:\n" .. text:sub(1, 1800) .. "\nEMU report end\n")
    end },
}
