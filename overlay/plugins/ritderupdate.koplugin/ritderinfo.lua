--[[--
Ritder's own "About", "Version", "Report a bug" and "Quickstart guide" menu entries,
replacing KOReader's (which describe KOReader and link to its bug tracker).
]]

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
• Nhật ký lỗi: Apps/Ritder/userdata/crash.log.

Mã nguồn và báo lỗi: ]] .. REPO

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
                text = T("Báo lỗi tại:\n%1/issues\n\nPhiên bản: %2\n\nGửi kèm file Apps/Ritder/userdata/crash.log.",
                    REPO, RitderInfo.versionText()),
            })
        end,
    }
    -- LCD: KOReader's e-ink refresh/waveform settings do nothing here.
    menu_items.screen_eink_opt = nil
end

return RitderInfo
