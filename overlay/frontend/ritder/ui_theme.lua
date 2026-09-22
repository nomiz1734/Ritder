--[[--
LCD look and feel for Ritder: focus highlight, D-pad menu navigation, lighter repaints.

KOReader marks the focused entry with a thin black underline (an UnderlineContainer whose
color flips from white to black), meant for e-ink touch devices. With buttons only it is
the one cue of where you are, and on the Brick's LCD it is easy to miss. Here:

* top menu entries (TouchMenuItem) get a rounded light-blue background, inset like the
  menu's separator lines, and no underline;
* list rows (MenuItem, CoverBrowser's ListMenuItem) get a light-blue tint over the whole
  row plus an accent bar on the left; grid tiles (MosaicMenuItem) a tint and a frame;
* dialog buttons get the tint and a frame instead of turning black;
* the reader's text cursor (UP/DOWN while reading) gets a yellow box and an orange cross.

In night mode the screen buffer is inverted: tints are skipped (they could only darken) and
rows get a frame instead; the accent color shows up as amber on black.

Moving the focus used to repaint the whole window (the entire file list with its covers)
for a change of two rows. When both rows are known widgets with known positions and their
window is on top, only those two are repainted and refreshed.

The top menu is also quicker with a D-pad: LEFT/RIGHT switch tabs (KOReader needs UP to
the tab icons first), LEFT goes back up from a submenu, and the first entry is selected
whenever a page, tab or submenu opens.

@module ritder.ui_theme
]]

local Blitbuffer = require("ffi/blitbuffer")

local Theme = {
    focus_background = Blitbuffer.ColorRGB32(0xD8, 0xE6, 0xFA, 0xFF),
    focus_accent = Blitbuffer.ColorRGB32(0x2B, 0x5C, 0xB8, 0xFF),
    cursor_box = Blitbuffer.ColorRGB32(0xFF, 0xEE, 0x8C, 0xFF),
    cursor_line = Blitbuffer.ColorRGB32(0xE0, 0x46, 0x2C, 0xFF),
    patched = {},
    -- Widget classes that repaint cleanly over a white rectangle (see repaintFocusChange).
    partial_classes = {},
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

local function size()
    return require("ui/size")
end

-- Highlight styles -----------------------------------------------------------

--- List rows and grid tiles: flag their UnderlineContainer, painted by patchUnderlineContainer.
local function patchRowClass(class, key, style)
    if not class or Theme.patched[key] then return end
    Theme.patched[key] = true
    Theme.partial_classes[class] = true
    local onFocus, onUnfocus = class.onFocus, class.onUnfocus
    function class:onFocus(...)
        if onFocus then onFocus(self, ...) end
        local underline = self._underline_container
        if underline then
            underline.ritder_focus = style
            underline.color = Blitbuffer.COLOR_WHITE -- the tint replaces the underline
        end
        return true
    end
    function class:onUnfocus(...)
        if onUnfocus then onUnfocus(self, ...) end
        if self._underline_container then
            self._underline_container.ritder_focus = nil
        end
        return true
    end
end

--- Tints a rectangle with the focus color. Not in night mode: the screen buffer is inverted
-- there, and multiplying can only darken, which would hide white-on-black text.
-- Returns false when it did not tint (callers then draw a frame instead).
local function tint(bb, x, y, w, h, color)
    if bb:getInverse() == 1 then return false end
    bb:multiplyRectRGB(x, y, w, h, color)
    return true
end
Theme.tint = tint

local function isWhite(color)
    return color and color.getColor8 and color:getColor8().a == 0xFF
end

local function patchUnderlineContainer()
    local BD = require("ui/bidi")
    local Geom = require("ui/geometry")
    local UnderlineContainer = require("ui/widget/container/underlinecontainer")
    -- Same as UnderlineContainer:paintTo, plus two changes:
    -- * the "invisible" white underline is not drawn: it hangs below the item, over the separator
    --   line the parent paints next. Harmless in a full repaint, but it erases part of that line
    --   when only the item is repainted (see repaintFocusChange);
    -- * focused rows and tiles get their tint, accent bar or frame.
    function UnderlineContainer:paintTo(bb, x, y)
        local container_size = self:getSize()
        if not self.dimen then
            self.dimen = Geom:new{ x = x, y = y, w = container_size.w, h = container_size.h }
        else
            self.dimen.x = x
            self.dimen.y = y
        end
        local content_size = self[1]:getSize()
        local p_y = y
        if self.vertical_align == "center" then
            p_y = math.floor((container_size.h - content_size.h) / 2) + y
        elseif self.vertical_align == "bottom" then
            p_y = (container_size.h - content_size.h) + y
        end
        self[1]:paintTo(bb, x, p_y)

        local style = self.ritder_focus
        if not style and not isWhite(self.color) then
            local line_width = self.line_width or self.dimen.w
            local line_x = x
            if BD.mirroredUILayout() then
                line_x = line_x + self.dimen.w - line_width
            end
            bb:paintRect(line_x, y + container_size.h - self.linesize, line_width, self.linesize, self.color)
        end
        if style then
            -- Tint what was just drawn: white turns light blue, black text stays black,
            -- whatever backgrounds the item's own widgets painted.
            local w = self.dimen.w
            local tinted = tint(bb, x, y, w, container_size.h, Theme.focus_background)
            local line = size().border.thick
            if style == "row" then
                bb:paintRectRGB32(x, y, 2 * line, container_size.h, Theme.focus_accent)
            end
            if style ~= "row" or not tinted then
                bb:paintBorderRGB32(x, y, w, container_size.h, line, Theme.focus_accent)
            end
        end
    end
end

--- Top menu entries: rounded background painted first, lined up with the separators.
local function patchTouchMenuItem(TouchMenuItem)
    if not TouchMenuItem or Theme.patched.TouchMenuItem then return end
    Theme.patched.TouchMenuItem = true
    Theme.partial_classes[TouchMenuItem] = true
    function TouchMenuItem:onFocus()
        self.ritder_focused = true
        self._underline_container.color = Blitbuffer.COLOR_WHITE
        return true
    end
    function TouchMenuItem:onUnfocus()
        self.ritder_focused = nil
        self._underline_container.color = Blitbuffer.COLOR_WHITE
        return true
    end
    local paintTo = TouchMenuItem.paintTo
    function TouchMenuItem:paintTo(bb, x, y)
        if self.ritder_focused and self.dimen then
            local S = size()
            -- Same horizontal inset as TouchMenu's separator lines; a little air above/below.
            local inset = S.span.horizontal_default
            local gap = S.padding.tiny
            bb:paintRoundedRectRGB32(x + inset, y + gap, self.dimen.w - 2 * inset, self.dimen.h - 2 * gap,
                Theme.focus_background, S.radius.default)
            bb:paintRectRGB32(x + inset, y + gap + S.radius.default, S.border.thick * 2,
                self.dimen.h - 2 * gap - 2 * S.radius.default, Theme.focus_accent)
        end
        return paintTo(self, bb, x, y)
    end
end

local function patchButton()
    local ok, Button = pcall(require, "ui/widget/button")
    if not ok or Theme.patched.Button then return end
    Theme.patched.Button = true
    Theme.partial_classes[Button] = true
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
            local s = self.frame:getSize()
            tint(bb, x, y, s.w, s.h, Theme.focus_background)
            bb:paintBorderRGB32(x, y, s.w, s.h, size().border.thick, Theme.focus_accent)
        end
    end
end

local function patchReaderCursor()
    local ok, ReaderKeySelection = pcall(require, "apps/reader/modules/readerkeyselection")
    if not ok then return end
    local IndicatorOverlay = findLocal(ReaderKeySelection, "IndicatorOverlay")
    if not IndicatorOverlay or not IndicatorOverlay.drawCrosshairs then return end
    function IndicatorOverlay:drawCrosshairs(bb, rect) -- luacheck: ignore self
        if not rect then return end
        local t = size().border.thick
        tint(bb, rect.x, rect.y, rect.w, rect.h, Theme.cursor_box)
        bb:paintRectRGB32(rect.x, math.floor(rect.y + rect.h / 2 - t / 2), rect.w, t, Theme.cursor_line)
        bb:paintRectRGB32(math.floor(rect.x + rect.w / 2 - t / 2), rect.y, t, rect.h, Theme.cursor_line)
    end
end

-- Menu navigation ------------------------------------------------------------

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

-- Partial repaint on focus moves ---------------------------------------------

--- Repaints just `items` (the widgets that lost/gained focus). Returns false when that is
-- not safe, and the caller then repaints the whole window as KOReader does.
function Theme.repaintFocusChange(host, items)
    local UIManager = require("ui/uimanager")
    local Screen = require("device").screen
    local stack = UIManager._window_stack
    local top = stack[#stack]
    if not top or top.widget ~= host then return false end -- something is drawn above us
    if #items == 0 then return false end
    for _, w in ipairs(items) do
        if not Theme.partial_classes[getmetatable(w)] then return false end
        local d = w.dimen
        if not (d and d.x and d.y and d.w and d.h and d.w > 0 and d.h > 0) then return false end
        if w.show_parent and w.show_parent.cropping_widget then return false end -- scrolled dialogs
    end
    local region
    for _, w in ipairs(items) do
        local d = w.dimen
        Screen.bb:paintRect(d.x, d.y, d.w, d.h, Blitbuffer.COLOR_WHITE)
        w:paintTo(Screen.bb, d.x, d.y)
        region = region and region:combine(d) or d:copy()
    end
    UIManager:setDirty(nil, "fast", region)
    return true
end

local function patchFocusRepaint()
    local FocusManager = require("ui/widget/focusmanager")
    local UIManager = require("ui/uimanager")
    local onFocusMove = FocusManager.onFocusMove
    function FocusManager:onFocusMove(args)
        local host = self.show_parent or self
        local before = self.getFocusItem and self:getFocusItem()
        local swallowed, other = false, false
        local setDirty = UIManager.setDirty
        -- Hold back the "repaint the whole window" request FocusManager makes after a move.
        UIManager.setDirty = function(um, widget, refresh, ...)
            if widget == host and refresh == "fast" and select("#", ...) == 0 then
                swallowed = true
                return
            end
            other = true
            return setDirty(um, widget, refresh, ...)
        end
        local ok, ret = pcall(onFocusMove, self, args)
        UIManager.setDirty = setDirty
        if not ok then error(ret, 0) end
        if swallowed then
            local after = self.getFocusItem and self:getFocusItem()
            local items = {}
            if before and before ~= after then table.insert(items, before) end
            if after then table.insert(items, after) end
            if other or not Theme.repaintFocusChange(host, items) then
                UIManager:setDirty(host, "fast")
            end
        end
        return ret
    end
end

-- Install --------------------------------------------------------------------

--- Core widgets (call once the device module is loaded, e.g. from a plugin).
function Theme.install()
    if Theme.installed then return end
    Theme.installed = true
    -- First: TouchMenu's own onFocusMove (below) must wrap this one, not the original.
    patchFocusRepaint()
    patchUnderlineContainer()
    local ok, TouchMenu = pcall(require, "ui/widget/touchmenu")
    if ok then
        patchTouchMenuItem(findLocal(TouchMenu, "TouchMenuItem"))
        patchTouchMenuKeys(TouchMenu)
    end
    local ok2, Menu = pcall(require, "ui/widget/menu")
    if ok2 then patchRowClass(findLocal(Menu, "MenuItem"), "MenuItem", "row") end
    patchButton()
    patchReaderCursor()
end

--- CoverBrowser's file list items: its modules can only be required once plugins are loaded.
function Theme.installPlugins()
    local ok, ListMenu = pcall(require, "listmenu")
    if ok and type(ListMenu) == "table" then
        patchRowClass(findLocal(ListMenu, "ListMenuItem"), "ListMenuItem", "row")
    end
    local ok2, MosaicMenu = pcall(require, "mosaicmenu")
    if ok2 and type(MosaicMenu) == "table" then
        patchRowClass(findLocal(MosaicMenu, "MosaicMenuItem"), "MosaicMenuItem", "tile")
    end
end

return Theme
