-- Unit tests for the Brick Pro evdev translation (frontend/device/trimui/input_evdev.lua).
local input = require("device/trimui/input_evdev")

local EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
local function ev(etype, code, value, t)
    t = t or 100
    return { type = etype, code = code, value = value, time = { tv_sec = math.floor(t), tv_usec = 0 } }
end

local function run(events, dev)
    dev = dev or { thresholds = { [2] = 127.5, [5] = 127.5, [9] = 127.5, [10] = 127.5 }, triggers = {} }
    local out = {}
    for _, e in ipairs(events) do input._translate(dev, e, out) end
    return out
end

local function keys(out)
    local parts = {}
    for _, e in ipairs(out) do
        assert(e.type == EV_KEY, "only EV_KEY may reach KOReader")
        table.insert(parts, e.code .. ":" .. e.value)
    end
    return table.concat(parts, " ")
end

local function eq(a, b) if a ~= b then error("expected [" .. tostring(b) .. "], got [" .. tostring(a) .. "]", 2) end end

local tests = {}

function tests.hat_becomes_arrow_keys()
    input.held, input.hat = {}, { [16] = 0, [17] = 0 }
    eq(keys(run{ ev(EV_ABS, 17, -1), ev(EV_SYN, 0, 0), ev(EV_ABS, 17, 0) }), "103:1 103:0")
    eq(keys(run{ ev(EV_ABS, 16, 1), ev(EV_ABS, 16, -1), ev(EV_ABS, 16, 0) }), "106:1 106:0 105:1 105:0")
end

function tests.triggers_become_buttons_past_half_travel()
    input.held = {}
    local dev = { thresholds = { [2] = 127.5, [5] = 127.5, [9] = 127.5, [10] = 127.5 }, triggers = {} }
    eq(keys(run({ ev(EV_ABS, 2, 50), ev(EV_ABS, 2, 200), ev(EV_ABS, 2, 255), ev(EV_ABS, 2, 0) }, dev)), "312:1 312:0")
    eq(keys(run({ ev(EV_ABS, 5, 255) }, dev)), "313:1")
end

function tests.buttons_pass_through_and_other_events_are_dropped()
    input.held = {}
    eq(keys(run{ ev(EV_KEY, 305, 1), ev(EV_SYN, 0, 0), ev(4, 4, 90001), ev(EV_ABS, 0, 12000), ev(EV_KEY, 305, 0) }),
        "305:1 305:0")
end

function tests.software_repeat_for_dpad_only_while_held()
    input.held, input.hat = {}, { [16] = 0, [17] = 0 }
    run{ ev(EV_ABS, 17, 1, 100) }
    local out = {}
    input._dueRepeats(out, 100.2)
    eq(#out, 0) -- before the 0.4 s delay
    input._dueRepeats(out, 100.45)
    eq(keys(out), "108:2")
    out = {}
    input._dueRepeats(out, 100.50)
    eq(#out, 0) -- period is 0.1 s
    input._dueRepeats(out, 100.56)
    eq(keys(out), "108:2")
    run{ ev(EV_ABS, 17, 0, 100.6) }
    out = {}
    input._dueRepeats(out, 200)
    eq(#out, 0) -- released: no more repeats
end

function tests.kernel_repeats_of_repeatable_keys_are_ignored()
    input.held = {}
    eq(keys(run{ ev(EV_KEY, 310, 1), ev(EV_KEY, 310, 2), ev(EV_KEY, 305, 2) }), "310:1 305:2")
end

return tests
