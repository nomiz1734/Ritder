--[[--
Download progress dialog: title, a "% • x / y MB" line and a progress bar that can be updated
in place. B (Back) calls `dismiss_callback` so the download can keep going in the background.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local ProgressDialog = InputContainer:extend{
    title = "",
    subtitle = "",
    hint = "",
    dismiss_callback = nil,
}

function ProgressDialog:init()
    local width = math.floor(Screen:getWidth() * 0.7)
    self.title_widget = TextWidget:new{
        text = self.title,
        face = Font:getFace("tfont"),
        bold = true,
        max_width = width,
    }
    self.subtitle_widget = TextWidget:new{
        text = self.subtitle,
        face = Font:getFace("cfont"),
        max_width = width,
    }
    self.progress_widget = ProgressWidget:new{
        width = width,
        height = Screen:scaleBySize(18),
        percentage = 0,
        fillcolor = Blitbuffer.COLOR_BLACK,
    }
    local hint_widget = TextWidget:new{
        text = self.hint,
        face = Font:getFace("smallinfofont"),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width,
    }
    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = Size.padding.large,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title_widget,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.subtitle_widget,
            VerticalSpan:new{ width = Size.span.vertical_default },
            self.progress_widget,
            VerticalSpan:new{ width = Size.span.vertical_large },
            hint_widget,
        },
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.frame,
    }
    if Device:hasKeys() then
        self.key_events.Dismiss = { { Device.input.group.Back } }
    end
end

function ProgressDialog:setProgress(fraction, subtitle)
    self.progress_widget:setPercentage(math.max(0, math.min(1, fraction or 0)))
    if subtitle then
        self.subtitle_widget:setText(subtitle)
    end
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

function ProgressDialog:setTitle(title)
    self.title_widget:setText(title)
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

function ProgressDialog:onDismiss()
    UIManager:close(self)
    if self.dismiss_callback then
        self.dismiss_callback()
    end
    return true
end

function ProgressDialog:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

function ProgressDialog:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.frame.dimen end)
end

return ProgressDialog
