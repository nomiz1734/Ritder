-- Unit tests for frontend/ritder/diagnostics.lua (the log report the user sends).
local Diagnostics = require("ritder/diagnostics")
local util = require("ritder/update").util

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected a true value", 2) end end
local function falsy(v, msg) if v then error(msg or "expected a false value, got " .. tostring(v), 2) end end

local function sandbox()
    local dir = py_tmpdir()
    Diagnostics.data_dir = dir
    -- The device block needs a running KOReader: the tests replace it.
    Diagnostics.deviceReport = function() return { "Ritder 9.9.9 (thử nghiệm)", "Màn hình: 1024x768" } end
    return dir
end

local tests = {}

function tests.report_has_the_device_block_and_every_log()
    local dir = sandbox()
    util.writeFile(dir .. "/ritder.log", "mở app\nthoát bình thường\n")
    util.writeFile(dir .. "/update.log", "installing update 9.9.9\n")
    util.writeFile(dir .. "/crash.log", "dòng log hiện tại\n")
    local path, size = Diagnostics.collect()
    truthy(path)
    truthy(size > 0)
    local text = util.readFile(path)
    truthy(text:find("Ritder 9.9.9 (thử nghiệm)", 1, true), "device block")
    truthy(text:find("Màn hình: 1024x768", 1, true))
    truthy(text:find("thoát bình thường", 1, true), "run history")
    truthy(text:find("installing update 9.9.9", 1, true), "update history")
    truthy(text:find("dòng log hiện tại", 1, true), "current run")
    truthy(text:find("(không có)", 1, true), "a missing log is reported, not fatal")
end

function tests.report_keeps_only_the_tail_of_a_long_log()
    local dir = sandbox()
    local lines = {}
    for i = 1, 2000 do lines[i] = "dòng " .. i end
    util.writeFile(dir .. "/crash.log", table.concat(lines, "\n"))
    local path = Diagnostics.collect()
    local text = util.readFile(path)
    falsy(text:find("dòng 100\n", 1, true), "old lines are dropped")
    truthy(text:find("dòng 2000", 1, true), "the last lines are kept")
    truthy(#text < 200 * 1024, "the report stays small enough to send")
end

function tests.crash_code_is_reported_once()
    local dir = sandbox()
    util.writeFile(dir .. "/crashed", "139\n")
    eq(Diagnostics.takeCrashCode(), 139)
    eq(Diagnostics.takeCrashCode(), nil, "reading it clears it")
end

return tests
