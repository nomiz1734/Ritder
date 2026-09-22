-- Unit tests for the double-buffered Brick framebuffer (frontend/device/trimui/framebuffer.lua).
local ffi = require("ffi")

-- Load the driver with its KOReader dependencies stubbed: only copyToScreen/refreshFullImp are tested.
local saved = {}
local stubs = {
    ["ffi/blitbuffer"] = {},
    ["ffi/linux_fb_h"] = true,
    ["ffi/framebuffer_linux"] = { extend = function(_, o) return o end },
}
for name, value in pairs(stubs) do
    saved[name] = package.loaded[name]
    package.loaded[name] = value
end
package.loaded["device/trimui/framebuffer"] = nil
local fb = require("device/trimui/framebuffer")
for name in pairs(stubs) do package.loaded[name] = saved[name] end

local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- A fake BB: w x h pixels of 4 bytes, with its own stride (bytes).
local function buffer(w, h, stride)
    local data = ffi.new("uint8_t[?]", stride * h)
    return { w = w, h = h, stride = stride, data = data,
        px = function(x, y) local p = data + y * stride + x * 4; return p[0], p[1], p[2], p[3] end,
        set = function(x, y, a, b, c, d) local p = data + y * stride + x * 4; p[0], p[1], p[2], p[3] = a, b, c, d end }
end

local tests = {}

function tests.copy_swaps_red_and_blue_for_bgr_panels()
    local src, dst = buffer(4, 3, 16), buffer(4, 3, 24) -- different strides on purpose
    src.set(1, 1, 0xD8, 0xE6, 0xFA, 0xFF)              -- RGBA light blue
    src.set(2, 1, 0x11, 0x22, 0x33, 0x80)
    local self = setmetatable({ bb = src, fb_bb = dst, fb_bpp = 32, swap_rb = true }, { __index = fb })
    self:copyToScreen(1, 1, 2, 1)
    local b, g, r, a = dst.px(1, 1)
    eq(b, 0xFA, "B"); eq(g, 0xE6, "G"); eq(r, 0xD8, "R"); eq(a, 0xFF, "A")
    b, g, r, a = dst.px(2, 1)
    eq(b, 0x33); eq(g, 0x22); eq(r, 0x11); eq(a, 0x80)
    eq(select(1, dst.px(0, 1)), 0, "outside the rect untouched")
    eq(select(1, dst.px(3, 1)), 0, "outside the rect untouched")
end

function tests.copy_is_verbatim_for_rgb_panels()
    local src, dst = buffer(2, 2, 8), buffer(2, 2, 8)
    src.set(0, 0, 1, 2, 3, 4)
    local self = setmetatable({ bb = src, fb_bb = dst, fb_bpp = 32, swap_rb = false }, { __index = fb })
    self:copyToScreen(0, 0, 2, 2)
    local r, g, b, a = dst.px(0, 0)
    eq(r, 1); eq(g, 2); eq(b, 3); eq(a, 4)
end

return tests
