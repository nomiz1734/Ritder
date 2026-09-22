--[[--
Framebuffer driver for the TrimUI Brick Pro (Ritder): plain Linux fbdev on an LCD.

KOReader draws straight into the mmap'ed /dev/fb0, and an LCD shows every write immediately,
so there is no refresh work at all (no waveform, no dithering, no e-ink ioctls). The only
thing to take care of is the pan offset: the stock UI may leave the display on the second
buffer of a double-buffered fb, in which case we would draw into a buffer nobody shows.

@module device.trimui.framebuffer
]]

local ffi = require("ffi")
local C = ffi.C

require("ffi/linux_fb_h")
require("ffi/posix_h")

local FBIOPAN_DISPLAY = 0x4606

local framebuffer = {
    device_node = os.getenv("RITDER_FB") or "/dev/fb0",
}

function framebuffer:init()
    framebuffer.parent.init(self)
    self:panToFirstBuffer()
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

return require("ffi/framebuffer_linux"):extend(framebuffer)
