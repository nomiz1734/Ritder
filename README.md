# Ritder

App đọc sách cho **TrimUI Brick Pro**, dựa trên [KOReader](https://github.com/koreader/koreader). Ưu tiên đọc mượt PDF và truyện tranh CBZ/CBR trên màn hình LCD 1024×768, điều khiển hoàn toàn bằng nút bấm, tự cập nhật qua GitHub Releases.

Phiên bản hiện tại: **0.1.3** (dựa trên KOReader v2026.07.1).

> Đã chạy trên Brick Pro thật (firmware gốc): màn hình, nút bấm, pin, tiếng Việt. Giao diện được kiểm tra thêm bằng giả lập trên PC: [docs/CHUP-MAN-HINH-gia-lap.md](docs/CHUP-MAN-HINH-gia-lap.md).
>
> **Đang dùng 0.1.0, 0.1.1 hoặc 0.1.2?** Cách cài của các bản đó có lỗi (0.1.0 không kiểm tra được bản mới; 0.1.1 và 0.1.2 treo ở bước "Đang cài đặt" vì app tự thay file của chính nó). Hãy cài 0.1.3 **bằng tay một lần**: giải nén `Ritder-stock.zip`, chép đè vào `Apps/Ritder`, giữ nguyên `userdata/`. Từ 0.1.3 trở đi cập nhật qua MENU.

## Cài đặt

1. Tải `Ritder-stock.zip` ở [Releases](https://github.com/nomiz1734/Ritder/releases/latest).
2. Giải nén, chép thư mục `Ritder` vào `Apps/` trên thẻ nhớ (`Apps/Ritder/launch.sh`).
3. Chép sách vào `Books/` ở gốc thẻ nhớ (app tự tạo thư mục này lần đầu).
4. Mở **Ritder** trong menu Apps của Stock OS.

Cập nhật về sau: **MENU → Kiểm tra cập nhật**. Cài đặt, lịch sử và vị trí đang đọc nằm trong `Apps/Ritder/userdata/` và không bao giờ bị cập nhật ghi đè.

## Điều khiển

| Nút | Trong thư mục sách | Khi đọc |
|---|---|---|
| D-pad | Di chuyển | ← → lật trang; ↑ ↓ hiện con trỏ để chọn chữ, bấm liên kết (A chọn, B thoát) |
| A | Mở | Chọn |
| B | Quay lại | Quay lại / đóng hộp thoại |
| X | Menu thao tác (xóa, đổi tên, thông tin…) | Menu thao tác |
| Y | Về thư mục sách | Về thư mục sách |
| L1 / L2 | Trang trước | Trang trước |
| R1 / R2 | Trang sau | Trang sau |
| START / SELECT | Menu chính | Menu chính |
| MENU, âm lượng, nguồn | Để Stock OS xử lý (độ sáng, âm lượng, ngủ) | |

Trong menu chính: ↑ ↓ chọn mục, ← → đổi tab, A mở, ← hoặc B quay lại menu cha. Mục đang chọn luôn có nền xanh.

Giữ D-pad hoặc nút vai để lặp. Đổi cách gán nút: tạo `userdata/settings/event_map.lua` (cùng dạng với `overlay/frontend/device/trimui/event_map.lua`).

## Kiến trúc

Ritder là **KOReader gốc + một lớp chồng (overlay)**, không phải bản sao toàn bộ mã nguồn KOReader:

```
upstream.json                KOReader linux-arm64 (bản build chính thức) + glibc 2.36 Debian, ghim SHA-256
overlay/                     chép đè lên cây KOReader:
  frontend/device/trimui/    thiết bị Brick Pro: framebuffer, input evdev, pin, bảng phím
  frontend/ritder/update.lua lõi OTA (không có giao diện, chạy được trong tiến trình con)
  frontend/ritder/brand.lua  đổi mọi chuỗi "KOReader" thành "Ritder" (qua gettext)
  frontend/ritder/ui_theme.lua  highlight mục đang chọn, chỉ vẽ lại 2 mục khi đổi focus, ← → đổi tab, con trỏ chọn chữ
  resources/koreader.{png,svg}  logo Ritder thay logo KOReader
  plugins/ritderupdate.koplugin  giao diện OTA (MENU, hộp thoại, tiến trình tải)
package/stock/               launch.sh, install.sh (thay file khi cập nhật), config.json, icon, cài đặt lần đầu
tools/build.py               ghép dist/Ritder: tải + kiểm SHA-256 + chồng overlay + vá 3 chỗ
tools/make_update.py         gói OTA + update.json
tools/publish_release.py     tạo GitHub Release
tools/emulate.py             chạy Ritder trên PC (WSL1) theo kịch bản, chụp PNG từng màn hình
tools/make_icon.py           vẽ icon và logo
tests/lua/                   unit test Lua (chạy bằng LuaJIT nhúng qua lupa)
tests/screens/               kịch bản chụp màn hình cho tools/emulate.py
tests/shell/                 test cho install.sh, chạy trong WSL
docs/OTA-co-che-cap-nhat.md  toàn bộ cơ chế cập nhật
```

Những quyết định chính, và lý do:

- **Không tự biên dịch KOReader.** Phần nặng (MuPDF, CREngine, DjVuLibre, k2pdfopt) lấy nguyên từ bản build arm64 chính thức, nên build trên Windows chỉ cần Python. Ritder chỉ thêm Lua.
- **Mang theo glibc.** Bản arm64 của KOReader cần glibc ≥ 2.35 (và libstdc++ của GCC 12), firmware TrimUI cũ hơn. `launch.sh` chạy `sys/ld-linux-aarch64.so.1 --library-path sys:libs luajit reader.lua`, không đặt `LD_LIBRARY_PATH`, nên các lệnh hệ thống KOReader gọi vẫn dùng glibc của máy. `sdcv` (từ điển) được bọc cùng cách.
- **Không dùng SDL.** Bản arm64 mới của KOReader dùng SDL3, cần backend video mà firmware không chắc có. Ritder dùng thẳng `/dev/fb0` (driver `framebuffer_linux` của KOReader) nhưng **có double buffering**: KOReader vẽ vào bộ đệm RAM, mỗi lệnh refresh chép vùng của nó lên màn hình và đổi thứ tự màu RGB sang BGR của Brick trong lúc chép, nên LCD chỉ hiện khung hình đã vẽ xong (KOReader viết cho e-ink, vốn vẽ thẳng lên màn).
- **Nút bấm đọc thẳng từ evdev** (`input_evdev.lua`): D-pad (trục HAT) thành phím mũi tên, L2/R2 (trục analog) thành nút, bỏ mọi sự kiện khác để phần cảm ứng của KOReader không nhận nhầm.
- **Không đụng gì tới e-ink.** Thiết bị mới kế thừa `device/generic`, khai báo `hasEinkScreen = no`, `canHWDither = no`, `isTouchDevice = no`, `hasDPad = yes`, `useDPadAsActionKeys = yes`. Không driver mxcfb/sunxi nào được nạp.
- **MuPDF store 32 MB** (upstream 8 MB) để lật qua lật lại đỡ phải giải mã lại. Trang kế tiếp đã được KOReader dựng sẵn khi rảnh (hinting, `DHINTCOUNT = 1`), bộ nhớ đệm trang lấy 40% RAM trống.
- **CBR chạy được**: MuPDF của KOReader được build kèm libarchive (có RAR), khác với giả định ban đầu trong ghi chú nghiên cứu.
- **App không tự thay file của chính nó khi cập nhật.** Nó chỉ giải nén bản mới ra `userdata/update/staging/`; `install.sh` (do `launch.sh` gọi lúc app chưa chạy) mới đổi tên các file vào chỗ. Trên thẻ FAT/exFAT, thay một file đang chạy có thể treo vô hạn.
- **Vá upstream tối thiểu, có kiểm tra**: chỉ 3 chỗ (chọn thiết bị qua `RITDER_DEVICE`, 2 mục menu). Build dừng nếu một chỗ vá không còn khớp khi nâng KOReader.

## Build

Cần Python 3.10+ (Windows, PowerShell):

```powershell
.\build.ps1            # dist\Ritder, dist\Ritder-stock.zip, dist\update\{update.json, ritder-update.tar.gz}
.\build.ps1 -Publish   # và tạo GitHub Release
```

Lần đầu `tools/build.py` tải khoảng 32 MB (KOReader + 3 gói Debian) vào `vendor/cache/`.

Test:

```powershell
pip install lupa
python tests\run_lua_tests.py     # logic Lua: OTA, phím, framebuffer
python tests\run_shell_tests.py   # install.sh (thay file khi cập nhật), chạy trong WSL
```

Kiểm tra giao diện bằng ảnh chụp (xem [docs/CHUP-MAN-HINH-gia-lap.md](docs/CHUP-MAN-HINH-gia-lap.md)):

```powershell
python tools\emulate.py --setup   # một lần
python tools\emulate.py           # ảnh trong dist\emulator\shots
```

Quy trình phát hành đầy đủ: [docs/OTA-co-che-cap-nhat.md](docs/OTA-co-che-cap-nhat.md), mục 5.

## Cần kiểm tra trên máy

Các điểm dưới đây chưa xác nhận được nếu không có máy thật. Nếu có lỗi, `Apps/Ritder/userdata/crash.log` có đủ thông tin (độ phân giải framebuffer, các thiết bị input đã mở, mã phím).

- [x] `/dev/fb0` hiển thị đúng, màu đúng (0.1.0 trên máy thật).
- [x] D-pad, A/B, START hoạt động (0.1.0 trên máy thật). Các nút còn lại: xem mã nút lạ trong `crash.log`.
- [x] Thẻ nhớ cho chạy file.
- [x] Màu: framebuffer là BGR (0.1.1 hiện nền highlight màu hồng cam thay vì xanh). 0.1.2 đổi màu lúc chép lên màn.
- [x] Cập nhật OTA: 0.1.2 treo khi tự thay file đang chạy trên thẻ nhớ. 0.1.3 để `install.sh` thay file lúc app chưa chạy.
- [ ] 0.1.3 trên máy thật: hết nhấp nháy khi chuyển mục, màu xanh đúng, và OTA chạy trọn vẹn.
- [ ] Tốc độ mở PDF/CBZ nặng; có thể tăng `MUPDF_STORE_MB` trong `device.lua` hoặc `DHINTCOUNT`.
- [ ] Wi-Fi và đồng hồ đúng giờ để OTA kiểm tra được chứng chỉ HTTPS.

## Ghi chú

- Ritder dùng mã nguồn KOReader (AGPL-3.0), nên Ritder cũng theo **AGPL-3.0** (xem `LICENSE`). Mã nguồn KOReader tương ứng: tag [v2026.07.1](https://github.com/koreader/koreader/tree/v2026.07.1).
- glibc (LGPL-2.1) và libstdc++ (GPL-3.0 với ngoại lệ runtime) lấy nguyên từ gói Debian bookworm, xem `upstream.json`.
