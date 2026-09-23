--[[--
Ritder diagnostics: what the device looks like, and one file to send when something breaks.

`logStartup` writes a block into the run's log (`userdata/crash.log`) at every start, so a
log always says which version ran, on what screen, with which buttons and how much room was
left on the card.

`collect` gathers that plus the run history and the tails of every log into
`userdata/ritder-log.txt`, the single file to copy off the SD card and send.

@module ritder.diagnostics
]]

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Diagnostics = {
    REPORT_NAME = "ritder-log.txt",
    -- How many lines of each log go into the report.
    TAILS = {
        { file = "ritder.log", lines = 120, title = "lịch sử chạy" },
        { file = "update.log", lines = 60, title = "lịch sử cập nhật" },
        { file = "crash.log", lines = 250, title = "log lần chạy này" },
        { file = "crash.log.1", lines = 250, title = "log lần chạy trước" },
    },
}

local function dataDir()
    -- Diagnostics.data_dir is only set by the tests.
    return Diagnostics.data_dir or require("datastorage"):getDataDir()
end

local function readAll(path, max_bytes)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    if max_bytes and size > max_bytes then
        f:seek("set", size - max_bytes)
    else
        f:seek("set", 0)
    end
    local data = f:read("*a")
    f:close()
    return data
end

--- The last `count` lines of a text file (nil when there is no such file).
local function tailLines(path, count)
    local data = readAll(path, 256 * 1024)
    if not data then return nil end
    local lines = {}
    for line in data:gmatch("[^\n]*") do
        table.insert(lines, line)
        if #lines > count + 1 then table.remove(lines, 1) end
    end
    return table.concat(lines, "\n")
end

local function shell(cmd)
    local pipe = io.popen(cmd .. " 2>/dev/null")
    if not pipe then return nil end
    local out = pipe:read("*a")
    pipe:close()
    out = (out or ""):gsub("%s+$", "")
    return out ~= "" and out or nil
end

local function mb(bytes)
    return string.format("%.1f MB", (bytes or 0) / 1024 / 1024)
end

--- Lines describing the device, the build and the current state.
function Diagnostics.deviceReport()
    local Device = require("device")
    local Update = require("ritder/update")
    local Screen = Device.screen
    local out = {}
    local function add(fmt, ...)
        table.insert(out, select("#", ...) > 0 and string.format(fmt, ...) or fmt)
    end

    add("Ritder %s (KOReader %s)", Update.currentVersion(), Update.build_info.koreader_version)
    add("Thời điểm: %s", os.date("%Y-%m-%d %H:%M:%S"))
    add("Thiết bị: %s", tostring(Device.model))
    add("Hệ thống: %s", shell("uname -a") or "?")
    local size = Screen:getRawSize()
    add("Màn hình: %dx%d @ %s bpp, đổi R/B: %s, xoay: %s",
        size.w, size.h, tostring(Screen.fb_bpp), tostring(Screen.swap_rb == true), tostring(Screen:getRotationMode()))
    add("Thư mục app: %s", Update.appDir())
    add("Thư mục sách: %s", tostring(Device.home_dir))

    local evdev_ok, evdev = pcall(require, "device/trimui/input_evdev")
    if evdev_ok and evdev.devices then
        local names = {}
        for path, dev in pairs(evdev.devices) do
            table.insert(names, string.format("%s (%s)", path, dev.name or "?"))
        end
        table.sort(names)
        add("Nút bấm: %s", #names > 0 and table.concat(names, ", ") or "không mở được thiết bị nào")
    end

    local free = Update.freeSpace(Update.appDir())
    if free then add("Thẻ nhớ còn trống: %s", mb(free)) end
    local meminfo = readAll("/proc/meminfo", 4096) or ""
    local total, avail = meminfo:match("MemTotal:%s*(%d+)"), meminfo:match("MemAvailable:%s*(%d+)")
    if total then add("RAM: %d MB tổng, %d MB còn trống", total / 1024, (avail or 0) / 1024) end
    if G_reader_settings then
        add("Ngôn ngữ: %s, tự kiểm tra cập nhật: %s",
            tostring(G_reader_settings:readSetting("language")),
            G_reader_settings:nilOrTrue("ritder_auto_update_check") and "bật" or "tắt")
        add("Địa chỉ cập nhật: %s", Update.manifestUrl() ~= "" and Update.manifestUrl() or "(tắt)")
        add("Giữ nguyên màu trang ban đêm: %s",
            require("ritder/night_pages").isKept() and "bật" or "tắt")
    end
    local ready, pending = Update.readyVersion(), Update.pendingVersion()
    if ready then add("Bản đã tải, chờ cài: %s", ready) end
    if pending then add("Bản vừa cài, chờ xác nhận: %s", pending) end
    return out
end

--- Writes the device block into the run's log, at every start.
function Diagnostics.logStartup()
    for _, line in ipairs(Diagnostics.deviceReport()) do
        logger.info("Ritder:", line)
    end
end

--- The exit code of a run that ended badly, if there was one. Reading it clears it.
function Diagnostics.takeCrashCode()
    local path = dataDir() .. "/crashed"
    local data = readAll(path)
    os.remove(path)
    if data then
        data = data:match("%d+")
        if data then return tonumber(data) end
    end
    return nil
end

--- Writes userdata/ritder-log.txt: the device block plus the tail of every log.
-- Returns the path and its size in bytes, or nil + a message.
function Diagnostics.collect()
    local dir = dataDir()
    local path = dir .. "/" .. Diagnostics.REPORT_NAME
    local out, err = io.open(path, "wb")
    if not out then return nil, tostring(err) end

    out:write("===== Ritder =====\n")
    local ok, report = pcall(Diagnostics.deviceReport)
    if ok then
        out:write(table.concat(report, "\n"), "\n")
    else
        out:write("không đọc được thông tin máy: ", tostring(report), "\n")
    end

    for _, tail in ipairs(Diagnostics.TAILS) do
        out:write(string.format("\n===== %s (%s, %d dòng cuối) =====\n", tail.file, tail.title, tail.lines))
        local text = tailLines(dir .. "/" .. tail.file, tail.lines)
        out:write(text or "(không có)", "\n")
    end
    out:close()
    return path, lfs.attributes(path, "size") or 0
end

return Diagnostics
