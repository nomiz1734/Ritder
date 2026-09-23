"""Runs Ritder on the PC and saves screenshots of its screens, for checking the UI without the device.

    python tools/emulate.py --setup              once: create the WSL1 distro "RitderEmu"
    python tools/emulate.py                      run every script in tests/screens
    python tools/emulate.py 02_menus             run tests/screens/02_menus.lua only

Screenshots land in dist/emulator/shots/<script>/*.png.

How it works: the same KOReader version is available as an x86_64 Linux build, so
dist/emulator/Ritder is that build + the Ritder overlay and patches (exactly the Lua that
runs on the Brick). It runs in a WSL1 distro (WSL1 needs no hardware virtualization) with
RITDER_EMULATOR=1: the TrimUI device then draws into an in-memory 1024x768 screen and takes
its button presses from the script, sent as the raw evdev events of the Brick Pro
(device/trimui/emulator.lua). Every run starts from fresh settings, like a first install,
with a Books folder of generated sample PDF/CBZ/EPUB files.

What it does not show: the real /dev/fb0 and evdev devices, speed on the A133p, networking
of the device. Those still need the device.
"""
import io
import json
import os
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build  # noqa: E402

ROOT = build.ROOT
EMU = os.path.join(ROOT, "dist", "emulator")
APP = os.path.join(EMU, "Ritder")
BOOKS = os.path.join(EMU, "Books")
SHOTS = os.path.join(EMU, "shots")
SCRIPTS = os.path.join(ROOT, "tests", "screens")
DISTRO = "RitderEmu"
DISTRO_DIR = os.path.join(ROOT, "vendor", "wsl", "distro")
TIMEOUT_S = 900
WSL_USERDATA = "/tmp/ritder-emu-userdata"


def wsl_path(path: str) -> str:
    path = os.path.abspath(path).replace("\\", "/")
    return f"/mnt/{path[0].lower()}{path[2:]}"


def setup() -> None:
    pins = json.loads(build.read_text("upstream.json"))
    rootfs = build.fetch(pins["wsl_rootfs"])
    os.makedirs(DISTRO_DIR, exist_ok=True)
    subprocess.run(["wsl", "--import", DISTRO, DISTRO_DIR, rootfs, "--version", "1"], check=True)
    print(f"WSL1 distro {DISTRO} ready (remove with: wsl --unregister {DISTRO})")


def build_package() -> None:
    """The ARM64 package tests/screens/11_ota_install.lua unpacks. Rebuilding wipes dist/,
    so this runs before the emulator tree is assembled."""
    package = os.path.join(ROOT, "dist", "update", "ritder-update.tar.gz")
    if os.path.exists(package):
        return
    version = build.read_text("VERSION").strip()
    notes = os.path.join(ROOT, "release-notes.txt")
    print("Building the OTA package first (dist/update)")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build.py")], check=True,
                   stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "make_update.py"),
                    os.path.join(ROOT, "dist", "Ritder"), os.path.join(ROOT, "dist", "update"),
                    version, notes], check=True, stdout=subprocess.DEVNULL)


def assemble() -> None:
    pins = json.loads(build.read_text("upstream.json"))
    if os.path.isdir(APP):
        shutil.rmtree(APP)
    os.makedirs(APP)
    build.DIST = APP
    build.unpack_koreader(build.fetch(pins["koreader_emulator"]))
    build.copy_tree(os.path.join(ROOT, "overlay"), APP)
    build.apply_patches()
    build.write_build_info(build.read_text("VERSION").strip(), build.read_text("update-url.txt").strip(),
                           pins["koreader"]["version"])
    build.copy_tree(os.path.join(ROOT, "package", "stock"), APP)


def font(size: int):
    from PIL import ImageFont
    for name in ("arial.ttf", "tahoma.ttf", "segoeui.ttf"):
        try:
            return ImageFont.truetype(os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts", name), size)
        except OSError:
            pass
    return ImageFont.load_default()


def page_image(title: str, n: int, w: int = 900, h: int = 1270, color=(250, 250, 245)):
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (w, h), color)
    d = ImageDraw.Draw(img)
    d.text((60, 60), title, fill=(20, 20, 20), font=font(56))
    body = font(30)
    for i in range(18):
        d.text((60, 180 + i * 56), f"Trang {n}, dòng {i + 1}: nội dung mẫu để kiểm tra hiển thị tiếng Việt.",
               fill=(40, 40, 40), font=body)
    d.rectangle((60, h - 140, w - 60, h - 80), outline=(120, 120, 120), width=3)
    d.text((w // 2 - 60, h - 132), f"- {n} -", fill=(80, 80, 80), font=font(36))
    return img


def comic_page(n: int):
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (900, 1350), (255, 255, 255))
    d = ImageDraw.Draw(img)
    colors = [(230, 90, 70), (70, 130, 220), (90, 180, 110), (240, 190, 60)]
    panels = [(40, 40, 860, 520), (40, 560, 430, 1310), (470, 560, 860, 1310)]
    for i, (x0, y0, x1, y1) in enumerate(panels):
        d.rectangle((x0, y0, x1, y1), fill=colors[(n + i) % 4], outline=(0, 0, 0), width=8)
        d.ellipse((x0 + 40, y0 + 40, x0 + 260, y0 + 160), fill=(255, 255, 255), outline=(0, 0, 0), width=5)
        d.text((x0 + 70, y0 + 80), f"Trang {n}!", fill=(0, 0, 0), font=font(40))
    return img


def make_books() -> None:
    from PIL import Image
    Image.init()  # registers the JPEG/PDF writers
    if os.path.isdir(BOOKS):
        shutil.rmtree(BOOKS)
    os.makedirs(os.path.join(BOOKS, "Truyen tranh"))
    pages = [page_image("Sách mẫu PDF", n) for n in range(1, 6)]
    pages[0].save(os.path.join(BOOKS, "Sach mau.pdf"), save_all=True, append_images=pages[1:], resolution=150)
    with zipfile.ZipFile(os.path.join(BOOKS, "Truyen tranh", "Truyen mau.cbz"), "w") as z:
        for n in range(1, 6):
            buf = io.BytesIO()
            comic_page(n).save(buf, "JPEG", quality=85)
            z.writestr(f"{n:03d}.jpg", buf.getvalue())
    make_epub(os.path.join(BOOKS, "Truyen ngan.epub"))
    # A series of 8, like a manga split into volumes: two pages of list in the file browser.
    series = os.path.join(BOOKS, "Conan")
    os.makedirs(series)
    for n, (a, b) in enumerate([(0, 28), (29, 57), (58, 85), (86, 114), (115, 143), (144, 171), (172, 200), (201, 229)]):
        pages = [comic_page(n + k) for k in range(2)]
        pages[0].save(os.path.join(series, f"Conan chap {a}-{b}.pdf"), save_all=True, append_images=pages[1:],
                      resolution=100)


def make_epub(path: str) -> None:
    chapters = []
    for c in range(1, 4):
        paras = "".join(
            f"<p>Đây là đoạn {p} của chương {c}. Ritder hiển thị chữ tiếng Việt có dấu: "
            "ăâđêôơư, ÁÀẢÃẠ, những con đường làng quê yên ả buổi chiều.</p>"
            for p in range(1, 13))
        chapters.append(f'<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml">'
                        f"<head><title>Chương {c}</title></head><body><h1>Chương {c}</h1>{paras}</body></html>")
    manifest = "".join(f'<item id="c{i}" href="c{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(1, 4))
    spine = "".join(f'<itemref idref="c{i}"/>' for i in range(1, 4))
    nav = "".join(f'<navPoint id="n{i}" playOrder="{i}"><navLabel><text>Chương {i}</text></navLabel>'
                  f'<content src="c{i}.xhtml"/></navPoint>' for i in range(1, 4))
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")
        z.writestr("META-INF/container.xml",
                   '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                   '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
                   "</rootfiles></container>")
        z.writestr("OEBPS/content.opf",
                   '<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
                   'unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
                   '<dc:title>Truyện ngắn mẫu</dc:title><dc:creator>Ritder</dc:creator><dc:language>vi</dc:language>'
                   '<dc:identifier id="id">ritder-sample</dc:identifier></metadata>'
                   f'<manifest>{manifest}<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>'
                   f'<spine toc="ncx">{spine}</spine></package>')
        z.writestr("OEBPS/toc.ncx",
                   '<?xml version="1.0" encoding="utf-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
                   f"<head/><docTitle><text>Truyện ngắn mẫu</text></docTitle><navMap>{nav}</navMap></ncx>")
        for i, html in enumerate(chapters, 1):
            z.writestr(f"OEBPS/c{i}.xhtml", html)


def run_script(name: str) -> int:
    make_books()  # every script starts from the same books, without reading positions
    script = os.path.join(SCRIPTS, name + ".lua")
    out = os.path.join(SHOTS, name)
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    # The settings seed is written here; the app's userdata lives inside WSL (/tmp), because
    # SQLite (CoverBrowser's cache) gets I/O errors on Windows drives under WSL1.
    userdata = os.path.join(EMU, "userdata-seed")
    if os.path.isdir(userdata):
        shutil.rmtree(userdata)
    os.makedirs(userdata)
    books = wsl_path(BOOKS)
    with open(os.path.join(ROOT, "package", "stock", "defaults", "settings.reader.lua"), encoding="utf-8") as f:
        defaults = f.read().replace("@HOME_DIR@", books)
    with open(os.path.join(userdata, "settings.reader.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(defaults)
    env = {
        "RITDER_DIR": wsl_path(APP),
        "RITDER_DEVICE": "trimui-brick-pro",
        "RITDER_EMULATOR": "1",
        "RITDER_EMU_SCRIPT": wsl_path(script),
        "RITDER_EMU_OUT": wsl_path(out),
        "RITDER_EMU_BOOKS": books,
        "RITDER_HOME_DIR": books,
        "KO_HOME": WSL_USERDATA,
        # The package built by build.ps1, for the OTA script (a local file, no network).
        "RITDER_EMU_PACKAGE": wsl_path(os.path.join(ROOT, "dist", "update", "ritder-update.tar.gz")),
        "LC_ALL": "C.UTF-8",
    }
    exports = " ".join(f"{k}='{v}'" for k, v in env.items())
    debug = " -d" if os.environ.get("RITDER_EMU_DEBUG") else ""
    cmd = (f"rm -rf {WSL_USERDATA} && mkdir -p {WSL_USERDATA} && "
           f"cp '{wsl_path(userdata)}/settings.reader.lua' {WSL_USERDATA}/ && "
           f"cd '{wsl_path(APP)}' && env {exports} ./luajit reader.lua{debug}")
    log_path = os.path.join(out, "run.log")
    print(f"== {name}")
    with open(log_path, "wb") as log:
        try:
            code = subprocess.run(["wsl", "-d", DISTRO, "--", "/bin/sh", "-c", cmd],
                                  stdout=log, stderr=subprocess.STDOUT, timeout=TIMEOUT_S).returncode
        except subprocess.TimeoutExpired:
            code = -1
    with open(log_path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    for line in text.splitlines():
        if line.startswith("EMU ") or " ERROR " in line or "stack traceback" in line or line.startswith("./luajit:"):
            print("  " + line)
    shots = sorted(p for p in os.listdir(out) if p.endswith(".png"))
    print(f"  exit {code}, {len(shots)} screenshots in {out}")
    return code


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")  # the app logs in Vietnamese
    args = sys.argv[1:]
    if args[:1] == ["--setup"]:
        setup()
        return 0
    names = args or sorted(os.path.splitext(p)[0] for p in os.listdir(SCRIPTS) if p.endswith(".lua"))
    if any("ota" in name for name in names):
        build_package()
    assemble()
    names = args or sorted(os.path.splitext(p)[0] for p in os.listdir(SCRIPTS) if p.endswith(".lua"))
    failed = 0
    for name in names:
        if run_script(name) != 0:
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
