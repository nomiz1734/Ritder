--[[--
LCD-friendly focus highlight for Ritder.

KOReader marks the focused entry of a list with a thin black underline (an
UnderlineContainer whose color flips from white to black). That is meant for e-ink
touch devices; with buttons only it is the one cue of where you are, and on the
Brick's LCD it is easy to miss. Here the focused row gets a light accent background
and a colored underline instead, in every list that uses that mechanism:

* the top menu (TouchMenuItem),
* plain lists (MenuItem),
* the file browser in list and mosaic modes (CoverBrowser's ListMenuItem/MosaicMenuItem).

Focused buttons (dialogs) get the same light blue with a blue frame, instead of turning
black, so every focus cue looks alike.

The text cursor of the reader (UP/DOWN while reading) gets a yellow box and an orange cross
instead of a thin inverted cross that is hard to spot on a page of text.

It also makes the top menu quicker with a D-pad: LEFT/RIGHT switch tabs (KOReader needs UP
to the tab icons first), and LEFT goes back up from a submenu.

@module ritder.ui_theme
]]

local Blitbuffer = require("ffi/blitbuffer")

local Theme = {
    focus_background = Blitbuffer.ColorRGB32(0xD8, 0xE6, 0xFA, 0xFF),
    focus_line = Blitbuffer.ColorRGB32(0x2B, 0x5C, 0xB8, 0xFF),
    cursor_box = Blitbuffer.ColorRGB32(0xFF, 0xEE, 0x8C, 0xFF),
    cursor_line = Blitbuffer.ColorRGB32(0xE0, 0x46, 0x2C, 0xFF),
    patched = {},
}

--- Finds a local (upvalue) named `name` used by any function of module table `mod`.
local function findLocal(mod, name)
    for _, fn in pairs(mod) do
        if type(fn) == "function" then
            for i = 1, 200 do
                local upname, value = debug.getupvalue(fn, i)
                if not upname then break end
                if upname == name then return value end
            end
        end
    end
end

--- Makes `class` (an item widget with an `_underline_container`) use the LCD highlight.
local function patchItemClass(class, key)
    if not class or Theme.patched[key] then return end
    Theme.patched[key] = true
    local onFocus, onUnfocus = class.onFocus, class.onUnfocus
    function class:onFocus(...)
        if onFocus then onFocus(self, ...) end
        local underline = self._underline_container
        if underline then
            underline.ritder_focused = true
            underline.color = Theme.focus_line
        end
        return true
    end
    function class:onUnfocus(...)
        if onUnfocus then onUnfocus(self, ...) end
        if self._underline_container then
            self._underline_container.ritder_focused = nil
        end
        return true
    end
end

local function patchUnderlineContainer()
    local UnderlineContainer = require("ui/widget/container/underlinecontainer")
    local paintTo = UnderlineContainer.paintTo
    function UnderlineContainer:paintTo(bb, x, y)
        local ret = paintTo(self, bb, x, y)
        if self.ritder_focused then
            -- Tint what was just drawn: white turns light blue, black text stays black,
            -- whatever backgrounds the item's own widgets painted.
            local size = self:getSize()
            local w = self.dimen and self.dimen.w or size.w
            bb:multiplyRectRGB(x, y, w, size.h, Theme.focus_background)
        end
        return ret
    end
end

local function patchTouchMenuKeys(TouchMenu)
    local onFocusMove = TouchMenu.onFocusMove
    function TouchMenu:onFocusMove(args)
        local dx, dy = args[1], args[2]
        local on_items = self.selected and self.selected.y > 1
        if dy ~= 0 or dx == 0 or not on_items then
            return onFocusMove(self, args)
        end
        if self.item_table_stack and #self.item_table_stack > 0 then
            if dx < 0 then
                self:backToUpperMenu()
                return true
            end
            return onFocusMove(self, args)
        end
        -- Top level: next/previous tab, skipping the ones that are actions, not menus
        -- (the file browser's "+" tab).
        local count = #self.tab_item_table
        local tab = self.cur_tab
        for _ = 1, count do
            tab = (tab - 1 + dx) % count + 1
            if self.tab_item_table[tab].remember ~= false then break end
        end
        if tab ~= self.cur_tab then
            self.bar:switchToTab(tab)
        end
        return true
    end

    -- KOReader parks the focus on the tab icons after every page/tab/submenu change, so
    -- nothing looks selected until you press DOWN. Land on the first entry instead.
    local updateItems = TouchMenu.updateItems
    function TouchMenu:updateItems(...)
        updateItems(self, ...)
        if self.layout and self.layout[2] and self.layout[2][self.cur_tab] then
            self:moveFocusTo(self.cur_tab, 2)
        end
    end
end

local function patchReaderCursor()
    local ok, ReaderKeySelection = pcall(require, "apps/reader/modules/readerkeyselection")
    if not ok then return end
    local IndicatorOverlay = findLocal(ReaderKeySelection, "IndicatorOverlay")
    if not IndicatorOverlay or not IndicatorOverlay.drawCrosshairs then return end
    local Size = require("ui/size")
    function IndicatorOverlay:drawCrosshairs(bb, rect) -- luacheck: ignore self
        if not rect then return end
        local t = Size.border.thick
        bb:multiplyRectRGB(rect.x, rect.y, rect.w, rect.h, Theme.cursor_box)
        bb:paintRectRGB32(rect.x, math.floor(rect.y + rect.h / 2 - t / 2), rect.w, t, Theme.cursor_line)
        bb:paintRectRGB32(math.floor(rect.x + rect.w / 2 - t / 2), rect.y, t, rect.h, Theme.cursor_line)
    end
end

local function patchButton()
    local ok, Button = pcall(require, "ui/widget/button")
    if not ok then return end
    local Size = require("ui/size")
    function Button:onFocus()
        if self.no_focus then return end
        self.ritder_focused = true
        return true
    end
    function Button:onUnfocus()
        if self.no_focus then return end
        self.ritder_focused = nil
        return true
    end
    local paintTo = Button.paintTo
    function Button:paintTo(bb, x, y)
        paintTo(self, bb, x, y)
        if self.ritder_focused and self.frame then
            local size = self.frame:getSize()
            bb:multiplyRectRGB(x, y, size.w, size.h, Theme.focus_background)
            bb:paintBorderRGB32(x, y, size.w, size.h, Size.border.thick, Theme.focus_line)
        end
    end
end

--- Core widgets (call once the device module is loaded, e.g. from a plugin).
function Theme.install()
    if Theme.installed then return end
    Theme.installed = true
    patchUnderlineContainer()
    local ok, TouchMenu = pcall(require, "ui/widget/touchmenu")
    if ok then
        patchItemClass(findLocal(TouchMenu, "TouchMenuItem"), "TouchMenuItem")
        patchTouchMenuKeys(TouchMenu)
    end
    local ok2, Menu = pcall(require, "ui/widget/menu")
    if ok2 then patchItemClass(findLocal(Menu, "MenuItem"), "MenuItem") end
    patchReaderCursor()
    patchButton()
end

--- CoverBrowser's file list items: its modules can only be required once plugins are loaded.
function Theme.installPlugins()
    local ok, ListMenu = pcall(require, "listmenu")
    if ok and type(ListMenu) == "table" then
        patchItemClass(findLocal(ListMenu, "ListMenuItem"), "ListMenuItem")
    end
    local ok2, MosaicMenu = pcall(require, "mosaicmenu")
    if ok2 and type(MosaicMenu) == "table" then
        patchItemClass(findLocal(MosaicMenu, "MosaicMenuItem"), "MosaicMenuItem")
    end
end

return Theme
