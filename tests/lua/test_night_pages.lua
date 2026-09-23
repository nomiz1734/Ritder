-- Unit tests for frontend/ritder/night_pages.lua ("Giữ nguyên màu trang" in night mode).
local NightPages = require("ritder/night_pages")

local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected a true value", 2) end end
local function falsy(v, msg) if v then error(msg or "expected a false value, got " .. tostring(v), 2) end end

-- Just enough of LuaSettings for the two keys this module owns.
local function settings()
    local store = {}
    G_reader_settings = {
        readSetting = function(_, key) return store[key] end,
        saveSetting = function(_, key, value) store[key] = value end,
    }
    return store
end

--- A stand-in for the reader UI: records the events, and applies them the way
-- ReaderKoptListener:onConfigChange and ReaderTypeset:onToggleNightmodeImages do
-- (both write to the very table this holds: ui.document.configurable).
-- @param field "nightmode_document" (PDF/CBZ/CBR/DjVu) or "nightmode_images" (EPUB & co)
local function fakeUI(field, value)
    local ui = { events = {} }
    ui.document = { configurable = { [field] = value } }
    function ui:handleEvent(event)
        local name, arg = event.args[1], event.args[2]
        table.insert(self.events, { event.handler, name, arg })
        if event.handler == "onConfigChange" then
            self.document.configurable[name] = arg
        elseif event.handler == "onToggleNightmodeImages" then
            self.document.configurable.nightmode_images = name and 1 or 0
        end
        return true
    end
    return ui
end

local tests = {}

function tests.off_by_default_matching_koreader()
    settings()
    falsy(NightPages.isKept(), "KOReader inverts the page in night mode unless told otherwise")
end

function tests.the_switch_becomes_the_default_for_both_document_kinds()
    local store = settings()
    NightPages.set(true)
    eq(store.kopt_nightmode_document, 1, "paged documents (PDF, CBZ, CBR, DjVu):")
    eq(store.copt_nightmode_images, 1, "reflowable documents (EPUB & co):")
    truthy(NightPages.isKept())
    NightPages.set(false)
    eq(store.kopt_nightmode_document, 0)
    eq(store.copt_nightmode_images, 0)
    falsy(NightPages.isKept())
end

function tests.applies_to_an_open_comic()
    settings()
    local ui = fakeUI("nightmode_document", 0)
    NightPages.set(true, ui)
    eq(#ui.events, 1, "one event:")
    eq(ui.events[1][1], "onConfigChange")
    eq(ui.events[1][2], "nightmode_document")
    eq(ui.events[1][3], 1, "1 pre-inverts the page, so night mode leaves it black on white:")
end

function tests.applies_to_an_open_epub()
    settings()
    local ui = fakeUI("nightmode_images", 0)
    NightPages.set(true, ui)
    eq(#ui.events, 1, "one event:")
    eq(ui.events[1][1], "onToggleNightmodeImages")
    eq(ui.events[1][2], true)
    NightPages.set(false, ui)
    eq(#ui.events, 2)
    eq(ui.events[2][2], false)
end

function tests.a_document_already_in_the_right_state_is_left_alone()
    settings()
    NightPages.set(true)
    local ui = fakeUI("nightmode_document", 1)
    NightPages.applyTo(ui)
    eq(#ui.events, 0, "no repaint when nothing changes:")
end

function tests.a_book_read_before_the_switch_was_flipped_follows_it()
    settings()
    NightPages.set(true)
    -- Sidecar value from an earlier session, opposite of the switch.
    local ui = fakeUI("nightmode_document", 0)
    NightPages.applyTo(ui)
    eq(#ui.events, 1, "the switch wins over the per-document setting:")
    eq(ui.events[1][3], 1)
end

function tests.the_file_browser_has_no_document_to_apply_it_to()
    settings()
    NightPages.set(true, nil)
    NightPages.applyTo({})
    truthy(NightPages.isKept(), "the default is still saved")
end

function tests.the_menu_entry_reflects_and_toggles_the_switch()
    settings()
    local ui = fakeUI("nightmode_document", 0)
    local item = NightPages.menuItem(function() return ui end)
    truthy(item.text:find("màu trang", 1, true), "a name the reader can find under night mode")
    falsy(item.checked_func())
    item.callback()
    truthy(item.checked_func())
    eq(ui.document.configurable.nightmode_document, 1, "the open comic follows straight away")
    item.callback()
    falsy(item.checked_func())
    eq(#ui.events, 2)
end

return tests
