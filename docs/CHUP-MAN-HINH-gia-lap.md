# Chụp ảnh màn hình Ritder bằng chế độ giả lập trên PC

*Viết ngày 22/09/2026, theo code bản 0.1.1. Code chính: `tools/emulate.py`, `overlay/frontend/device/trimui/emulator.lua`, `overlay/frontend/device/trimui/emu_framebuffer.lua`, `tests/screens/*.lua`.*

## 1. Tóm tắt

Ritder có chế độ **chạy app trên PC, bấm nút theo kịch bản và lưu từng màn hình thành PNG 1024×768**, không cần máy TrimUI:

```powershell
python tools\emulate.py --setup      # một lần: tạo distro WSL1 "RitderEmu"
python tools\emulate.py              # chạy mọi kịch bản trong tests\screens
python tools\emulate.py 02_main_menu # chỉ chạy một kịch bản
```

Ảnh nằm trong `dist\emulator\shots\<kịch bản>\*.png`, kèm `run.log` (toàn bộ log của app).

Khác với Spoty (tự vẽ giao diện bằng Rust nên build được bản Windows), Ritder là KOReader: Lua + thư viện C chỉ có cho Linux. Vì vậy giả lập chạy **bản KOReader Linux x86_64 cùng phiên bản** (v2026.07.1) + đúng lớp Ritder (`overlay/`, 3 chỗ vá) trong **WSL1**. Phần Lua, tức toàn bộ giao diện, menu, focus, xử lý nút, đọc sách, OTA, là **đúng code chạy trên máy**. Chỉ màn hình và nút bấm được thay:

| Trên máy | Trong giả lập |
|---|---|
| `/dev/fb0` (`device/trimui/framebuffer.lua`) | Blitbuffer 1024×768 trong RAM (`emu_framebuffer.lua`) |
| Nút đọc từ `/dev/input/event*` | Kịch bản gửi **đúng các sự kiện evdev thô của Brick Pro** (D-pad là trục HAT, L2/R2 là trục analog), đi qua cùng hàm dịch của `input_evdev.lua` |
| Thẻ nhớ, sách của bạn | `dist\emulator\Books`: PDF, CBZ, EPUB mẫu do script tạo |
| `userdata/` giữ qua các lần mở | `dist\emulator\userdata` tạo mới mỗi lần, từ `package/stock/defaults` (như lần cài đầu) |

Mình dùng ảnh làm **bằng chứng** sau mỗi lần sửa giao diện: chạy, mở từng ảnh ra xem, sửa tới khi đúng mới phát hành.

## 2. Chuẩn bị (một lần)

- **WSL1**, không cần WSL2 hay ảo hóa phần cứng (máy này không bật được WSL2/Docker). `--setup` tải Ubuntu base 24.04 (ghim SHA-256 trong `upstream.json`, mục `wsl_rootfs`) và `wsl --import` thành distro riêng `RitderEmu` trong `vendor\wsl\distro`. Distro Ubuntu có sẵn của bạn không bị đụng tới. Gỡ: `wsl --unregister RitderEmu`.
- Python 3 + Pillow (để tạo sách mẫu). Font chữ lấy từ `C:\Windows\Fonts\arial.ttf`.
- Bản KOReader x86_64 được tải tự động vào `vendor\cache` (mục `koreader_emulator` trong `upstream.json`).

## 3. Viết kịch bản

Mỗi file `tests\screens\<tên>.lua` trả về một danh sách bước, chạy lần lượt sau khi app mở xong (chờ 5 giây, đóng các thông báo lần đầu để lần bấm đầu tiên không bị nuốt):

```lua
local books = os.getenv("RITDER_EMU_BOOKS")
return {
    { "key", "START", 1 },                 -- bấm 1 nút, chờ 1 giây (mặc định 0,6 giây)
    { "keys", "DOWN DOWN A" },             -- nhiều nút liên tiếp
    { "shot", "01_menu" },                 -- lưu 01_menu.png
    { "open", books .. "/Sach mau.pdf", 4 },  -- mở sách, chờ 4 giây
    { "wait", 8 },
    { "lua", function() ... end },         -- gọi thẳng code bất kỳ
}
```

Tên nút: `A B X Y L1 R1 L2 R2 START SELECT MENU UP DOWN LEFT RIGHT`.

## 4. Các kịch bản có sẵn

| Kịch bản | Kiểm tra |
|---|---|
| `01_file_browser` | Màn đầu, tiêu đề "Ritder", nền xanh ở sách đang chọn, menu thao tác (X) và nút đang chọn |
| `02_main_menu` | START mở menu và chọn sẵn mục đầu, LEFT/RIGHT đổi tab, A vào menu con, LEFT quay lại, tab chính có "Kiểm tra cập nhật", Giúp đỡ là mục của Ritder, không còn "Cài đặt màn hình E-ink" |
| `03_reader_epub` | Trang EPUB tiếng Việt, lật trang bằng →, menu đọc, con trỏ chọn chữ (ô vàng + dấu thập cam) |
| `04_reader_pdf_cbz` | PDF lật bằng R1, CBZ lật bằng R2 (trục analog), Y về thư mục |
| `05_ritder_dialogs` | Hướng dẫn nhanh, Giới thiệu (logo Ritder), Phiên bản, **kiểm tra cập nhật thật** qua GitHub |
| `06_exit_menu` | Menu Thoát: "Khởi động lại Ritder" (chuỗi gốc có chữ KOReader) |

## 5. Những gì giả lập đã bắt được (bản 0.1.1)

- Menu không có mục nào được tô khi mở, phải bấm DOWN mới thấy (KOReader đặt focus lên hàng biểu tượng tab).
- Muốn đổi tab phải bấm UP lên hàng biểu tượng trước.
- Nền xanh bị ô trắng của phần tử con vẽ đè, và vẽ bằng `paintRect` thì màu bị đổi sang xám → chuyển sang tô kiểu "multiply" sau khi vẽ.
- **Lỗi OTA của 0.1.0**: "Kiểm tra cập nhật" luôn lỗi (`attempt to call local 'close_sink'`). Unit test không bắt được vì đã giả lập `httpGet`; giờ có thêm test chạy `httpGet` thật với `ssl.https` giả.

## 6. Giới hạn

- **Không thử được phần cứng**: `/dev/fb0`, mã nút thật, tốc độ A133p, glibc đi kèm trong `sys/` (bản x86_64 dùng glibc của WSL), Wi-Fi của máy. Những phần đó vẫn phải thử trên TrimUI.
- Pin hiện 0% và không đổi (WSL không có pin).
- Ảnh chụp ngay sau bước cuối; hiệu ứng động không có (KOReader cũng gần như không có).
- Thời gian khởi động và vẽ trang trên PC nhanh hơn máy nhiều, không dùng để đo tốc độ.
