--[[--
Ritder OTA updates: MENU entry "Kiểm tra cập nhật", an automatic check 8 s after start,
background download + install, restart with exit code 42 and the post-update confirmation.

The network and disk work runs in a forked child (ffiutil.runInSubProcess) so the reader
stays usable; the UI polls the child. See frontend/ritder/update.lua for the mechanics and
docs/OTA-co-che-cap-nhat.md for the whole flow.

@module koplugin.ritderupdate
]]

local ConfirmBox = require("ui/widget/confirmbox")
local Diagnostics = require("ritder/diagnostics")
local InfoMessage = require("ui/widget/infomessage")
local NightPages = require("ritder/night_pages")
local Notification = require("ui/widget/notification")
local ProgressDialog = require("progressdialog")
local RitderInfo = require("ritderinfo")
local UIManager = require("ui/uimanager")
local Update = require("ritder/update")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local rapidjson = require("rapidjson")
local T = ffiutil.template

local AUTO_CHECK_DELAY_S = 8
local CONFIRM_AFTER_S = 10
local POLL_S = 0.5
local STALLED_S = 180 -- no progress for this long: let the user give up
local RESTART_EXIT_CODE = 42
local MAX_NOTES_LINES = 6

-- Shared by every instance: the plugin is re-created each time we switch
-- between the file browser and the reader, but these happen once per process.
local state = {
    started = false,
    available = nil,  -- manifest of a newer version, once known
    job = nil,        -- { pid, manifest, background }
    installed = nil,  -- version unpacked and waiting for a restart to be installed
    progress = nil,   -- the open ProgressDialog, if any
    instance = nil,   -- the plugin instance of the current UI (file browser or reader)
}

-- Background jobs outlive the UI that started them: always talk to the live one.
local function live(fallback)
    return state.instance or fallback
end

local function formatMB(bytes)
    return string.format("%.1f", (bytes or 0) / 1024 / 1024)
end

local function trimNotes(notes)
    local lines = {}
    for line in (notes or ""):gmatch("[^\n]+") do
        if #lines == MAX_NOTES_LINES then
            table.insert(lines, "…")
            break
        end
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

--- Runs `fn` in a child process; `on_done(result_table)` gets what fn returned (a table).
local function runInChild(fn, on_done)
    local pid, read_fd = ffiutil.runInSubProcess(function(_, write_fd)
        local ok, result = pcall(fn)
        if not ok then
            result = { status = "error", err = tostring(result) }
        end
        ffiutil.writeToFD(write_fd, rapidjson.encode(result), true)
    end, true)
    if not pid then
        on_done({ status = "error", err = tostring(read_fd) })
        return
    end
    local function poll()
        if ffiutil.getNonBlockingReadSize(read_fd) > 0 or ffiutil.isSubProcessDone(pid) then
            local data = ffiutil.readAllFromFD(read_fd)
            ffiutil.isSubProcessDone(pid, true)
            local ok, result = pcall(rapidjson.decode, data or "")
            if not ok or type(result) ~= "table" then
                result = { status = "error", err = "tiến trình kiểm tra dừng bất thường" }
            end
            on_done(result)
        else
            UIManager:scheduleIn(POLL_S, poll)
        end
    end
    UIManager:scheduleIn(POLL_S, poll)
    return pid
end

local RitderUpdate = WidgetContainer:extend{
    name = "ritderupdate",
    is_doc_only = false,
}

function RitderUpdate:init()
    state.instance = self
    -- LCD focus highlight. Done here, not in the device init: the widgets need the device
    -- module, and the file browser's list items come from CoverBrowser, loaded as a plugin too.
    local Theme = require("ritder/ui_theme")
    Theme.install()
    Theme.installPlugins()
    self.ui.menu:registerToMainMenu(self)
    if not state.started then
        state.started = true
        UIManager:nextTick(function() self:onStartup() end)
    end
end

-- Start-up -----------------------------------------------------------------

function RitderUpdate:onStartup()
    local work_dir = Update.workDir()

    -- launch.sh leaves this behind when it had to go back to the previous version.
    local rolled_back = Update.util.readFile(work_dir .. "/rolled_back")
    if rolled_back then
        os.remove(work_dir .. "/rolled_back")
        UIManager:show(InfoMessage:new{
            text = T("Bản cập nhật %1 bị lỗi khi khởi động nên Ritder đã quay về bản %2.\n\nChi tiết: userdata/update.log",
                rolled_back:match("^%s*(.-)%s*$"), Update.currentVersion()),
        })
    end

    -- launch.sh writes this when the app exited badly: offer to gather the logs right away.
    local crash_code = Diagnostics.takeCrashCode()
    if crash_code then
        UIManager:show(ConfirmBox:new{
            text = T("Lần chạy trước kết thúc bất thường (mã %1).\nGom log lại để gửi báo lỗi?", crash_code),
            ok_text = "Gom log",
            cancel_text = "Bỏ qua",
            ok_callback = function() RitderInfo.collectLogs() end,
        })
    end

    local failed = Update.takeFailedVersion()
    if failed then
        UIManager:show(InfoMessage:new{
            text = T("Không cài được bản %1 (không thay được file trên thẻ nhớ).\nRitder vẫn đang chạy bản %2.\n\nChi tiết: userdata/update.log",
                failed, Update.currentVersion()),
        })
    end
    state.installed = Update.readyVersion()

    local pending = Update.pendingVersion()
    if pending then
        Notification:notify(T("Đã cập nhật lên phiên bản %1", Update.currentVersion()), Notification.SOURCE_ALWAYS_SHOW)
        UIManager:scheduleIn(CONFIRM_AFTER_S, function()
            Update.confirm()
            logger.info("Ritder update: version", Update.currentVersion(), "confirmed")
        end)
    end

    if G_reader_settings:nilOrTrue("ritder_auto_update_check") and Update.manifestUrl() ~= "" then
        UIManager:scheduleIn(AUTO_CHECK_DELAY_S, function() self:autoCheck() end)
    end
end

function RitderUpdate:autoCheck()
    if state.job or state.installed then return end
    runInChild(function() return RitderUpdate.checkInChild() end, function(result)
        if result.status == "available" then
            state.available = result.manifest
            Notification:notify(T("Có bản cập nhật %1 — xem trong MENU", result.manifest.version),
                Notification.SOURCE_ALWAYS_SHOW)
        elseif result.status == "error" then
            logger.warn("Ritder update check:", result.err)
        else
            logger.info("Ritder update check: up to date")
        end
    end)
end

-- Runs in the child process.
function RitderUpdate.checkInChild()
    local manifest, err = Update.check()
    if manifest then
        return { status = "available", manifest = manifest }
    elseif manifest == false then
        return { status = "uptodate", version = err and err.version }
    end
    return { status = "error", err = err }
end

--- The switch in the menu wins over what this book was last read with.
function RitderUpdate:onReaderReady()
    NightPages.applyTo(self.ui)
end

-- Menu ---------------------------------------------------------------------

function RitderUpdate:addToMainMenu(menu_items)
    RitderInfo.addToMainMenu(menu_items)
    -- Under "Chế độ ban đêm": keep comics and illustrations in their own colors.
    menu_items.ritder_night_pages = NightPages.menuItem(function()
        return self.ui and self.ui.document and self.ui or nil
    end)
    menu_items.ritder_update = {
        text_func = function()
            if state.installed then
                return T("Khởi động lại để cài bản %1", state.installed)
            elseif state.job then
                return "Đang tải bản cập nhật…"
            elseif state.available then
                return T("Cập nhật lên phiên bản %1", state.available.version)
            end
            return "Kiểm tra cập nhật"
        end,
        sorting_hint = "main",
        sub_item_table_func = function() return self:subMenu() end,
    }
end

function RitderUpdate:subMenu()
    return {
        {
            text_func = function()
                if state.installed then
                    return T("Khởi động lại để cài bản %1", state.installed)
                elseif state.job then
                    return "Xem tiến trình tải"
                elseif state.available then
                    return T("Cập nhật lên phiên bản %1", state.available.version)
                end
                return "Kiểm tra cập nhật"
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                if touchmenu_instance then touchmenu_instance:closeMenu() end
                self:onMenuAction()
            end,
        },
        {
            text = "Tự kiểm tra khi mở app",
            checked_func = function() return G_reader_settings:nilOrTrue("ritder_auto_update_check") end,
            callback = function()
                G_reader_settings:flipNilOrTrue("ritder_auto_update_check")
            end,
        },
        {
            text_func = function()
                return T("Phiên bản: Ritder %1 (KOReader %2)", Update.currentVersion(), Update.build_info.koreader_version)
            end,
            enabled = false,
        },
    }
end

function RitderUpdate:onMenuAction()
    if state.installed then
        self:askRestart(state.installed)
    elseif state.job then
        state.job.background = false
        self:showProgress()
    elseif state.available then
        self:showAvailable(state.available)
    else
        self:manualCheck()
    end
end

-- Dialog states: Checking -> UpToDate | Available -> Downloading -> Installing -> Ready | Failed

function RitderUpdate:manualCheck()
    if Update.manifestUrl() == "" then
        UIManager:show(InfoMessage:new{
            text = "Chưa cấu hình địa chỉ cập nhật (ritder_update_url trong settings.reader.lua).",
        })
        return
    end
    local cancelled = false
    local checking = InfoMessage:new{
        text = "Đang kiểm tra bản cập nhật…",
        dismiss_callback = function() cancelled = true end,
    }
    UIManager:show(checking)
    local pid
    pid = runInChild(function() return RitderUpdate.checkInChild() end, function(result)
        if cancelled then return end
        UIManager:close(checking)
        local plugin = live(self)
        if result.status == "available" then
            state.available = result.manifest
            plugin:showAvailable(result.manifest)
        elseif result.status == "uptodate" then
            UIManager:show(InfoMessage:new{
                text = T("Bạn đang dùng bản mới nhất (%1).", Update.currentVersion()),
            })
        else
            plugin:showFailed(result.err, function() live(plugin):manualCheck() end)
        end
    end)
    checking.dismiss_callback = function()
        cancelled = true
        if pid then ffiutil.terminateSubProcess(pid) end
    end
end

function RitderUpdate:showAvailable(manifest)
    local text = T("Có phiên bản mới: %1\nĐang dùng: %2", manifest.version, Update.currentVersion())
    if manifest.size then
        text = text .. T("\nDung lượng: %1 MB", formatMB(manifest.size))
    end
    local notes = trimNotes(manifest.notes)
    if notes ~= "" then
        text = text .. "\n\n" .. notes
    end
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = "Cập nhật ngay",
        cancel_text = "Để sau",
        ok_callback = function() self:startDownload(manifest) end,
    })
end

function RitderUpdate:showFailed(err, retry)
    UIManager:show(ConfirmBox:new{
        text = "Không cập nhật được\n\n" .. tostring(err or "lỗi không rõ"),
        ok_text = "Thử lại",
        cancel_text = "Đóng",
        ok_callback = retry,
    })
end

function RitderUpdate:startDownload(manifest)
    if state.job then return end
    Update.setStatus("downloading")
    os.remove(Update.packagePath())
    local job = { manifest = manifest, background = false }
    state.job = job
    job.pid = runInChild(function()
        local ok, err = Update.downloadAndStage(manifest)
        return { status = ok and "done" or "error", err = err }
    end, function(result)
        live(self):onJobDone(job, result)
    end)
    if not job.pid then return end
    self:showProgress()
    self:pollProgress(job)
end

function RitderUpdate:showProgress()
    local job = state.job
    if not job or state.progress then return end
    state.progress = ProgressDialog:new{
        title = T("Đang tải bản cập nhật %1", job.manifest.version),
        subtitle = "0%",
        hint = "B: chạy nền, bạn vẫn đọc sách bình thường",
        dismiss_callback = function()
            job.background = true
            state.progress = nil
        end,
    }
    UIManager:show(state.progress)
end

function RitderUpdate:pollProgress(job)
    if state.job ~= job then return end
    local status, detail = Update.readStatus()
    local size = lfs.attributes(Update.packagePath(), "size") or 0
    -- Watchdog: the job is meant to make progress (bytes downloaded, then files unpacked).
    local mark = tostring(status) .. ":" .. tostring(detail) .. ":" .. size
    if mark ~= job.mark then
        job.mark, job.mark_at = mark, os.time()
    elseif job.mark_at and os.time() - job.mark_at > STALLED_S then
        job.mark_at = nil
        self:onStalled(job)
        return
    end
    local progress = state.progress
    if progress then
        if status == "unpacking" then
            progress:setTitle("Đang giải nén…")
            progress:setProgress(1, detail ~= "" and T("%1 tệp", detail) or "")
        else
            local total = job.manifest.size
            if total and total > 0 then
                local fraction = size / total
                progress:setProgress(fraction, T("%1% • %2 / %3 MB",
                    math.floor(fraction * 100), formatMB(size), formatMB(total)))
            else
                progress:setProgress(0, T("%1 MB", formatMB(size)))
            end
        end
    end
    UIManager:scheduleIn(POLL_S, function() self:pollProgress(job) end)
end

function RitderUpdate:onJobDone(job, result)
    state.job = nil
    if state.progress then
        UIManager:close(state.progress)
        state.progress = nil
    end
    if result.status == "done" then
        state.available = nil
        state.installed = job.manifest.version
        logger.info("Ritder update:", job.manifest.version, "unpacked, waiting for a restart")
        self:askRestart(job.manifest.version)
    else
        local err = result.err
        local status, message = Update.readStatus()
        if status == "failed" and message ~= "" then err = message end
        logger.warn("Ritder update failed:", err)
        self:showFailed(err, function() live(self):startDownload(job.manifest) end)
    end
end

function RitderUpdate:askRestart(version)
    UIManager:show(ConfirmBox:new{
        text = T("Đã tải xong phiên bản %1.\nKhởi động lại để cài (mất vài giây).", version),
        ok_text = "Khởi động lại",
        cancel_text = "Để sau",
        ok_callback = function() self:restart() end,
    })
end

--- Nothing has moved for a while: let the user stop instead of watching a frozen dialog.
function RitderUpdate:onStalled(job)
    if job.pid then ffiutil.terminateSubProcess(job.pid) end
    state.job = nil
    if state.progress then
        UIManager:close(state.progress)
        state.progress = nil
    end
    logger.warn("Ritder update: no progress for", STALLED_S, "s, gave up")
    Update.discard()
    self:showFailed(T("quá trình cập nhật không nhúc nhích trong %1 giây nên đã dừng", STALLED_S),
        function() live(self):startDownload(job.manifest) end)
end

function RitderUpdate:restart()
    -- Close the book properly (saves position and settings), then exit with 42:
    -- launch.sh re-runs itself, and installs the unpacked update before starting the app.
    self.ui.menu:exitOrRestart(function() UIManager:quit(RESTART_EXIT_CODE) end)
end

return RitderUpdate
