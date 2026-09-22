# Handoff: App đọc sách cho TrimUI Brick Pro (fork KOReader)

> Tài liệu tổng hợp lại quá trình nghiên cứu & quyết định kỹ thuật trong phiên làm việc này. Mục đích: người đọc sau (kể cả chính bạn vài tuần sau) có thể tiếp tục dự án mà không cần lặp lại phần điều tra source code.

## 1. Mục tiêu dự án

Fork [koreader/koreader](https://github.com/koreader/koreader) + submodule [koreader-base](https://github.com/koreader/koreader-base) để tạo app đọc sách cho **TrimUI Brick Pro**, tối ưu hiệu năng, ưu tiên v1 đọc mượt **PDF** và **CBZ/CBR**.

## 2. Phần cứng mục tiêu

| Thông số | Giá trị |
|---|---|
| CPU | Allwinner A133p, 1.8GHz |
| GPU | PowerVR GE8300, max 660MHz |
| RAM | **1GB** LPDDR3 |
| Màn hình | 3.95" IPS, **1024×768**, 324ppi, full lamination (LCD màu, không phải e-ink) |
| Pin | 5000mAh |
| Input | D-pad, A/B/X/Y, L1/L2/R1/R2, Start/Select — **không có cảm ứng** |
| OS | Linux (firmware gốc TrimUI, hoặc custom: CrossMix / KNULLI / MinUI) |
| Lưu trữ | Thẻ SD |

## 3. Vì sao fork KOReader hợp lý

Phần nặng nhất (decode/render tài liệu) nằm ở lớp C native, đã được cộng đồng tối ưu hơn chục năm — không cần viết lại từ đầu.

```
frontend/           ← Lua/LuaJIT: UI, logic đọc, gesture/key mapping
koreader-base/       ← C/C++ (submodule):
  ├─ MuPDF           ← PDF, XPS, CBZ/CBT
  ├─ CREngine (crengine) ← EPUB, FB2, MOBI, DOC, HTML, TXT, CHM, RTF
  ├─ DjVuLibre       ← DjVu
  └─ k2pdfopt        ← reflow file scan (dựa trên MuPDF + Leptonica)
```

## 4. Vấn đề định dạng: CBR

KOReader **không hỗ trợ tốt CBR** (RAR) vì `unrar` có giấy phép rắc rối, không tích hợp sẵn như MuPDF (xử lý CBZ tự nhiên vì CBZ = zip). Hai hướng cho v1:

- **A.** Tích hợp `libarchive` để đọc RAR trực tiếp.
- **B.** (khuyến nghị v1) Chỉ hỗ trợ chính thức CBZ, yêu cầu convert CBR→CBZ trước khi copy vào thẻ nhớ.

## 5. Chiến lược porting sang Brick Pro

Chưa có target chính thức cho TrimUI trong koreader-base. Gần nhất về kiến trúc: target **SDL2** (`ffi/framebuffer_SDL2_0.lua`, dùng cho Linux desktop/PocketBook) — SDL2 xử lý tốt cả input joystick/button lẫn output.

Cần viết mới:
- **Input mapping**: D-pad/nút bấm → hệ key-event/gesture nội bộ của KOReader.
- **Device object mới** trong `frontend/device/` cho "TrimUI Brick Pro", kế thừa generic Linux/SDL2 device, khai báo cờ: `isTouchDevice = false`, `hasDPad = true`, `hasKeys = true`, `canHWDither = false`, không set eink-flag nào.

> Đây là pattern chuẩn (idiomatic) của KOReader — mỗi model tự khai báo capability qua các hàm như `fb.device:canHWDither()` (xem PR [#1043](https://github.com/koreader/koreader-base/commit/dc65873b7dfc77ee13e3bd4ea73cea832ba75852)), thay vì patch cứng từng chỗ.

## 6. Phát hiện từ nghiên cứu source code

### 6.1 Display pipeline — không có driver eink nào dùng được

| File | Vai trò | Dùng được cho Brick Pro? |
|---|---|---|
| `ffi/framebuffer.lua` | Abstraction chung | Có (base class) |
| `ffi/framebuffer_mxcfb.lua` | Kindle/Kobo, xử lý waveform/dither e-ink (`refresh_zelda()`) | Không |
| `ffi/framebuffer_sunxi.lua` | **Đã kiểm tra kỹ** — chỉ dùng cho Kobo đời dùng chip Allwinner **nhưng vẫn là màn e-ink** (`if self.device:isKobo() then ... else error("unknown device type") end`). "sunxi" ở đây = "chip Allwinner + panel e-ink", không phải "Allwinner nói chung". | **Không** — hard-error nếu không phải Kobo |
| `ffi/framebuffer_SDL2_0.lua` | SDL2, texture-based (`SDL_UpdateTexture` → `SDL_RenderCopy` → `SDL_RenderPresent`) | **Điểm khởi đầu tốt nhất** |
| `ffi/blitbuffer.lua` | Blit + dithering (`dither_o8x8`, ordered dither) | Chỉ kích hoạt khi cờ `dither=true` được truyền — nếu device flag không bật, tự động bypass |

**Kết luận**: không cần "bóc" hay "tắt" code eink nào — driver cho Brick Pro sẽ không kế thừa từ `framebuffer_mxcfb.lua`/`framebuffer_sunxi.lua` nên toàn bộ waveform/dither logic không compile vào app từ đầu.

### 6.2 MuPDF cache — đính chính so với giả thuyết ban đầu

Từ `ffi/mupdf.lua`:
```lua
local mupdf = {
  cache_size = 8*1024*1024,   -- 8 MB — mặc định đã RẤT tiết kiệm
}
```
→ Không cần giảm cho máy 1GB RAM. Ngược lại có thể **tăng lên** (32–64MB) để giảm decode lại khi lật qua lật lại. (Giả thuyết ban đầu trong session — rằng cần giảm cache — là sai, đã đính chính.)

`page_mt.__index:draw_new()` tạo `BlitBuffer` + pixmap mới mỗi lần gọi → đây là điểm hook đúng để prefetch (gọi trước cho trang N+1, lưu kết quả, blit khi cần).

`mupdf.scaleBlitBuffer()` — nên để MuPDF scale (qua `draw_context.zoom`) thay vì render to rồi tự scale bên Lua (chất lượng tốt hơn, đỡ tốn CPU).

### 6.3 Cảnh báo concurrency — quan trọng nhất cho phần prefetch

`fz_new_context_imp(alloc, locks, max_store, version)` trong `mupdf.lua` được gọi với **`locks = nil`**:
```lua
local ctx = M.fz_new_context_imp(
  mupdf.debug_memory and W.mupdf_get_my_alloc_context() or nil,
  nil,   -- locks: KHÔNG được cấu hình
  mupdf.cache_size, FZ_VERSION)
```
→ Context MuPDF hiện tại **không an toàn để render từ nhiều thread cùng lúc**.

Pattern pthread có sẵn trong `page_mt.__index:reflow()` (dùng cho k2pdfopt precache) **không chứng minh ngược lại** — vì `render_for_kopt()` (gọi MuPDF) chạy đồng bộ *trước*, thread chỉ xử lý hậu kỳ trên bitmap thô đã render xong, không đụng lại vào `fz_context` dùng chung.

**Hai lựa chọn cho prefetch trang N+1:**

| Cách | Ưu điểm | Nhược điểm |
|---|---|---|
| A. `fz_locks_context` + `fz_clone_context()` | Chuẩn upstream MuPDF, share cache giữa thread | Phải tự viết lock callback bằng C, sửa vào chỗ tạo context |
| **B. Fork tiến trình con + IPC qua `tmpfs`** (khuyến nghị v1) | Đơn giản, không đụng core MuPDF context, tránh hoàn toàn race condition | Overhead copy qua shared memory/file |

## 7. Roadmap đề xuất cho v1

1. Fork + dọn dẹp source (loại code platform Kindle/Kobo/Cervantes/reMarkable không cần)
2. Không cần "tắt" eink pipeline — chỉ đơn giản không kế thừa từ nó khi viết device mới
3. Viết platform target mới cho TrimUI (dựa theo SDL2 target làm khung: input mapping + output)
4. Giữ nguyên MuPDF + CRE, chỉ tune `cache_size` (có thể tăng, không cần giảm)
5. Thêm prefetch trang qua **fork process + tmpfs handoff** (phương án B ở mục 6.3)
6. Quyết định hướng CBR (mục 4) — khuyến nghị v1 chỉ CBZ
7. Benchmark PDF/CBZ nặng trên máy thật, tinh chỉnh dựa trên số đo thực tế, không đoán

## 8. Việc còn mở / cần quyết định tiếp

- [ ] Đọc kỹ hơn code decode ảnh CBZ (libjpeg-turbo path) để xác nhận NEON có được tận dụng trên A133p không
- [ ] Xác định BSP/kernel của TrimUI có expose `/dev/ion` không (ảnh hưởng cách viết framebuffer driver)
- [ ] Thiết kế cụ thể luồng code cho phương án B (fork + tmpfs) áp dụng vào `draw_new()`
- [ ] Xác nhận SDL2 build cho A133p có driver renderer tăng tốc (OpenGL ES qua PowerVR) hay chỉ software fallback

## 9. Nguồn tham khảo chính

- Repo gốc: https://github.com/koreader/koreader
- Base framework: https://github.com/koreader/koreader-base
- `ffi/framebuffer.lua`: https://github.com/koreader/koreader-base/blob/master/ffi/framebuffer.lua
- `ffi/framebuffer_sunxi.lua` (đã xác nhận chỉ cho Kobo eink): https://github.com/NiLuJe/koreader-base/blob/b8089573dd4656d326cbb62d3f230c41a8bb75d0/ffi/framebuffer_sunxi.lua
- `ffi/mupdf.lua`: https://github.com/koreader/koreader-base/blob/master/ffi/mupdf.lua
- Device capability pattern (PR #1043): https://github.com/koreader/koreader-base/commit/dc65873b7dfc77ee13e3bd4ea73cea832ba75852
- Building/Porting docs: https://github.com/koreader/koreader/blob/master/doc/Building.md , https://github.com/koreader/koreader/blob/master/doc/Porting.md

---

## 10. Trạng thái sau Ritder 0.1.0 (22/09/2026)

Những gì thực tế khác với kế hoạch ở trên, khi bắt tay làm:

- **Không fork toàn bộ source, không biên dịch lại.** Ritder = bản build chính thức `koreader-linux-arm64` (v2026.07.1, ghim SHA-256 trong `upstream.json`) + lớp chồng Lua trong `overlay/`. Build trên Windows chỉ cần Python.
- **KOReader arm64 cần glibc ≥ 2.35**, firmware TrimUI (toolchain GCC 8.3) cũ hơn → app mang theo glibc 2.36 + libstdc++ (Debian bookworm) trong `sys/`, chạy qua `ld-linux-aarch64.so.1 --library-path`.
- **Target SDL không dùng được như dự tính:** KOReader đã chuyển sang SDL3 (bundled), cần backend video mà firmware không chắc có. Thay vào đó: `framebuffer_linux` (fbdev `/dev/fb0`) + backend input evdev viết bằng FFI (`frontend/device/trimui/`). Đúng tinh thần mục 5–6.1: thiết bị mới kế thừa `device/generic`, không nạp driver e-ink nào.
- **CBR (mục 4) đã chạy sẵn:** `libwrap-mupdf.so` được link với libarchive, và `pdfdocument.lua` đăng ký `cbr`.
- **MuPDF store (mục 6.2):** tăng lên 32 MB trong `device.lua`.
- **Prefetch trang (mục 6.3):** chưa làm phương án fork + tmpfs. KOReader đã tự dựng trước trang kế tiếp khi rảnh (hinting, `DHINTCOUNT = 1`) trên cùng context MuPDF nên không có vấn đề thread. Chỉ làm phương án B nếu đo trên máy thật thấy chậm.
- **OTA:** theo thiết kế của Spoty, xem `docs/OTA-co-che-cap-nhat.md`.

Các việc còn mở ở mục 8 vẫn còn nguyên (NEON trong libjpeg-turbo, `/dev/ion`, GPU), cộng thêm danh sách "Cần kiểm tra trên máy" trong `README.md`.
