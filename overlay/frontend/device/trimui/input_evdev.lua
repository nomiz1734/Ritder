--[[--
Pure-FFI evdev input backend for the TrimUI Brick Pro (Ritder).

It implements the same interface as KOReader's `libs/libkoreader-input` (open, close, closeAll,
waitForEvent), which the upstream linux-arm64 build does not ship, and it only hands EV_KEY
events to `device/input`:

* the D-pad (ABS_HAT0X/ABS_HAT0Y) becomes KEY_UP/KEY_DOWN/KEY_LEFT/KEY_RIGHT;
* the analog triggers (ABS_Z/ABS_RZ) become BTN_TL2/BTN_TR2;
* every other EV_ABS/EV_SYN/EV_MSC event is dropped, so that KOReader's touch code never sees them;
* the D-pad and shoulder buttons get software key repeat (the gamepad driver has none).

The device is never grabbed: the stock OS still sees MENU/volume/power for brightness and sleep.

@module device.trimui.input_evdev
]]

local bit = require("bit")
local ffi = require("ffi")
local logger = require("logger")
local C = ffi.C

require("ffi/posix_h")
require("ffi/linux_input_h")

ffi.cdef[[
struct ritder_input_absinfo {
    int32_t value;
    int32_t minimum;
    int32_t maximum;
    int32_t fuzz;
    int32_t flat;
    int32_t resolution;
};
]]

local EV_KEY, EV_ABS = 0x01, 0x03
local ABS_Z, ABS_RZ, ABS_GAS, ABS_BRAKE = 0x02, 0x05, 0x09, 0x0a
local ABS_HAT0X, ABS_HAT0Y = 0x10, 0x11
local KEY_UP, KEY_LEFT, KEY_RIGHT, KEY_DOWN = 103, 105, 106, 108
local BTN_TL, BTN_TR, BTN_TL2, BTN_TR2 = 310, 311, 312, 313
local KEY_RELEASE, KEY_PRESS, KEY_REPEAT = 0, 1, 2

-- _IOC(_IOC_READ, 'E', nr, size)
local function EVIOC_READ(nr, size)
    local v = bit.bor(bit.lshift(2, 30), bit.lshift(size, 16), bit.lshift(0x45, 8), nr)
    -- bit.* works on signed 32-bit values; ioctl wants the unsigned request number.
    if v < 0 then v = v + 2^32 end
    return v
end
local EVIOCGNAME_256 = EVIOC_READ(0x06, 256)
local function EVIOCGABS(abs) return EVIOC_READ(0x40 + abs, ffi.sizeof("struct ritder_input_absinfo")) end

local REPEAT_DELAY = 0.40  -- seconds before the first repeat
local REPEAT_PERIOD = 0.10 -- seconds between repeats
local REPEATABLE = {
    [KEY_UP] = true, [KEY_DOWN] = true, [KEY_LEFT] = true, [KEY_RIGHT] = true,
    [BTN_TL] = true, [BTN_TR] = true, [BTN_TL2] = true, [BTN_TR2] = true,
}
-- Analog axes that act as buttons, and the key code they produce.
local TRIGGER_KEYS = {
    [ABS_Z] = BTN_TL2, [ABS_BRAKE] = BTN_TL2,
    [ABS_RZ] = BTN_TR2, [ABS_GAS] = BTN_TR2,
}

local input = {
    is_ffi = true,
    devices = {}, -- path -> { fd, name, thresholds = { [abs] = value }, triggers = { [abs] = pressed } }
    held = {},    -- key code -> next repeat time (seconds)
    event_map = nil, -- set by the device, only to log presses of unmapped keys
    hat = { [ABS_HAT0X] = 0, [ABS_HAT0Y] = 0 },
}

local timeval = ffi.new("struct timeval")
local function now()
    C.gettimeofday(timeval, nil)
    return tonumber(timeval.tv_sec) + tonumber(timeval.tv_usec) / 1e6
end

local function makeEvent(code, value, t)
    local sec = math.floor(t)
    return {
        type = EV_KEY,
        code = code,
        value = value,
        time = { sec = sec, usec = math.floor((t - sec) * 1e6) },
    }
end

local function deviceName(fd)
    local buf = ffi.new("char[256]")
    if C.ioctl(fd, EVIOCGNAME_256, buf) >= 0 then
        return ffi.string(buf)
    end
    return "?"
end

-- Middle of the axis range; a trigger counts as pressed past it.
local function triggerThreshold(fd, abs)
    local info = ffi.new("struct ritder_input_absinfo")
    if C.ioctl(fd, EVIOCGABS(abs), info) >= 0 and info.maximum > info.minimum then
        return info.minimum + (info.maximum - info.minimum) / 2
    end
    return 0.5
end

function input.open(path, name)
    if input.devices[path] then
        return true
    end
    local fd = C.open(path, bit.bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
    if fd < 0 then
        logger.warn("Ritder input: cannot open", path, ffi.string(C.strerror(ffi.errno())))
        return false
    end
    local dev = { fd = fd, name = name or deviceName(fd), thresholds = {}, triggers = {} }
    for abs in pairs(TRIGGER_KEYS) do
        dev.thresholds[abs] = triggerThreshold(fd, abs)
    end
    input.devices[path] = dev
    logger.info("Ritder input: opened", path, dev.name)
    return true
end

function input.close(path)
    local dev = input.devices[path]
    if dev then
        C.close(dev.fd)
        input.devices[path] = nil
    end
    return true
end

function input.closeAll()
    for path in pairs(input.devices) do
        input.close(path)
    end
    input.held = {}
    return true
end

--- Opens every /dev/input/event* node. Returns how many could be opened.
function input.openAll(dir)
    local lfs = require("libs/libkoreader-lfs")
    dir = dir or "/dev/input"
    local count = 0
    local ok, iter, state = pcall(lfs.dir, dir)
    if not ok then
        logger.warn("Ritder input: cannot list", dir)
        return 0
    end
    local nodes = {}
    for entry in iter, state do
        if entry:match("^event%d+$") then
            table.insert(nodes, entry)
        end
    end
    table.sort(nodes)
    for _, entry in ipairs(nodes) do
        if input.open(dir .. "/" .. entry) then
            count = count + 1
        end
    end
    return count
end

local function press(out, code, value, t)
    table.insert(out, makeEvent(code, value, t))
    if REPEATABLE[code] then
        if value == KEY_PRESS then
            input.held[code] = t + REPEAT_DELAY
        elseif value == KEY_RELEASE then
            input.held[code] = nil
        end
    end
end

local function translateHat(out, code, value, t)
    local old = input.hat[code] or 0
    if value == old then return end
    input.hat[code] = value
    local neg, pos
    if code == ABS_HAT0X then
        neg, pos = KEY_LEFT, KEY_RIGHT
    else
        neg, pos = KEY_UP, KEY_DOWN
    end
    if old < 0 then press(out, neg, KEY_RELEASE, t) end
    if old > 0 then press(out, pos, KEY_RELEASE, t) end
    if value < 0 then press(out, neg, KEY_PRESS, t) end
    if value > 0 then press(out, pos, KEY_PRESS, t) end
end

local function translate(dev, ev, out)
    local t = tonumber(ev.time.tv_sec) + tonumber(ev.time.tv_usec) / 1e6
    local etype, code, value = ev.type, ev.code, ev.value
    if etype == EV_KEY then
        if value == KEY_REPEAT and REPEATABLE[code] then
            return -- we generate our own, evenly spaced repeats
        end
        if value == KEY_PRESS and input.event_map and not input.event_map[code] then
            logger.info("Ritder input: unmapped key code", code)
        end
        press(out, code, value, t)
    elseif etype == EV_ABS then
        if code == ABS_HAT0X or code == ABS_HAT0Y then
            translateHat(out, code, value < 0 and -1 or (value > 0 and 1 or 0), t)
        elseif TRIGGER_KEYS[code] then
            local pressed = value > dev.thresholds[code]
            if pressed ~= (dev.triggers[code] or false) then
                dev.triggers[code] = pressed
                press(out, TRIGGER_KEYS[code], pressed and KEY_PRESS or KEY_RELEASE, t)
            end
        end
    end
    -- EV_SYN, EV_MSC and the rest are dropped on purpose.
end

local function dueRepeats(out, t)
    for code, due in pairs(input.held) do
        if t >= due then
            table.insert(out, makeEvent(code, KEY_REPEAT, t))
            input.held[code] = t + REPEAT_PERIOD
        end
    end
end

local function nextRepeat()
    local soonest
    for _, due in pairs(input.held) do
        if not soonest or due < soonest then soonest = due end
    end
    return soonest
end

local ev_buf = ffi.new("struct input_event[64]")
local ev_size = ffi.sizeof("struct input_event")

--- Waits for input. Returns true + an array of events, or false + errno (C.ETIME on timeout).
function input.waitForEvent(sec, usec)
    local deadline
    if sec then
        deadline = now() + sec + (usec or 0) / 1e6
    end
    while true do
        local paths, n = {}, 0
        for path in pairs(input.devices) do
            n = n + 1
            paths[n] = path
        end
        local pfds = ffi.new("struct pollfd[?]", math.max(n, 1))
        for i = 1, n do
            pfds[i - 1].fd = input.devices[paths[i]].fd
            pfds[i - 1].events = C.POLLIN
        end

        local t = now()
        local wake = deadline
        local rep = nextRepeat()
        if rep and (not wake or rep < wake) then wake = rep end
        local timeout_ms = -1
        if wake then
            timeout_ms = math.max(0, math.ceil((wake - t) * 1000))
        end

        local ret = C.poll(pfds, n, timeout_ms)
        if ret < 0 then
            local err = ffi.errno()
            if err == C.EINTR then
                return false, C.EINTR
            end
            return false, err
        end

        local out = {}
        if ret > 0 then
            for i = 1, n do
                local revents = pfds[i - 1].revents
                if revents ~= 0 then
                    local path = paths[i]
                    local dev = input.devices[path]
                    while true do
                        local got = C.read(dev.fd, ev_buf, ev_size * 64)
                        if got < 0 then
                            local err = ffi.errno()
                            if err == C.ENODEV then
                                logger.warn("Ritder input: device gone", path)
                                input.close(path)
                            end
                            break
                        end
                        local count = math.floor(tonumber(got) / ev_size)
                        for j = 0, count - 1 do
                            translate(dev, ev_buf[j], out)
                        end
                        if count < 64 then break end
                    end
                end
            end
        end

        t = now()
        dueRepeats(out, t)
        if #out > 0 then
            return true, out
        end
        if deadline and t >= deadline then
            return false, C.ETIME
        end
    end
end

-- For tests (tests/lua/test_input_evdev.lua).
input._translate = translate
input._dueRepeats = dueRepeats

return input
