"""Draws package/stock/icon.png (300x300): an open book on a rounded tile.

    python tools/make_icon.py
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 300
SS = 4  # supersampling for smooth edges


def main() -> None:
    s = SIZE * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=64 * SS, fill=(28, 44, 74, 255))

    cx, top, bottom = s // 2, 78 * SS, 222 * SS
    page_w = 96 * SS
    sag = 14 * SS
    for side in (-1, 1):
        outer = cx + side * page_w
        d.polygon(
            [(cx, top + sag), (outer, top), (outer, bottom - sag), (cx, bottom)],
            fill=(246, 241, 228, 255),
        )
        # text lines
        for i in range(5):
            y = top + (26 + i * 22) * SS
            x0 = cx + side * 18 * SS
            x1 = cx + side * (page_w - 18 * SS)
            d.line([(x0, y + sag // 2), (x1, y)], fill=(160, 170, 190, 255), width=5 * SS)
    d.line([(cx, top + sag), (cx, bottom)], fill=(28, 44, 74, 255), width=4 * SS)
    # bookmark ribbon
    bx = cx + 58 * SS
    d.polygon(
        [(bx, top - 6 * SS), (bx + 22 * SS, top - 9 * SS), (bx + 22 * SS, top + 58 * SS),
         (bx + 11 * SS, top + 46 * SS), (bx, top + 60 * SS)],
        fill=(236, 92, 72, 255),
    )

    out = os.path.join(ROOT, "package", "stock", "icon.png")
    img.resize((SIZE, SIZE), Image.LANCZOS).save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
