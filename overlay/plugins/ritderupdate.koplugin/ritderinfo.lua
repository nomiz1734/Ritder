--[[--
Ritder's own "About", "Version", "Report a bug", "Quickstart guide" and "Collect the logs"
menu entries, replacing KOReader's (which describe KOReader and link to its bug tracker).
]]

local Diagnostics = require("ritder/diagnostics")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local Update = require("ritder/update")
local T = require("ffi/util").template

local REPO = "https://github.com/nomiz1734/Ritder"

local RitderInfo = {}

local GUIDE = [[
Ritder là app đọc sách cho TrimUI Brick Pro, dựa trên KOReader.

SÁCH
• Chép sách vào thư mục Books ở gốc thẻ nhớ.
• Đọc được PDF, CBZ, CBR, EPUB, MOBI, FB2, DjVu, TXT, HTML.

NÚT BẤM
• D-pad: di chuyển trong danh sách và menu.
• A: mở / chọn.   B: quay lại, đóng hộp thoại.
• START hoặc SELECT: menu chính.
• X: menu thao tác với sách đang chọn (xóa, đổi tên, thông tin...).
• Y: về thư mục sách.

KHI ĐỌC
• ← → hoặc L1/R1, L2/R2: lật trang.
• ↑ ↓: hiện con trỏ để chọn chữ, tra từ, mở liên kết (A chọn, B thoát).
• START: menu đọc (mục lục, cỡ chữ, lề, xoay màn hình...).

ĐỘ SÁNG, ÂM LƯỢNG, NGỦ
• Do Stock OS điều khiển như bình thường (nút MENU, âm lượng, nguồn).

CẬP NHẬT
• START → Kiểm tra cập nhật. Máy cần Wi-Fi và đồng hồ đúng giờ.
• Cài đặt, lịch sử và vị trí đang đọc được giữ nguyên khi cập nhật.

DỮ LIỆU
• Cài đặt và lịch sử đọc nằm trong Apps/Ritder/userdata.

KHI CÓ LỖI
• START → Giúp đỡ → Gom log để gửi: app gộp mọi nhật ký thành một file
  Apps/Ritder/userdata/ritder-log.txt để bạn chép ra và gửi đi.

Mã nguồn và báo lỗi: ]] .. REPO

--- Writes the report and tells the user where it is.
function RitderInfo.collectLogs()
    local path, size = Diagnostics.collect()
    if not path then
        UIManager:show(InfoMessage:new{ text = T("Không ghi được log: %1", tostring(size)) })
        return
    end
    UIManager:show(InfoMessage:new{
        text = T("Đã gom log vào file:\n%1  (%2 KB)\n\nFile nằm trong Apps/Ritder/userdata trên thẻ nhớ. Tắt máy, cắm thẻ vào máy tính, chép file đó ra rồi gửi kèm khi báo lỗi.",
            path:match("[^/]+$") or path, math.floor(size / 1024 + 0.5)),
    })
end

function RitderInfo.showGuide()
    UIManager:show(TextViewer:new{
        title = "Hướng dẫn nhanh Ritder",
        text = GUIDE,
    })
end

function RitderInfo.versionText()
    return T("Ritder %1", Update.currentVersion())
end

--- Overrides KOReader's entries in the main menu (called from the plugin's addToMainMenu,
-- which runs after the built-in items are in place).
function RitderInfo.addToMainMenu(menu_items)
    menu_items.quickstart_guide = {
        text = "Hướng dẫn nhanh",
        callback = RitderInfo.showGuide,
    }
    menu_items.version = {
        text = T("Phiên bản: %1", RitderInfo.versionText()),
        keep_menu_open = true,
        callback = function()
            UIManager:show(InfoMessage:new{
                text = T("Ritder %1\nNền KOReader %2", Update.currentVersion(), Update.build_info.koreader_version),
            })
        end,
    }
    menu_items.about = {
        text = "Giới thiệu",
        keep_menu_open = true,
        callback = function()
            UIManager:show(InfoMessage:new{
                text = T("Ritder %1\n\nApp đọc sách cho TrimUI Brick Pro.\n\nDựa trên KOReader %2, giấy phép Affero GPL v3. Mọi thư viện đi kèm đều là phần mềm tự do.\n\n%3",
                    Update.currentVersion(), Update.build_info.koreader_version, REPO),
                icon = "koreader", -- resources/koreader.svg is the Ritder logo
            })
        end,
    }
    menu_items.report_bug = {
        text = "Báo lỗi",
        keep_menu_open = true,
        callback = function()
            UIManager:show(InfoMessage:new{
                text = T("Báo lỗi tại:\n%1/issues\n\nPhiên bản: %2\n\nBấm \"Gom log để gửi\" ngay dưới đây, rồi gửi kèm file ritder-log.txt.",
                    REPO, RitderInfo.versionText()),
            })
        end,
    }
    menu_items.ritder_logs = {
        text = "Gom log để gửi",
        sorting_hint = "help",
        keep_menu_open = true,
        callback = RitderInfo.collectLogs,
    }
    menu_items.ritder_verbose_log = {
        text = "Ghi log chi tiết (chỉ khi cần báo lỗi)",
        sorting_hint = "help",
        checked_func = function() return G_reader_settings:isTrue("debug_verbose") end,
        callback = function()
            local dbg = require("dbg")
            if G_reader_settings:isTrue("debug_verbose") then
                dbg:setVerbose(false)
                dbg:turnOff()
                G_reader_settings:makeFalse("debug_verbose")
                G_reader_settings:makeFalse("debug")
            else
                dbg:turnOn()
                dbg:setVerbose(true)
                G_reader_settings:makeTrue("debug")
                G_reader_settings:makeTrue("debug_verbose")
            end
            UIManager:show(InfoMessage:new{
                text = "Đã bật/tắt ghi log chi tiết. Khởi động lại app để log đầy đủ từ đầu.",
            })
        end,
    }
    -- LCD: KOReader's e-ink refresh/waveform settings do nothing here.
    menu_items.screen_eink_opt = nil
end

return RitderInfo
