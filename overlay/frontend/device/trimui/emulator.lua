--[[--
Scripted runs for the Ritder emulator (tools/emulate.py).

A script is a Lua file returning a list of steps, run one after the other once the UI is up:

    { "key", "START" }          press + release a button (A B X Y L1 R1 L2 R2 START SELECT MENU UP DOWN LEFT RIGHT),
                                sent as the raw evdev events the Brick Pro produces (D-pad as HAT, L2/R2 as axes)
    { "keys", "DOWN DOWN A" }   several buttons in a row
    { "wait", 1.5 }             let the UI settle (seconds)
    { "shot", "02_menu" }       save the screen as <out>/02_menu.png
    { "open", "/path/book.pdf" } open a document in the reader
    { "lua", function() ... end } anything else

After each step the runner waits `step_delay` seconds (0.6 by default; a step can carry its own
third field). At the end it quits with exit code 0.

@module device.trimui.emulator
]]

local logger = require("logger")

local EV_KEY, EV_ABS = 0x01, 0x03
local ABS_Z, ABS_RZ, ABS_HAT0X, ABS_HAT0Y = 0x02, 0x05, 0x10, 0x11

local KEYS = {
    A = 305, B = 304, X = 308, Y = 307,
    L1 = 310, R1 = 311, SELECT = 314, START = 315, MENU = 316,
}
local HATS = {
    UP = { ABS_HAT0Y, -1 }, DOWN = { ABS_HAT0Y, 1 },
    LEFT = { ABS_HAT0X, -1 }, RIGHT = { ABS_HAT0X, 1 },
}
local TRIGGERS = { L2 = ABS_Z, R2 = ABS_RZ }

local Emulator = {
    step_delay = 0.6,
    start_delay = 5, -- after the first-run "book info cache database updated" notice (3 s)
}

--- Raw evdev events for one press + release of `name`.
function Emulator.eventsFor(name)
    name = name:upper()
    if KEYS[name] then
        return { { type = EV_KEY, code = KEYS[name], value = 1 }, { type = EV_KEY, code = KEYS[name], value = 0 } }
    elseif HATS[name] then
        local axis, value = HATS[name][1], HATS[name][2]
        return { { type = EV_ABS, code = axis, value = value }, { type = EV_ABS, code = axis, value = 0 } }
    elseif TRIGGERS[name] then
        local axis = TRIGGERS[name]
        return { { type = EV_ABS, code = axis, value = 255 }, { type = EV_ABS, code = axis, value = 0 } }
    end
    error("unknown button " .. name)
end

--- Called from Device:setEventHandlers, i.e. while ui/uimanager is still loading: take it as an argument.
function Emulator.run(script_path, out_dir, UIManager)
    local evdev = require("device/trimui/input_evdev")
    local time = require("ui/time")
    local steps = dofile(script_path)

    -- Per-step cost: time spent painting widgets, and screen area copied to the "panel".
    local paint_ms = 0
    local _repaint = UIManager._repaint
    UIManager._repaint = function(um)
        local t0 = time.now()
        _repaint(um)
        paint_ms = paint_ms + time.to_ms(time.now() - t0)
    end
    local function report(label)
        local screen = require("device").screen
        local px = screen.refreshed_pixels or 0
        io.stdout:write(string.format("EMU %-24s paint %6.1f ms, refreshed %5.1f%% of the screen\n",
            label, paint_ms, 100 * px / (screen:getWidth() * screen:getHeight())))
        paint_ms = 0
        screen.refreshed_pixels = 0
    end

    local i = 0
    local last_label
    local function nextStep()
        if last_label then report(last_label) end
        last_label = nil
        i = i + 1
        local step = steps[i]
        if not step then
            logger.info("Ritder emulator: done")
            io.stdout:write("EMU done\n")
            UIManager:quit(0)
            return
        end
        local op, arg = step[1], step[2]
        local delay = step[3] or Emulator.step_delay
        if op == "key" or op == "keys" then
            last_label = op .. " " .. arg
        end
        local ok, err = pcall(function()
            if op == "key" then
                evdev.inject(Emulator.eventsFor(arg))
            elseif op == "keys" then
                -- One press per UI tick, so focus moves are processed one by one.
                local names = {}
                for name in arg:gmatch("%S+") do table.insert(names, name) end
                for n, name in ipairs(names) do
                    UIManager:scheduleIn((n - 1) * 0.25, function() evdev.inject(Emulator.eventsFor(name)) end)
                end
                delay = delay + #names * 0.25
            elseif op == "wait" then
                delay = tonumber(arg) or delay
            elseif op == "shot" then
                UIManager:forceRePaint()
                local path = out_dir .. "/" .. arg .. ".png"
                require("device").screen:shot(path)
                io.stdout:write("EMU shot " .. path .. "\n")
            elseif op == "open" then
                require("apps/reader/readerui"):showReader(arg)
            elseif op == "lua" then
                arg()
            else
                error("unknown step " .. tostring(op))
            end
        end)
        if not ok then
            io.stdout:write("EMU step " .. i .. " (" .. tostring(op) .. ") failed: " .. tostring(err) .. "\n")
        end
        UIManager:scheduleIn(delay, nextStep)
    end
    UIManager:scheduleIn(Emulator.start_delay, function()
        -- First-run notices (e.g. CoverBrowser's "book info cache database updated") would eat
        -- the first key press, at a time that varies between runs: close them for stable shots.
        local InfoMessage = require("ui/widget/infomessage")
        for i = #UIManager._window_stack, 1, -1 do
            local widget = UIManager._window_stack[i].widget
            if getmetatable(widget) == InfoMessage then
                UIManager:close(widget)
            end
        end
        UIManager:scheduleIn(0.5, nextStep)
    end)
end

return Emulator
