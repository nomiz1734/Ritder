"""Publishes dist/ as a GitHub release so devices pick it up over OTA.

    python tools/publish_release.py

Uses the repo from update-url.txt, the version from VERSION and the notes from
release-notes.txt. Authenticates with the GitHub login that Git already stored
(Git Credential Manager), so no separate token is needed. Push your commits
first: the release tag is created on `main`.
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ASSETS = [
    (os.path.join("dist", "update", "update.json"), "application/json"),
    (os.path.join("dist", "update", "ritder-update.tar.gz"), "application/gzip"),
    (os.path.join("dist", "Ritder-stock.zip"), "application/zip"),
]


def read(name: str) -> str:
    with open(os.path.join(ROOT, name), encoding="utf-8-sig") as f:
        return f.read()


def token(owner: str) -> str:
    # Naming the account avoids Git Credential Manager's account picker when
    # several GitHub logins are saved on the PC.
    out = subprocess.run(
        ["git", "credential", "fill"],
        input=f"protocol=https\nhost=github.com\nusername={owner}\n\n",
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    sys.exit("Không tìm thấy đăng nhập GitHub. Hãy `git push` một lần để đăng nhập.")


def call(url: str, tok: str, data: bytes | None = None, ctype: str = "application/json"):
    req = urllib.request.Request(url, data=data, method="POST" if data is not None else "GET")
    req.add_header("Authorization", f"Bearer {tok}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "ritder-publish")
    if data is not None:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"GitHub trả lỗi HTTP {e.code}: {e.read().decode(errors='replace')[:400]}")


def main() -> None:
    m = re.search(r"github\.com/([^/]+/[^/]+)/releases", read("update-url.txt"))
    if not m:
        sys.exit("update-url.txt phải trỏ tới https://github.com/<user>/<repo>/releases/...")
    repo = m.group(1)
    version = read("VERSION").strip()
    manifest = json.loads(read(os.path.join("dist", "update", "update.json")))
    if manifest["version"] != version:
        sys.exit(f"dist/ là bản {manifest['version']}, VERSION là {version}: hãy chạy build.ps1 lại")
    for rel_path, _ in ASSETS:
        if not os.path.exists(os.path.join(ROOT, rel_path)):
            sys.exit(f"thiếu {rel_path}: hãy chạy build.ps1 trước")
    notes = read("release-notes.txt").strip()
    body = (
        f"{notes}\n\n"
        "**Cài lần đầu:** giải nén `Ritder-stock.zip`, chép thư mục `Ritder` vào `Apps/` trên thẻ nhớ.\n"
        "**Đã cài rồi:** mở Ritder → MENU → Kiểm tra cập nhật (OTA).\n\n"
        "`update.json` và `ritder-update.tar.gz` là file dùng cho OTA."
    )
    tok = token(repo.split("/")[0])
    rel = call(
        f"https://api.github.com/repos/{repo}/releases",
        tok,
        json.dumps(
            {
                "tag_name": f"v{version}",
                "target_commitish": "main",
                "name": f"Ritder {version}",
                "body": body,
                "make_latest": "true",
            }
        ).encode(),
    )
    upload = rel["upload_url"].split("{")[0]
    for rel_path, ctype in ASSETS:
        name = os.path.basename(rel_path)
        with open(os.path.join(ROOT, rel_path), "rb") as f:
            a = call(f"{upload}?name={name}", tok, f.read(), ctype)
        print(f"  {a['name']} ({a['size']} bytes)")
    print(f"Đã phát hành {version}: {rel['html_url']}")


if __name__ == "__main__":
    main()
