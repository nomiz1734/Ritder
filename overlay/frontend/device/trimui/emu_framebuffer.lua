--[[--
In-memory 1024x768 screen for the Ritder emulator (tools/emulate.py).

KOReader draws into this buffer exactly as it draws into /dev/fb0 on the device;
device/trimui/emulator.lua saves it as PNG with Screen:shot().

@module device.trimui.emu_framebuffer
]]

local BB = require("ffi/blitbuffer")

local framebuffer = {}

function framebuffer:init()
    local w = tonumber(os.getenv("RITDER_EMU_W")) or 1024
    local h = tonumber(os.getenv("RITDER_EMU_H")) or 768
    self.bb = BB.new(w, h, BB.TYPE_BBRGB32)
    self.bb:fill(BB.COLOR_WHITE)
    self.fb_bpp = 32
    framebuffer.parent.init(self)
end

function framebuffer:close()
    if self.bb then
        self.bb:free()
        self.bb = nil
    end
end

return require("ffi/framebuffer"):extend(framebuffer)
