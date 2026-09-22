"""Builds the OTA package and its manifest from dist/Ritder.

    python tools/make_update.py <dist/Ritder> <out dir> <version> [notes or notes-file]

Writes <out>/ritder-update.tar.gz and <out>/update.json. Upload both to the same
place (one GitHub release) and point the app's update URL at update.json.
The user's data (userdata/) is never part of the package.
"""
import hashlib
import json
import os
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build import EXECUTABLE  # noqa: E402

PACKAGE = "ritder-update.tar.gz"
SKIP_DIRS = {"userdata"}
SKIP_FILES = {"settings.json"}


def main() -> None:
    src, out, version = sys.argv[1], sys.argv[2], sys.argv[3]
    notes = sys.argv[4] if len(sys.argv) > 4 else ""
    # Notes may be a UTF-8 text file (safer than passing Vietnamese on a command line).
    if notes and os.path.isfile(notes):
        with open(notes, encoding="utf-8-sig") as f:
            notes = f.read().strip()
    os.makedirs(out, exist_ok=True)
    pkg = os.path.join(out, PACKAGE)
    count = 0
    with tarfile.open(pkg, "w:gz", format=tarfile.GNU_FORMAT, compresslevel=9) as tar:
        for root, dirs, files in os.walk(src):
            if root == src:
                dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            dirs.sort()
            for name in sorted(files):
                full = os.path.join(root, name)
                rel = os.path.relpath(full, src).replace(os.sep, "/")
                if rel in SKIP_FILES:
                    continue
                info = tar.gettarinfo(full, arcname=rel)
                info.mode = 0o755 if rel in EXECUTABLE else 0o644
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                with open(full, "rb") as f:
                    tar.addfile(info, f)
                count += 1
    data = open(pkg, "rb").read()
    manifest = {
        "version": version,
        "notes": notes,
        "file": PACKAGE,
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
    }
    with open(os.path.join(out, "update.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"OTA package: {pkg} ({count} files, {len(data)} bytes)")


if __name__ == "__main__":
    main()
