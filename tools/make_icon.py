"""Draws the Ritder logo (an open book on a rounded tile).

    python tools/make_icon.py

Writes:
  package/stock/icon.png            300x300 launcher icon for the Stock OS. The tile only covers
                                    the middle 184x184 (58 px transparent margin), the same
                                    proportions as the stock app icons, so it fits the Apps grid.
  overlay/resources/koreader.png    256x256 logo that replaces KOReader's inside the app
  overlay/resources/koreader.svg    (About dialog, fallback images...)
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4  # supersampling for smooth edges

TILE = (28, 44, 74, 255)
PAGE = (246, 241, 228, 255)
LINE = (160, 170, 190, 255)
RIBBON = (236, 92, 72, 255)


def tile(size: int) -> Image.Image:
    """The logo filling a size x size square (drawn in a 300-unit design space)."""
    s = size * SS
    k = s / 300
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(64 * k), fill=TILE)
    cx, top, bottom = s / 2, 78 * k, 222 * k
    page_w, sag = 96 * k, 14 * k
    for side in (-1, 1):
        outer = cx + side * page_w
        d.polygon([(cx, top + sag), (outer, top), (outer, bottom - sag), (cx, bottom)], fill=PAGE)
        for i in range(5):
            y = top + (26 + i * 22) * k
            x0 = cx + side * 18 * k
            x1 = cx + side * (page_w - 18 * k)
            d.line([(x0, y + sag / 2), (x1, y)], fill=LINE, width=max(1, int(5 * k)))
    d.line([(cx, top + sag), (cx, bottom)], fill=TILE, width=max(1, int(4 * k)))
    bx = cx + 58 * k
    d.polygon(
        [(bx, top - 6 * k), (bx + 22 * k, top - 9 * k), (bx + 22 * k, top + 58 * k),
         (bx + 11 * k, top + 46 * k), (bx, top + 60 * k)],
        fill=RIBBON,
    )
    return img.resize((size, size), Image.LANCZOS)


def svg() -> str:
    lines = []
    for side in (-1, 1):
        outer = 150 + side * 96
        lines.append(f'<polygon points="150,92 {outer},78 {outer},208 150,222" fill="#f6f1e4"/>')
        for i in range(5):
            y = 78 + 26 + i * 22
            x0 = 150 + side * 18
            x1 = 150 + side * 78
            lines.append(f'<line x1="{x0}" y1="{y + 7}" x2="{x1}" y2="{y}" stroke="#a0aabe" stroke-width="5"/>')
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300" width="300" height="300">\n'
        '<rect width="300" height="300" rx="64" fill="#1c2c4a"/>\n'
        + "\n".join(lines)
        + '\n<line x1="150" y1="92" x2="150" y2="222" stroke="#1c2c4a" stroke-width="4"/>\n'
        '<polygon points="208,72 230,69 230,136 219,124 208,138" fill="#ec5c48"/>\n'
        "</svg>\n"
    )


def main() -> None:
    launcher = Image.new("RGBA", (300, 300), (0, 0, 0, 0))
    launcher.paste(tile(184), (58, 58))
    out = os.path.join(ROOT, "package", "stock", "icon.png")
    launcher.save(out)
    print(f"wrote {out}")

    res = os.path.join(ROOT, "overlay", "resources")
    os.makedirs(res, exist_ok=True)
    tile(256).save(os.path.join(res, "koreader.png"))
    with open(os.path.join(res, "koreader.svg"), "w", encoding="utf-8", newline="\n") as f:
        f.write(svg())
    print(f"wrote {res}\\koreader.png, koreader.svg")


if __name__ == "__main__":
    main()
