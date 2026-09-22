--[[--
Framebuffer driver for the TrimUI Brick Pro (Ritder): Linux fbdev on an LCD, double-buffered.

KOReader was written for e-ink, where the panel only changes when the driver is told to
refresh, so it draws straight into the framebuffer: a widget is cleared, then its parts are
painted one after the other. On an LCD every one of those steps is visible, and moving the
focus in a list showed the whole screen blanking and redrawing top to bottom (~170 ms).

So KOReader here draws into an off-screen buffer (`self.bb`), and each refresh request copies
just its rectangle to the mapped /dev/fb0 memory in one go: only finished frames reach the panel.

The same copy converts colors: the Brick's fb is ARGB8888 (bytes B, G, R, A) while KOReader's
32-bit buffers are R, G, B, A. Swapping here, instead of flagging a BGR framebuffer, keeps every
color right (UI accents, highlight colors, images) with one code path.

It also makes sure the display shows the first buffer: the stock UI may leave a double-buffered
fb panned to its second half.

@module device.trimui.framebuffer
]]

local BB = require("ffi/blitbuffer")
local bit = require("bit")
local ffi = require("ffi")
local C = ffi.C

require("ffi/linux_fb_h")
require("ffi/posix_h")

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local uint8pt = ffi.typeof("uint8_t*")
local int32pt = ffi.typeof("int32_t*")

local FBIOPAN_DISPLAY = 0x4606

local framebuffer = {
    device_node = os.getenv("RITDER_FB") or "/dev/fb0",
    fb_bb = nil,   -- the mapped framebuffer (what the panel shows)
    swap_rb = false,
}

function framebuffer:init()
    framebuffer.parent.init(self)
    self:panToFirstBuffer()
    -- self.bb is the mapped memory at this point: keep it aside and give KOReader a shadow buffer.
    self.fb_bb = self.bb
    self.swap_rb = self.fb_bpp == 32 and self._vinfo.red.offset ~= 0
    self.bb = BB.new(self.fb_bb.w, self.fb_bb.h, self.fb_bb:getType())
    self.bb:fill(BB.COLOR_WHITE)
    self:copyToScreen(0, 0, self.fb_bb.w, self.fb_bb.h)
end

function framebuffer:panToFirstBuffer()
    local vinfo = self._vinfo
    if vinfo.xoffset == 0 and vinfo.yoffset == 0 then
        return
    end
    self.debug("FB: panning from", vinfo.xoffset, vinfo.yoffset, "to 0,0")
    vinfo.xoffset = 0
    vinfo.yoffset = 0
    if C.ioctl(self.fd, FBIOPAN_DISPLAY, vinfo) ~= 0 then
        -- Not fatal: some drivers only pan through FBIOPUT_VSCREENINFO.
        C.ioctl(self.fd, C.FBIOPUT_VSCREENINFO, vinfo)
    end
end

--- Copies a rectangle, in physical (unrotated) coordinates, from the shadow buffer to the panel.
function framebuffer:copyToScreen(x, y, w, h)
    local src, dst = self.bb, self.fb_bb
    local bpp = self.fb_bpp / 8
    local sstride, dstride = tonumber(src.stride), tonumber(dst.stride)
    local sbase = ffi.cast(uint8pt, src.data) + y * sstride + x * bpp
    local dbase = ffi.cast(uint8pt, dst.data) + y * dstride + x * bpp
    if self.swap_rb then
        -- Little-endian words: RGBA bytes read as 0xAABBGGRR, BGRA bytes as 0xAARRGGBB.
        for row = 0, h - 1 do
            local s = ffi.cast(int32pt, sbase + row * sstride)
            local d = ffi.cast(int32pt, dbase + row * dstride)
            for i = 0, w - 1 do
                local v = s[i]
                d[i] = bor(band(v, 0xFF00FF00), band(rshift(v, 16), 0xFF), lshift(band(v, 0xFF), 16))
            end
        end
    else
        local n = w * bpp
        for row = 0, h - 1 do
            ffi.copy(dbase + row * dstride, sbase + row * sstride, n)
        end
    end
end

-- Every refresh flavor (partial, UI, fast, flash...) ends up here by default.
function framebuffer:refreshFullImp(x, y, w, h)
    if not self.fb_bb then return end
    x, y, w, h = self.bb:getBoundedRect(x, y, w, h)
    if w <= 0 or h <= 0 then return end
    x, y, w, h = self.bb:getPhysicalRect(x, y, w, h)
    self:copyToScreen(x, y, w, h)
end

function framebuffer:close(reinit)
    -- framebuffer_linux frees self.bb (our shadow) and unmaps the memory fb_bb points to.
    if self.fb_bb then
        self.fb_bb:free()
        self.fb_bb = nil
    end
    framebuffer.parent.close(self, reinit)
end

return require("ffi/framebuffer_linux"):extend(framebuffer)
