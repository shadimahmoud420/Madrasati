"""Generates assets/icon/icon.png (1024, opaque) and icon_foreground.png
(adaptive-icon foreground with safe-zone padding). Run: python3 tool/make_icon.py

Design: teal → indigo gradient, a white open book and a golden star above it.
"""
import os

from PIL import Image, ImageDraw

S = 1024
SS = 4  # supersampling
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")


def gradient(size):
    stops = [(0.0, (15, 118, 110)), (1.0, (67, 56, 202))]
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        (t0, c0), (t1, c1) = stops
        color = tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
        for x in range(size):
            px[x, y] = color
    return img


def star(d, cx, cy, r_out, r_in, fill):
    import math
    pts = []
    for i in range(10):
        r = r_out if i % 2 == 0 else r_in
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill=fill)


def glyph(scale):
    """White book + gold star on a transparent canvas, scaled around center."""
    size = S * SS
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    u = SS * scale
    c = size / 2

    def p(x, y):
        return (c + x * u, c + y * u)

    white = (255, 255, 255, 255)
    shade = (220, 232, 255, 255)
    # Left and right pages, slightly lifted at the outer edges.
    d.polygon([p(-20, -40), p(-330, -95), p(-330, 260), p(-20, 300)], fill=white)
    d.polygon([p(20, -40), p(330, -95), p(330, 260), p(20, 300)], fill=white)
    # Page lines.
    for i in range(4):
        y = 20 + i * 60
        d.line([p(-280, y - 45), p(-70, y - 10)], fill=shade, width=int(18 * u))
        d.line([p(70, y - 10), p(280, y - 45)], fill=shade, width=int(18 * u))
    star(d, *p(0, -240), 150 * u, 62 * u, (251, 191, 36, 255))
    return layer


def main():
    os.makedirs(OUT, exist_ok=True)
    bg = gradient(S * SS).convert("RGBA")
    icon = Image.alpha_composite(bg, glyph(1.0)).resize((S, S), Image.LANCZOS).convert("RGB")
    icon.save(os.path.join(OUT, "icon.png"))
    # Adaptive icons crop to a circle/squircle: keep the glyph inside ~66%.
    fg = glyph(0.62).resize((S, S), Image.LANCZOS)
    fg.save(os.path.join(OUT, "icon_foreground.png"))
    print("Wrote", OUT)


if __name__ == "__main__":
    main()
