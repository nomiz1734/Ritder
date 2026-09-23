"""Assembles dist/Ritder from the pinned upstream KOReader build and the Ritder overlay.

    python tools/build.py [--update-url URL]

Steps:
 1. download (or reuse from vendor/cache) every file pinned in upstream.json, checking SHA-256;
 2. unpack KOReader's linux-arm64 tree (lib/koreader/*) into dist/Ritder;
 3. unpack glibc 2.36 + libstdc++ from the Debian debs into dist/Ritder/sys
    (the upstream binaries need glibc >= 2.35, the TrimUI firmware is older);
 4. copy overlay/ on top and apply the small text patches listed in PATCHES;
 5. write frontend/ritder/build_info.lua (version, OTA manifest URL, KOReader version);
 6. copy package/stock (launch.sh, config.json, icon, first-run defaults);
 7. zip dist/Ritder into dist/Ritder-stock.zip (first install / manual install).

Symlinks are flattened into regular files: the SD card is FAT/exFAT.
"""
import argparse
import hashlib
import io
import json
import os
import shutil
import stat
import sys
import tarfile
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "vendor", "cache")
DIST_ROOT = os.path.join(ROOT, "dist")
DIST = os.path.join(DIST_ROOT, "Ritder")

# Files that must keep the executable bit (in the zip and in the OTA tarball).
EXECUTABLE = {
    "launch.sh",
    "install.sh",
    "logging.sh",
    "luajit",
    "reader.lua",
    "sdcv",
    "sdcv.bin",
    "sys/ld-linux-aarch64.so.1",
}

# (file, anchor, text, where): insert `text` before/after the first line containing `anchor`.
# The build fails if an anchor is missing, so a KOReader bump cannot silently drop a patch.
PATCHES = [
    (
        "frontend/device.lua",
        "if util.loadSDL3() then",
        '    if os.getenv("RITDER_DEVICE") == "trimui-brick-pro" then\n'
        '        return require("device/trimui/device")\n'
        "    end\n\n",
        "before",
    ),
    (
        "frontend/ui/elements/filemanager_menu_order.lua",
        '"ota_update", -- if Device:hasOTAUpdates()',
        '        "ritder_update", -- Ritder OTA (plugins/ritderupdate.koplugin)\n',
        "after",
    ),
    (
        "frontend/ui/elements/reader_menu_order.lua",
        '"ota_update", -- if Device:hasOTAUpdates()',
        '        "ritder_update", -- Ritder OTA (plugins/ritderupdate.koplugin)\n',
        "after",
    ),
    # Right under "Night mode" in both menus: the switch from ritder/night_pages.lua.
    (
        "frontend/ui/elements/filemanager_menu_order.lua",
        '"night_mode",',
        '        "ritder_night_pages",\n',
        "after",
    ),
    (
        "frontend/ui/elements/reader_menu_order.lua",
        '"night_mode",',
        '        "ritder_night_pages",\n',
        "after",
    ),
]


def read_text(name: str) -> str:
    with open(os.path.join(ROOT, name), encoding="utf-8-sig") as f:
        return f.read()


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(entry: dict) -> str:
    """Returns the local path of a pinned file, downloading it if needed."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, entry["file"])
    if os.path.exists(path) and sha256_file(path) == entry["sha256"]:
        return path
    errors = []
    for url in entry["urls"]:
        print(f"  downloading {url}")
        tmp = path + ".part"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ritder-build"})
            with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
                shutil.copyfileobj(r, f, 1 << 20)
        except Exception as e:  # noqa: BLE001 - try the next mirror
            errors.append(f"{url}: {e}")
            continue
        got = sha256_file(tmp)
        if got != entry["sha256"]:
            os.remove(tmp)
            errors.append(f"{url}: SHA-256 {got} does not match upstream.json")
            continue
        os.replace(tmp, path)
        return path
    sys.exit(f"cannot fetch {entry['file']}:\n  " + "\n  ".join(errors))


def resolve_member(tar: tarfile.TarFile, member: tarfile.TarInfo, depth: int = 0) -> tarfile.TarInfo:
    """Follows symlinks/hardlinks inside the archive to a regular file member."""
    if depth > 16:
        raise RuntimeError(f"symlink loop at {member.name}")
    if member.issym():
        target = os.path.normpath(os.path.join(os.path.dirname(member.name), member.linkname)).replace(os.sep, "/")
    elif member.islnk():
        target = member.linkname
    else:
        return member
    for cand in (target, "./" + target, target.lstrip("./")):
        try:
            return resolve_member(tar, tar.getmember(cand), depth + 1)
        except KeyError:
            pass
    raise RuntimeError(f"dangling link {member.name} -> {member.linkname}")


def write_member(tar: tarfile.TarFile, member: tarfile.TarInfo, dest: str) -> None:
    real = resolve_member(tar, member)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with tar.extractfile(real) as src, open(dest, "wb") as out:
        shutil.copyfileobj(src, out, 1 << 20)


def unpack_koreader(archive: str) -> None:
    prefix = "lib/koreader/"
    count = 0
    with tarfile.open(archive, "r:xz") as tar:
        for m in tar.getmembers():
            name = m.name.lstrip("./")
            if not name.startswith(prefix) or m.isdir():
                continue
            rel = name[len(prefix):]
            if not rel or rel.startswith("/") or ".." in rel.split("/"):
                continue
            write_member(tar, m, os.path.join(DIST, rel))
            count += 1
    print(f"  KOReader: {count} files")


def deb_data(path: str) -> tarfile.TarFile:
    data = open(path, "rb").read()
    if data[:8] != b"!<arch>\n":
        sys.exit(f"{path} is not a .deb")
    off = 8
    while off < len(data):
        name = data[off:off + 16].decode().strip().rstrip("/")
        size = int(data[off + 48:off + 58])
        body = data[off + 60:off + 60 + size]
        off += 60 + size + (size & 1)
        if name.startswith("data.tar"):
            return tarfile.open(fileobj=io.BytesIO(body))
    sys.exit(f"{path}: no data.tar member")


def unpack_runtime(entry: dict, archive: str) -> None:
    tar = deb_data(archive)
    for want in entry["extract"]:
        member = None
        for cand in (want, "./" + want):
            try:
                member = tar.getmember(cand)
                break
            except KeyError:
                pass
        if member is None:
            sys.exit(f"{entry['file']}: {want} not found")
        write_member(tar, member, os.path.join(DIST, "sys", os.path.basename(want)))
    print(f"  runtime: {entry['file']} ({len(entry['extract'])} files)")


def wrap_sdcv() -> None:
    """sdcv (dictionary lookups) is a separate program: route it through the bundled loader too."""
    sdcv = os.path.join(DIST, "sdcv")
    if not os.path.exists(sdcv):
        return
    os.replace(sdcv, os.path.join(DIST, "sdcv.bin"))
    with open(sdcv, "w", newline="\n") as f:
        f.write(
            "#!/bin/sh\n"
            "# Ritder: run sdcv with the bundled glibc (see launch.sh).\n"
            'd=$(cd "$(dirname "$0")" && pwd)\n'
            'exec "$d/sys/ld-linux-aarch64.so.1" --library-path "$d/sys:$d/libs" "$d/sdcv.bin" "$@"\n'
        )


def copy_tree(src: str, dst: str) -> int:
    count = 0
    for root, _dirs, files in os.walk(src):
        for name in files:
            if name.endswith((".pyc",)) or name == ".gitkeep":
                continue
            full = os.path.join(root, name)
            out = os.path.join(dst, os.path.relpath(full, src))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            shutil.copyfile(full, out)
            count += 1
    return count


def apply_patches() -> None:
    for rel, anchor, text, where in PATCHES:
        path = os.path.join(DIST, rel)
        with open(path, encoding="utf-8", newline="") as f:
            lines = f.read().split("\n")
        idx = next((i for i, line in enumerate(lines) if anchor in line), None)
        if idx is None:
            sys.exit(f"patch anchor not found in {rel}: {anchor!r} (KOReader changed? update PATCHES)")
        insert = text.rstrip("\n").split("\n")
        if where == "after":
            idx += 1
        lines[idx:idx] = insert
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write("\n".join(lines))
        print(f"  patched {rel}")


def lua_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def write_build_info(version: str, update_url: str, koreader_version: str) -> None:
    path = os.path.join(DIST, "frontend", "ritder", "build_info.lua")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(
            "-- Generated by tools/build.py. Do not edit.\n"
            "return {\n"
            f"    version = {lua_string(version)},\n"
            f"    update_url = {lua_string(update_url)},\n"
            f"    koreader_version = {lua_string(koreader_version)},\n"
            "}\n"
        )


def to_lf(path: str) -> None:
    with open(path, "rb") as f:
        data = f.read()
    with open(path, "wb") as f:
        f.write(data.replace(b"\r\n", b"\n"))


def make_zip(out: str) -> None:
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, dirs, files in os.walk(DIST):
            dirs.sort()
            for name in sorted(files):
                full = os.path.join(root, name)
                rel = os.path.relpath(full, DIST).replace(os.sep, "/")
                info = zipfile.ZipInfo.from_file(full, "Ritder/" + rel)
                mode = 0o755 if rel in EXECUTABLE else 0o644
                info.external_attr = (stat.S_IFREG | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                with open(full, "rb") as f:
                    z.writestr(info, f.read())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--update-url", default="")
    args = ap.parse_args()

    version = read_text("VERSION").strip()
    update_url = args.update_url or (read_text("update-url.txt").strip() if os.path.exists(os.path.join(ROOT, "update-url.txt")) else "")
    pins = json.loads(read_text("upstream.json"))

    if os.path.isdir(DIST_ROOT):
        shutil.rmtree(DIST_ROOT)
    os.makedirs(DIST)

    print("Fetching upstream files")
    unpack_koreader(fetch(pins["koreader"]))
    for entry in pins["runtime"]:
        unpack_runtime(entry, fetch(entry))
    wrap_sdcv()

    print("Applying the Ritder overlay")
    print(f"  overlay: {copy_tree(os.path.join(ROOT, 'overlay'), DIST)} files")
    apply_patches()
    write_build_info(version, update_url, pins["koreader"]["version"])
    copy_tree(os.path.join(ROOT, "package", "stock"), DIST)
    to_lf(os.path.join(DIST, "launch.sh"))
    to_lf(os.path.join(DIST, "install.sh"))
    to_lf(os.path.join(DIST, "logging.sh"))
    to_lf(os.path.join(DIST, "sdcv"))

    make_zip(os.path.join(DIST_ROOT, "Ritder-stock.zip"))
    print(f"Package ready: {DIST} (Ritder {version}, KOReader {pins['koreader']['version']})")
    if update_url:
        print(f"OTA manifest: {update_url}")


if __name__ == "__main__":
    main()
