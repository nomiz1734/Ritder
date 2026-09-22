--[[--
In-memory 1024x768 screen for the Ritder emulator (tools/emulate.py).

Like the device driver (device/trimui/framebuffer.lua), KOReader draws into a shadow buffer
and only refresh requests copy rectangles to the "panel". Screenshots are taken from the
panel, so they show what the LCD would show, including anything painted but never refreshed.

@module device.trimui.emu_framebuffer
]]

local BB = require("ffi/blitbuffer")
local ffi = require("ffi")

local uint8pt = ffi.typeof("uint8_t*")

local framebuffer = {}

function framebuffer:init()
    local w = tonumber(os.getenv("RITDER_EMU_W")) or 1024
    local h = tonumber(os.getenv("RITDER_EMU_H")) or 768
    self.bb = BB.new(w, h, BB.TYPE_BBRGB32)
    self.bb:fill(BB.COLOR_WHITE)
    self.panel = BB.new(w, h, BB.TYPE_BBRGB32)
    self.panel:fill(BB.COLOR_WHITE)
    self.fb_bpp = 32
    self.refreshed_pixels = 0 -- for the emulator's stats
    framebuffer.parent.init(self)
end

function framebuffer:refreshFullImp(x, y, w, h)
    x, y, w, h = self.bb:getBoundedRect(x, y, w, h)
    if w <= 0 or h <= 0 then return end
    x, y, w, h = self.bb:getPhysicalRect(x, y, w, h)
    local src, dst = self.bb, self.panel
    local sstride, dstride = tonumber(src.stride), tonumber(dst.stride)
    local sbase = ffi.cast(uint8pt, src.data) + y * sstride + x * 4
    local dbase = ffi.cast(uint8pt, dst.data) + y * dstride + x * 4
    for row = 0, h - 1 do
        ffi.copy(dbase + row * dstride, sbase + row * sstride, w * 4)
    end
    self.refreshed_pixels = self.refreshed_pixels + w * h
end

function framebuffer:shot(filename)
    self.panel:writePNG(filename)
end

function framebuffer:close()
    if self.bb then self.bb:free(); self.bb = nil end
    if self.panel then self.panel:free(); self.panel = nil end
end

return require("ffi/framebuffer"):extend(framebuffer)
