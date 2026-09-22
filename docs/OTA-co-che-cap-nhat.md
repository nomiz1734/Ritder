# Cơ chế cập nhật OTA của Ritder

*Viết ngày 22/09/2026, theo code bản 0.1.0. Các file được nhắc tới: `overlay/frontend/ritder/update.lua`, `overlay/plugins/ritderupdate.koplugin/main.lua`, `package/stock/launch.sh`, `tools/build.py`, `tools/make_update.py`, `tools/publish_release.py`, `build.ps1`.*

Cơ chế này làm theo thiết kế OTA của Spoty (cùng máy TrimUI Brick Pro, cùng GitHub Releases), có thay đổi ở những chỗ Ritder khác Spoty: app là KOReader (Lua + nhiều thư viện) chứ không phải một file chạy duy nhất, nên **mọi file bị thay đều được sao lưu**, không riêng file chạy chính.

## 1. Tóm tắt

Ritder tự cập nhật qua mạng từ **GitHub Releases** của repo `nomiz1734/Ritder`. Không cần máy chủ riêng.

1. Mỗi bản phát hành trên GitHub có 3 file: `update.json` (bảng kê), `ritder-update.tar.gz` (gói cập nhật) và `Ritder-stock.zip` (gói cài lần đầu).
2. Máy đọc `https://github.com/nomiz1734/Ritder/releases/latest/download/update.json`. GitHub luôn trỏ đường dẫn `latest` này về bản mới nhất.
3. Nếu phiên bản trong `update.json` mới hơn bản đang chạy, app báo có cập nhật.
4. Người dùng bấm cập nhật: app tải gói **trong một tiến trình con** (vẫn đọc sách được), kiểm tra SHA-256, giải nén, chép đè lên thư mục app (giữ nguyên `userdata/`), sao lưu mọi file bị thay, rồi khởi động lại.
5. Nếu bản mới bị lỗi ngay khi khởi động, `launch.sh` trả lại toàn bộ file cũ.

```
 PC (build.ps1 -Publish)                 GitHub Release v0.1.0              TrimUI Brick Pro
 ───────────────────────                 ─────────────────────              ────────────────
 tools/build.py ────────────┐
 (KOReader + glibc + overlay)│
 make_update.py ─────────────┼──► update.json ─────────────► 1. kiểm tra phiên bản
                             │    ritder-update.tar.gz ────► 2. tải + so SHA-256 (tiến trình con)
                             └──► Ritder-stock.zip           3. giải nén, sao lưu file cũ, chép đè
                                  (cài lần đầu)              4. thoát mã 42 → launch.sh chạy lại
                                                             5. chạy ổn 10 giây → xác nhận
                                                                lỗi trước đó → trả lại file cũ
```

---

## 2. Bảng kê `update.json`

Do `tools/make_update.py` tạo ra khi build:

```json
{
  "version": "0.1.0",
  "notes": "• Dòng ghi chú 1\n• Dòng ghi chú 2",
  "file": "ritder-update.tar.gz",
  "sha256": "…64 ký tự hex…",
  "size": 44017570
}
```

| Trường | Bắt buộc | Ý nghĩa |
|---|---|---|
| `version` | có | Phiên bản của gói. So với phiên bản đang chạy để quyết định có cập nhật hay không |
| `sha256` | có | Mã băm của gói (64 ký tự hex). Tải về mà lệch là bị từ chối |
| `notes` | không | Ghi chú hiện trong hộp thoại cập nhật trên máy (tối đa 6 dòng). Lấy từ `release-notes.txt` |
| `file` | một trong hai | Tên gói, tính **tương đối** theo địa chỉ của `update.json` |
| `url` | một trong hai | Địa chỉ tuyệt đối của gói (dùng thay cho `file`), phải là HTTPS |
| `size` | không | Kích thước gói: dùng cho thanh tiến trình, và tải về mà lệch kích thước là bị từ chối |

**So sánh phiên bản** (`Update.isNewer`): bỏ chữ `v` ở đầu, tách theo `.`, `-`, `+` rồi so từng số. Ví dụ `0.10.0` mới hơn `0.9.9`. **Chỉ bản mới hơn mới được đề nghị**, không bao giờ tự hạ cấp.

Phiên bản của app nằm ở file `VERSION` trong repo. `tools/build.py` ghi nó (cùng địa chỉ OTA và phiên bản KOReader) vào `frontend/ritder/build_info.lua` trong gói.

---

## 3. Gói cập nhật `ritder-update.tar.gz`

Là thư mục `dist/Ritder` nén lại (khoảng 44 MB), **bỏ ra** thư mục `userdata/`:

```
launch.sh             ← script khởi chạy (quyền 755)
config.json, icon.png ← khai báo app cho Stock OS
luajit, reader.lua    ← KOReader (luajit là file chạy ARM64)
sys/                  ← glibc 2.36 + libstdc++ đi kèm (ld-linux-aarch64.so.1 quyền 755)
libs/, common/, ffi/  ← thư viện C và Lua của KOReader
frontend/, plugins/   ← giao diện KOReader + phần của Ritder
data/, fonts/, l10n/  ← tài nguyên (CSS, từ điển gạch nối, font, bản dịch)
defaults/             ← cài đặt cho lần chạy đầu
```

`Ritder-stock.zip` chứa đúng những file đó, trong thư mục `Ritder/`, dùng để **cài lần đầu** hoặc **cài tay** khi OTA lỗi: giải nén rồi chép đè vào `Apps/Ritder` trên thẻ nhớ.

---

## 4. Trên máy: từ lúc kiểm tra tới lúc chạy bản mới

### 4.1 Địa chỉ kiểm tra và tùy chọn

- Mặc định được **gắn sẵn lúc build** từ `update-url.txt` (hoặc `.\build.ps1 -UpdateUrl <url>`).
- Ghi đè bằng khóa `ritder_update_url` trong `userdata/settings.reader.lua`. Đặt thành `""` là tắt hẳn OTA.
- `ritder_auto_update_check` (mặc định bật): bật/tắt trong **MENU → Kiểm tra cập nhật → Tự kiểm tra khi mở app**.

### 4.2 Kiểm tra

| Khi nào | Điều kiện | Kết quả |
|---|---|---|
| **8 giây sau khi mở app** (tự động) | `ritder_auto_update_check` bật và có địa chỉ | Có bản mới thì hiện thông báo nhỏ "Có bản cập nhật X — xem trong MENU". Lỗi mạng thì chỉ ghi log, không làm phiền |
| **MENU → Kiểm tra cập nhật** (bấm tay) | có địa chỉ | Mở hộp thoại: *Đang kiểm tra* → *Bạn đang dùng bản mới nhất* / *Có phiên bản mới* / *Không cập nhật được* + lý do |

Cả hai đều chạy trong tiến trình con (`ffiutil.runInSubProcess`), giao diện không bị đơ kể cả khi mạng chậm. Có bản mới thì mục trong MENU đổi thành **"Cập nhật lên phiên bản X"**.

### 4.3 Các trạng thái của hộp thoại

```
Checking ──► UpToDate
    │
    └──► Available ──A──► Downloading ──► Installing ──► Ready ──A──► khởi động lại
                              │                │
                              └──── Failed ◄───┘   (A = thử lại)
```

| Trạng thái | Màn hình | Nút |
|---|---|---|
| `Checking` | "Đang kiểm tra bản cập nhật…" | B hủy |
| `UpToDate` | "Bạn đang dùng bản mới nhất (0.1.0)." | A / B đóng |
| `Available` | Phiên bản mới, bản đang dùng, dung lượng, ghi chú (tối đa 6 dòng) | **A Cập nhật ngay**, B Để sau |
| `Downloading` | Thanh tiến trình, "% • x / y MB" | B chạy nền (vẫn đọc sách được; MENU → "Xem tiến trình tải" để mở lại) |
| `Installing` | "Đang cài đặt…" | — |
| `Ready` | "Đã cài xong phiên bản X" | **A Khởi động lại**, B Để sau |
| `Failed` | "Không cập nhật được" + lý do | **A Thử lại**, B đóng |

Tiến trình con ghi trạng thái vào `userdata/update/status`; giao diện đọc file đó và kích thước file đang tải mỗi 0,5 giây.

### 4.4 Tải gói

`Update.download`:
1. Tải qua **HTTPS**, tự đi theo chuyển hướng (link `releases/latest/download/…` của GitHub luôn chuyển hướng sang máy chủ file), tối đa 8 lần. **Mỗi bước chuyển hướng cũng phải là HTTPS**; mỗi bước ghi lại file từ đầu nên nội dung trang chuyển hướng không lẫn vào gói.
2. Kiểm tra chứng chỉ máy chủ theo `data/ca-bundle.crt` có sẵn trong KOReader. Nếu lỗi chứng chỉ mà đồng hồ máy đang ở trước năm 2026, báo rõ là *đồng hồ của máy đang sai* thay vì lỗi mạng chung chung.
3. Ghi ra `userdata/update/package.tar.gz`.
4. Tải xong, so kích thước (nếu có `size`) và SHA-256 (qua libcrypto của KOReader) với `update.json`. **Lệch thì xóa file** và báo *"file tải về bị hỏng (sai SHA-256)"*.

### 4.5 Cài đặt

`Update.install` chạy luôn trong tiến trình con đó:

1. Giải nén vào `userdata/update/staging/` bằng libarchive. **Từ chối** mọi đường dẫn tuyệt đối hoặc có `..`, và mọi mục không phải file/thư mục thường (symlink, thiết bị…).
2. Gói phải có `launch.sh`, `reader.lua`, `luajit`, và **`luajit` phải là chương trình Linux ARM64** (bắt đầu bằng `\x7fELF`, 64-bit, mã kiến trúc `0xB7`). Sai thì dừng, báo *"gói cập nhật không đúng kiến trúc ARM64"*, thư mục app không bị đụng tới.
3. Ghi dấu `userdata/update/installing` (đang chép dở).
4. Chép từng file từ `staging/` vào thư mục app:
   - **Bỏ qua** mọi thứ trong `userdata/`: cài đặt, lịch sử đọc, vị trí đang đọc, bookmark, cache đều được giữ nguyên.
   - File cũ bị thay được **chuyển vào `userdata/update/backup/`** (giữ nguyên đường dẫn), file mới hoàn toàn được ghi tên vào `userdata/update/added.txt`.
   - Đổi tên trước, nếu thẻ FAT/exFAT không cho đổi tên đè thì chép rồi xóa.
   - Lỗi giữa chừng: trả ngay file cũ từ `backup/` và báo lỗi.
5. Ghi phiên bản mới vào `userdata/update/pending` (dấu "đang chờ xác nhận"), xóa `installing`, `staging/` và `package.tar.gz`.

File có trong bản cũ nhưng không còn trong bản mới được để nguyên (không ảnh hưởng gì, KOReader không nạp file thừa).

### 4.6 Khởi động lại và quay về bản cũ

Bấm **A Khởi động lại** → app đóng sách đúng cách (lưu vị trí đọc) rồi thoát với **mã 42**. Khi đó `launch.sh` (rút gọn):

```sh
if [ -f "$UPD/installing" ]; then restore_backup; fi   # lần cài trước bị cắt ngang (mất điện…)

while true; do
    "$LOADER" --library-path "$LIBPATH" luajit reader.lua
    code=$?
    if [ "$code" -eq 42 ]; then                          # vừa cập nhật xong
        export RITDER_RESTARTED=1
        exec /bin/sh "$progdir/launch.sh"                # chạy lại bằng launch.sh MỚI
    fi
    [ "$code" -eq 85 ] && continue                       # "khởi động lại" của KOReader
    if [ "$code" -ne 0 ] && [ -f "$UPD/pending" ] && [ -d "$UPD/backup" ]; then
        restore_backup                                   # bản mới lỗi trước khi xác nhận:
        echo "$version" > "$UPD/rolled_back"             # trả lại mọi file cũ, ghi update.log
        exec /bin/sh "$progdir/launch.sh"                # chạy lại bằng launch.sh CŨ
    fi
    break
done
```

`restore_backup` xóa các file có tên trong `added.txt`, chuyển mọi file trong `backup/` về chỗ cũ, rồi xóa `backup/`, `added.txt`, `pending`, `installing`.

- `exec launch.sh` giúp **chính `launch.sh` cũng được cập nhật** (hoặc được trả về bản cũ khi quay lại).
- `RITDER_RESTARTED=1` để lần chạy lại không làm lại các việc chỉ cần làm lúc mở app (đặt chế độ CPU, tạo cài đặt lần đầu).
- Bản mới mở lên: plugin thấy file `pending` → hiện **"Đã cập nhật lên phiên bản X"**.
- **Chạy ổn 10 giây** → plugin xóa `pending` và `backup/`, tức là xác nhận bản mới tốt.
- Nếu bản mới **thoát bằng lỗi trước 10 giây đó** → `launch.sh` trả lại file cũ, ghi lý do và 40 dòng cuối của `crash.log` vào `userdata/update.log`, chạy lại bản cũ. Bản cũ mở lên thì báo *"Bản cập nhật X bị lỗi khi khởi động nên Ritder đã quay về bản Y"*.

### 4.7 Các file trên thẻ nhớ liên quan tới OTA

| Đường dẫn (trong `Apps/Ritder/`) | Là gì |
|---|---|
| `userdata/update/package.tar.gz` | Gói đang tải (xóa sau khi cài) |
| `userdata/update/staging/` | Nơi giải nén tạm (xóa sau khi cài) |
| `userdata/update/backup/` | Các file bị thay trong lần cập nhật gần nhất (xóa khi bản mới được xác nhận) |
| `userdata/update/added.txt` | Các file lần cập nhật gần nhất thêm mới |
| `userdata/update/installing` | Có mặt = đang chép dở; lần mở sau sẽ tự trả lại file cũ |
| `userdata/update/pending` | Có mặt = bản mới chưa được xác nhận chạy ổn |
| `userdata/update/rolled_back` | Có mặt = vừa quay về bản cũ, lần mở tới sẽ báo cho người dùng |
| `userdata/update/status` | Trạng thái tiến trình tải/cài, cho giao diện đọc |
| `userdata/update.log` | Lịch sử các lần quay về bản cũ / cài dở |
| `userdata/crash.log` | Toàn bộ log của lần chạy gần nhất (có các dòng `Ritder update …`) |
| `userdata/launch.log` | Bản sao `crash.log` khi app thoát bằng lỗi |

---

## 5. Trên PC: phát hành một bản mới

### 5.1 Các bước

1. Sửa code (trong `overlay/`, `package/`, `tools/`).
2. Tăng phiên bản trong file `VERSION`, ví dụ `0.1.0` → `0.1.1`.
3. Viết `release-notes.txt`: mỗi dòng một ý, bắt đầu bằng `•`.
4. Build và đóng gói:
   ```powershell
   .\build.ps1
   ```
   Kết quả nằm trong `dist\`:
   - `dist\Ritder\`: thư mục app,
   - `dist\Ritder-stock.zip`,
   - `dist\update\update.json` và `dist\update\ritder-update.tar.gz`.
5. Chạy test: `python tests\run_lua_tests.py` (cần `pip install lupa`).
6. Commit và `git push` lên `main`. **Phải push trước**, vì bản phát hành được gắn vào commit mới nhất của `main`.
7. Phát hành:
   ```powershell
   $env:GCM_INTERACTIVE = "never"
   python tools\publish_release.py      # hoặc gộp 4 + 7: .\build.ps1 -Publish
   ```
   Script sẽ:
   - lấy đăng nhập GitHub đã lưu trong Git Credential Manager (hỏi đúng tài khoản `nomiz1734`, tránh cửa sổ chọn tài khoản),
   - kiểm tra phiên bản trong `dist\update\update.json` khớp `VERSION`,
   - tạo release `v<version>`, đánh dấu **latest**, tải lên 3 file.
8. Kiểm tra lại:
   ```bash
   curl -sL https://github.com/nomiz1734/Ritder/releases/latest/download/update.json
   curl -sL https://github.com/nomiz1734/Ritder/releases/latest/download/ritder-update.tar.gz | sha256sum
   ```
   `version` phải là bản vừa phát hành, và mã SHA-256 tính được phải trùng trường `sha256`.

### 5.2 Nâng phiên bản KOReader

`upstream.json` ghim bản KOReader (`koreader-linux-arm64-*.tar.xz`) và các gói glibc Debian, kèm SHA-256. Đổi sang bản KOReader mới: sửa mục `koreader` (tên file, URL, SHA-256), chạy `build.ps1`. `tools/build.py` sẽ **dừng build** nếu một chỗ vá không còn khớp (xem `PATCHES` trong file đó), để không lặng lẽ mất phần của Ritder. Nếu bản KOReader mới đòi glibc mới hơn 2.36, đổi luôn các gói Debian (bookworm → trixie).

---

## 6. Các lớp an toàn

| Nguy cơ | Được chặn bởi |
|---|---|
| Bị chèn nội dung giữa đường (mạng công cộng) | Chỉ HTTPS, cả ở từng bước chuyển hướng; chứng chỉ được kiểm tra theo `ca-bundle.crt` |
| Gói tải về bị hỏng, thiếu hoặc bị tráo | So kích thước và SHA-256 với `update.json` |
| Gói chứa đường dẫn `../`, đường dẫn tuyệt đối hoặc symlink | Giải nén từ chối, không file nào được ghi |
| Gói sai máy (ví dụ nhầm bản PC) | Kiểm tra `luajit` là ELF ARM64 trước khi chép |
| Mất cài đặt, lịch sử đọc sau khi cập nhật | Không bao giờ ghi vào `userdata/` |
| Mất điện giữa lúc chép file | Dấu `installing` → lần mở sau tự trả lại file cũ |
| Bản mới crash ngay khi mở | Tự trả lại **toàn bộ** file cũ (kể cả `launch.sh`, thư viện) |
| Tự hạ cấp về bản cũ hơn | Chỉ đề nghị khi phiên bản mới hơn |
| Giao diện đơ khi mạng chậm | Kiểm tra, tải, cài đều chạy trong tiến trình con |

---

## 7. Giới hạn đã biết

1. **Chỉ bắt được lỗi dạng "thoát ngay".** Nếu bản mới treo (không thoát) hoặc chạy được quá 10 giây rồi mới lỗi, nó đã được xác nhận là tốt và sẽ không tự quay về. Khi đó phải cài tay bằng `Ritder-stock.zip` của bản trước.
2. **`update.json` không được ký số.** Độ tin cậy dựa trên HTTPS và bảo mật tài khoản GitHub. Ai chiếm được tài khoản `nomiz1734` là phát hành được bản giả. Ngoài ra LuaSec kiểm tra chuỗi chứng chỉ nhưng **không kiểm tra tên máy chủ**. Nếu cần chặt hơn: ký `update.json` bằng khóa ed25519, gắn khóa công khai vào app lúc build, và app từ chối bảng kê không có chữ ký hợp lệ.
3. **Cần đồng hồ đúng.** Máy để sai giờ (ví dụ về năm 1970) thì không kiểm tra được chứng chỉ, OTA báo lỗi đồng hồ. Chỉnh giờ trong Stock OS rồi thử lại.
4. **Gói lớn (~44 MB) vì là toàn bộ app.** Lần nào cũng tải lại cả KOReader. Có thể làm gói chênh lệch (chỉ các file đổi) ở bản sau.
5. **Cần chỗ trống trên thẻ** khoảng 3 lần kích thước gói trong lúc cập nhật (gói nén, bản giải nén, bản sao lưu).
6. **GitHub đôi khi trả HTTP 504** (máy chủ tải file quá tải). Đó là lỗi tạm thời: bấm **Thử lại** sau vài phút.
7. **Kiểm tra tự động chỉ chạy một lần mỗi lần mở app.**

---

## 8. Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| "Chưa cấu hình địa chỉ cập nhật" | `ritder_update_url` là `""` | Xóa khóa đó khỏi `userdata/settings.reader.lua` (dùng địa chỉ gắn sẵn) hoặc điền `https://github.com/nomiz1734/Ritder/releases/latest/download/update.json` |
| "máy chủ trả lỗi HTTP 504" | GitHub quá tải tạm thời | Thử lại sau vài phút, hoặc cài tay |
| "đồng hồ của máy đang sai" | Giờ hệ thống sai | Chỉnh ngày giờ trong Stock OS |
| "file tải về bị hỏng (sai SHA-256)" / "bị thiếu" | Mạng chập chờn, hoặc gói trên GitHub không khớp `update.json` | Thử lại; nếu vẫn lỗi, kiểm tra lại bằng lệnh ở mục 5.1 bước 8 |
| "gói cập nhật không đúng kiến trúc ARM64" | Phát hành nhầm gói | Build lại bằng `build.ps1`, phát hành lại |
| Cập nhật xong app mở rồi báo đã quay về bản cũ | Bản mới crash lúc khởi động | Xem `userdata/update.log` |
| App không mở được sau cập nhật | Cả hai bản đều lỗi, hoặc file bị hỏng | Cài tay: giải nén `Ritder-stock.zip`, chép đè vào `Apps/Ritder` (không xóa `userdata/`) |
