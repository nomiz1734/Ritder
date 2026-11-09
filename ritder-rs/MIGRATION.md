# MIGRATION — Ritder 0.1.6 → Rust (ritder-rs)

Ngày thực hiện: 2026-11-05. Nguồn: `../original/` (https://github.com/nomiz1734/Ritder, v0.1.6, dựa trên KOReader v2026.07.1), giữ nguyên không đụng vào để đối chứng.

## Phạm vi — nói thẳng

- **Trong phạm vi:** mọi code do Ritder tự viết trong repo: Lua overlay + plugin (~2.857 dòng), Python tools (866 dòng), Shell (235 dòng), Rust launcher sẵn có (193 dòng), và các test Lua/Shell của chúng.
- **Ngoài phạm vi:** KOReader upstream. Repo Ritder **không chứa** mã nguồn KOReader (C/Lua khổng lồ) — nó chỉ tải bản build chính thức của KOReader lúc đóng gói (ghim trong `upstream.json`). Vì vậy bản migration này **không** nhận là đã migrate KOReader.
- Các file Lua overlay vốn là điểm móc vào LuaJIT/widget của KOReader: **toàn bộ logic thuần** của chúng đã port sang `ritder-core`. Phần monkey-patch widget / vòng lặp sự kiện của KOReader không có runtime tương ứng trong Rust — khi KOReader vẫn là engine đọc sách, lớp móc đó vẫn phải sống ở phía KOReader; bản Rust cung cấp đầy đủ logic quyết định (bảng quyết định, hằng số, state machine) và các binary điều khiển vòng đời/giao dịch file.

## Các phase

| Phase | Nội dung | Trạng thái |
|---|---|---|
| 0 | Audit repo gốc, đếm dòng, phân loại code Ritder tự viết vs upstream | ✅ Hoàn thành (trước khi bắt đầu; kết quả ở mục Phạm vi) |
| 1 | Mapping từng file gốc → module Rust, chọn dependency | ✅ Hoàn thành (bảng Mapping dưới đây) |
| 2 | `ritder-core`: OTA, night pages, framebuffer, evdev, event_map, diagnostics, brand, ui_theme, powerd, device, plugin, install, logging, buildtools, icon, emulate_plan | ✅ Hoàn thành |
| 3 | `ritder-launcher` (giữ + mở rộng bản Rust gốc, hấp thụ launch/logging/install.sh) + `ritder-tools` (build / make-update / publish-release / make-icon / emulate) | ✅ Hoàn thành |
| 4 | Port test Lua/Shell → Rust tests; `cargo test` pass 39/39 | ✅ Hoàn thành |
| 5 | `cargo build --release` pass; cross-build `aarch64-unknown-linux-musl` cho launcher pass; đóng gói `ritder-rs.zip` | ✅ Hoàn thành |

## Lựa chọn dependency (đã kiểm chứng crates.io tải được trên máy này)

- Dùng: `serde`, `serde_json` (manifest/upstream/build-info), `sha2` (SHA-256), `flate2` + `tar` (tar.gz OTA thật), `zip` (deflate) cho Ritder-stock.zip.
- Tự viết thay vì thêm crate: PNG encoder tối thiểu + CRC32 (`icon.rs`, zlib qua flate2), parser .deb/ar (`buildtools.rs`), version compare, JSON build-info. Không dùng regex crate: PROTECTED patterns được cài đặt trực tiếp.
- Tải mạng trong `ritder-tools build/publish-release` gọi `curl` hệ thống (giống cách bản gốc dùng urllib/git credential); giải nén `.tar.xz` gọi `tar` hệ thống. Đây là phần host-dependent, xem mục Chưa kiểm chứng.

## Bảng mapping từng file gốc → Rust

| File gốc | Dòng | Module / đích Rust |
|---|---|---|
| `overlay/frontend/ritder/update.lua` | 642 | `ritder-core/src/update.rs` (version, safe/protected path, manifest, ELF ARM64, unpack tar.gz, stage, status/pending/ready/failed/discard/confirm) |
| `overlay/frontend/ritder/ui_theme.lua` | 397 | `ritder-core/src/ui_theme.rs` (màu focus/cursor, tint vs night mode, chuyển tab bỏ tab action, focus-row sau update, điều kiện repaint từng phần, focus nút OK của ConfirmBox) |
| `overlay/frontend/ritder/diagnostics.lua` | 165 | `ritder-core/src/diagnostics.rs` (TAILS, tail 256KB/giới hạn dòng, device report, collect, takeCrashCode) |
| `overlay/frontend/ritder/night_pages.lua` | 69 | `ritder-core/src/night_pages.rs` (isKept, bảng quyết định Paged/Reflowable/None, set 2 khóa) |
| `overlay/frontend/ritder/brand.lua` | 43 | `ritder-core/src/brand.rs` (rebrand KOReader→Ritder, giữ nguyên chữ thường) |
| `overlay/frontend/device/trimui/input_evdev.lua` | 344 | `ritder-core/src/input_evdev.rs` (HAT→phím, trigger analog→nút + ngưỡng giữa dải, software repeat 0.40s/0.10s, bỏ EV_SYN/MSC, log phím chưa map) |
| `overlay/frontend/device/trimui/emulator.lua` | 141 | `ritder-core/src/event_map.rs` (`events_for`) + `emulate_plan.rs` (hằng số delay, env) |
| `overlay/frontend/device/trimui/framebuffer.lua` | 110 | `ritder-core/src/framebuffer.rs` (`swap_rb_word`, `copy_to_screen`, bounded rect, double-buffer model) |
| `overlay/frontend/device/trimui/device.lua` | 108 | `ritder-core/src/device.rs` (capabilities Brick Pro 1024×768, DPI 324, MuPDF store 32MB) |
| `overlay/frontend/device/trimui/powerd.lua` | 56 | `ritder-core/src/powerd.rs` (quét /sys/class/power_supply tìm Battery, capacity/charging/full) |
| `overlay/frontend/device/trimui/emu_framebuffer.lua` | 53 | `ritder-core/src/framebuffer.rs` (`EmuFramebuffer`, refreshed_pixels, cỡ từ RITDER_EMU_W/H) |
| `overlay/frontend/device/trimui/event_map.lua` | 23 | `ritder-core/src/event_map.rs` (bảng mặc định 14 phím; 316 MENU cố ý không map; gộp bản đồ người dùng) |
| `overlay/plugins/ritderupdate.koplugin/main.lua` | 444 | `ritder-core/src/plugin.rs` (hằng số AUTO_CHECK 8s / CONFIRM 10s / POLL 0.5s / STALLED 180s / exit 42, trimNotes 6 dòng, formatMB) + vòng đời OTA ở `update.rs`/`install.rs` |
| `overlay/plugins/ritderupdate.koplugin/ritderinfo.lua` | 150 | `ritder-core/src/plugin.rs` (GUIDE_SECTIONS, version_text, REPO) + `diagnostics.rs` (collectLogs) |
| `overlay/plugins/ritderupdate.koplugin/progressdialog.lua` | 106 | `ritder-core/src/plugin.rs` (`progress_state`, `dialog_width` = 70% màn hình) |
| `overlay/plugins/ritderupdate.koplugin/_meta.lua` | 6 | `ritder-core/src/plugin.rs` (PLUGIN_NAME/FULLNAME/DESCRIPTION) |
| `tools/build.py` | 329 | `ritder-tools` subcommand `build` + `ritder-core/src/buildtools.rs` (EXECUTABLE, 5 PATCHES kiểm anchor & FAIL khi lệch, deb_data, lua_string/build_info, to_lf, sdcv wrapper, koreader_rel) |
| `tools/emulate.py` | 275 | `ritder-tools` subcommand `emulate` + `ritder-core/src/emulate_plan.rs` (parse steps key/keys/wait/shot/open/lua, RunPlan, emu_env, wsl_path) |
| `tools/publish_release.py` | 110 | `ritder-tools` subcommand `publish-release` (kiểm version khớp, đủ 3 assets, **dry-run mặc định**, --execute + GH_TOKEN mới gọi GitHub API) |
| `tools/make_icon.py` | 88 | `ritder-tools` subcommand `make-icon` + `ritder-core/src/icon.rs` (bảng màu, tile/launcher 300×300 tile 184 ở (58,58), logo 256, SVG, PNG encoder tự viết; vẽ đơn giản hoá: không supersampling 4×, trang vẽ dạng khối thay cho polygon xiên — xem Chưa kiểm chứng) |
| `tools/make_update.py` | 64 | `ritder-tools` subcommand `make-update` + `buildtools::ota_included` (bỏ userdata/, settings.json; mode 755/644; update.json có sha256+size) |
| `package/stock/install.sh` | 82 | `ritder-core/src/install.rs` (`install_staged`, `restore_backup`, `safe_relative`, chống symlink/special file) |
| `package/stock/launch.sh` | 102 | `crates/ritder-launcher/src/main.rs` (vòng đời: khôi phục khi `installing` còn dở → cài staged → chạy reader qua loader; lặp khi exit 42/85; rollback + `rolled_back` khi pending mà thoát lỗi) |
| `package/stock/logging.sh` | 51 | `ritder-core/src/logging.rs` (rotate crash.log→.1, ritder.log giữ 800 dòng, session start/end, file `crashed` + 40 dòng cuối) + gọi từ launcher |
| `rust/ritder-launcher/src/main.rs` | 193 | `crates/ritder-launcher/src/main.rs` — **giữ nguyên hành vi** (exit 42/85, backup/rollback, pending/rolled_back, test gốc `rejects_escape_paths`/`accepts_nested_paths` giữ tên); mở rộng: nhận cả 6 tham số vị trí như launch.sh gọi lẫn dạng cờ, ghi log phiên qua `logging.rs` |
| `tools/build_native.ps1`, `build.ps1` | — | Thay bằng Cargo: `cargo build --release` và cross-build aarch64 (`.cargo/config.toml` đặt linker `rust-lld`, tương đương build_native.ps1) |
| `tests/lua/test_update.lua` (287), `test_night_pages.lua` (120), `test_input_evdev.lua` (73), `test_diagnostics.lua` (57), `test_framebuffer.lua` (54), `tests/shell/test_install.sh` (116) | 707 | `crates/ritder-core/tests/ported_tests.rs` — 21 integration test, tên dạng `update__version_compare`, `install__rollback_on_failure`, … + 15 unit test trong các module + 3 test của launcher |
| `tests/run_lua_tests.py`, `tests/run_shell_tests.py` | — | Thay bằng `cargo test` (không còn runner Python) |
| `tests/screens/*.lua` (13 file) | — | Dữ liệu kịch bản đầu vào cho `ritder-tools emulate` (parser ở `emulate_plan.rs`); không sao chép vào cây ritder-rs vì chúng là dữ liệu test của repo gốc |
| `package/stock/defaults/settings.reader.lua` | — | File dữ liệu cài đặt của KOReader (Lua data cho runtime KOReader), không phải logic Ritder; bản Rust ghi `build_info.json` dạng dữ liệu tương đương. Không port vì nó là cấu hình nạp bởi KOReader, xem ngoại lệ dữ liệu bên dưới |

## Ngoại lệ dữ liệu thuần (không phải code, được giữ dạng dữ liệu)

Trong cây `ritder-rs` **không có** file `.lua` / `.py` / `.sh` / `.ps1` nào. Chỉ có:

- `assets/config.json` — config Stock OS (label/icon/launch) chép nguyên từ `package/stock/config.json`.
- `assets/upstream.json` — ghim upstream + SHA-256, chép nguyên từ gốc.
- `VERSION`, `LICENSE` — dữ liệu văn bản.
- Nội dung sinh ra lúc build: `build_info.json`, `update.json`, icon PNG/SVG.

## Cách build

```bash
export PATH=$HOME/.cargo/bin:$PATH   # rustup stable minimal cài ở ~/.cargo
cd ritder-rs
cargo build --release     # binary: target/release/ritder-launcher, target/release/ritder-tools
cargo test                # 39 test
# Cross cho Brick Pro (đã kiểm chứng trên máy này):
rustup target add aarch64-unknown-linux-musl
cargo build --release --target aarch64-unknown-linux-musl -p ritder-launcher
# -> ELF 64-bit ARM aarch64, statically linked (kiểm bằng chính is_arm64_elf của ritder-core)
```

Dùng thử tools:

```bash
target/release/ritder-tools make-update <dist/Ritder> <out> <version> [notes]
target/release/ritder-tools make-icon --root <root>
target/release/ritder-tools emulate --scripts <tests/screens>   # in kế hoạch từng kịch bản
target/release/ritder-tools publish-release --root <root>        # dry-run mặc định
target/release/ritder-tools build --root <repo> [--out <dist>]   # cần mạng + curl + tar/xz
```

## Kết quả kiểm chứng trên máy này (bằng chứng thật)

- `cargo test`: **39 passed; 0 failed** (15 unit ritder-core + 21 integration ported_tests + 3 launcher).
- `cargo build --release`: `Finished release profile [optimized]` — binary x86_64: `ritder-tools` 1.326.800 byte, `ritder-launcher` 669.208 byte.
- Cross aarch64: `ritder-launcher` 815.968 byte, `ELF 64-bit LSB executable, ARM aarch64, statically linked`; hàm kiểm ELF của chính ritder-core xác nhận e_machine 0xB7.
- Smoke test thật: `make-update` sinh tar.gz đúng 2 file (đã loại userdata/) + update.json có sha256/size khớp; `make-icon` sinh PNG 300×300 chữ ký PNG hợp lệ + SVG; `emulate` phân tích đủ 13/13 kịch bản gốc (số bước/ảnh từng file in ra được).
- Một khác biệt chủ động ghi lại: `parse_version("v0.10.0-rc1")` cho `{0,10,0,1}` theo **docstring** của update.lua (lấy cụm số đầu tiên trong phần, `rc1` → 1); cách đọc nghiêm ngặt mã Lua gốc (`^%d+` neo đầu) sẽ cho 0 ở phần đó. Chọn theo tài liệu vì đó là hành vi được mô tả cho người dùng OTA.

## CHƯA kiểm chứng được trên máy này (host/device-dependent)

- **Brick Pro thật:** /dev/fb0 thật, evdev thật, /sys pin thật, thẻ FAT/exFAT, Stock OS — launcher aarch64 đã build được nhưng chưa chạy trên máy thật.
- **KOReader runtime:** lớp móc widget (ui_theme/plugin UI) chỉ port logic; chưa chạy cùng KOReader thật/giả lập.
- **WSL emulate:** `emulate` mới sinh kế hoạch + env; việc chạy KOReader x86_64 trong WSL1 distro `RitderEmu` và chụp PNG cần máy Windows.
- **GitHub Release thật:** `publish-release` mặc định dry-run; đường `--execute` (GH_TOKEN + API) chưa chạy thật.
- **build trọn gói:** `ritder-tools build` cần tải ~32MB upstream + tar có xz; chưa chạy end-to-end trên máy này (từng bước — fetch kiểm SHA-256, deb parser, patch anchor, zip — đã có unit test/smoke riêng).
- **Icon:** hình học đơn giản hoá so với PIL (không supersampling, trang không xiên sag) — màu/kích thước/tỉ lệ đúng, chi tiết pixel chưa đối chiếu với bản gốc.
