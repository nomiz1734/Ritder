--[[--
TrimUI Brick Pro device for Ritder (Allwinner A133p, 1024x768 IPS LCD, 1 GB RAM, buttons only).

Selected by frontend/device.lua when launch.sh sets RITDER_DEVICE=trimui-brick-pro.
It builds on the generic device instead of the SDL one: the display is /dev/fb0
(device/trimui/framebuffer) and the buttons are read straight from evdev
(device/trimui/input_evdev), so nothing depends on the firmware's SDL build.
None of the e-ink machinery (mxcfb/sunxi drivers, waveform modes, HW dithering) is involved.

@module device.trimui.device
]]

local Generic = require("device/generic/device")
local logger = require("logger")

local function yes() return true end
local function no() return false end

-- MuPDF's fitz store. Upstream keeps it at 8 MB; with 1 GB of RAM a larger store avoids
-- re-decoding fonts and images when flipping back and forth in heavy PDF/CBZ files.
local MUPDF_STORE_MB = 32

local TrimUIBrickPro = Generic:extend{
    model = "TrimUI Brick Pro",
    home_dir = os.getenv("RITDER_HOME_DIR") or "/mnt/SDCARD",
    display_dpi = 324,

    isTouchDevice = no,
    hasKeys = yes,
    hasDPad = yes,
    useDPadAsActionKeys = yes,
    hasFewKeys = no,
    hasKeyboard = no,

    hasEinkScreen = no,
    hasColorScreen = yes,
    canHWDither = no,
    canHWInvert = no,
    needsScreenRefreshAfterResume = no,

    hasFrontlight = no, -- the stock OS owns the backlight (MENU + volume keys)
    hasWifiToggle = no, -- and Wi-Fi; networking is assumed available
    hasSeamlessWifiToggle = no,
    hasOTAUpdates = no, -- KOReader's own updater is off, Ritder has its own (ritderupdate plugin)

    canRestart = yes,
    canSuspend = no,
    canStandby = no,
    canReboot = no,
    canPowerOff = no,
}

function TrimUIBrickPro:init()
    -- Before anything builds a menu or a dialog.
    require("ritder/brand").install()

    -- RITDER_EMULATOR=1 (tools/emulate.py): same code, but an in-memory screen and scripted buttons.
    local emulator = os.getenv("RITDER_EMULATOR") == "1"
    if emulator then
        self.screen = require("device/trimui/emu_framebuffer"):new{ device = self, debug = logger.dbg }
    else
        -- Double-buffered; converts to the panel's BGR order itself, so KOReader stays in RGB.
        self.screen = require("device/trimui/framebuffer"):new{ device = self, debug = logger.dbg }
    end
    local size = self.screen:getRawSize()
    logger.info("Ritder: framebuffer", size.w, "x", size.h, "@", self.screen.fb_bpp, "bpp",
        "swap R/B:", self.screen.swap_rb == true)

    self.powerd = require("device/trimui/powerd"):new{ device = self }

    local evdev = require("device/trimui/input_evdev")
    self.input = require("device/input"):new{
        device = self,
        input = evdev,
        event_map = dofile("frontend/device/trimui/event_map.lua"),
    }
    evdev.event_map = self.input.event_map
    if not emulator then
        local opened = evdev.openAll(os.getenv("RITDER_INPUT_DIR") or "/dev/input")
        logger.info("Ritder: opened", opened, "input devices")
    end

    local ok, mupdf = pcall(require, "ffi/mupdf")
    if ok then
        mupdf.cache_size = MUPDF_STORE_MB * 1024 * 1024
    end

    Generic.init(self)

    -- What the logs should say about this run (see ritder/diagnostics.lua).
    local diag_ok, diagnostics = pcall(require, "ritder/diagnostics")
    if diag_ok then
        pcall(diagnostics.logStartup)
    end
end

function TrimUIBrickPro:setEventHandlers(UIManager)
    Generic.setEventHandlers(self, UIManager)
    local script = os.getenv("RITDER_EMU_SCRIPT")
    if os.getenv("RITDER_EMULATOR") == "1" and script then
        require("device/trimui/emulator").run(script, os.getenv("RITDER_EMU_OUT") or ".", UIManager)
    end
end

-- The stock OS handles the power button and sleep itself.
function TrimUIBrickPro:supportsScreensaver() return false end

return TrimUIBrickPro
