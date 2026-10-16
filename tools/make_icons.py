"""Draws the ProxyProof owl app icon + splash images for Android (run once; outputs are committed).

    py tools/make_icons.py
"""
import pathlib

from PIL import Image, ImageDraw

NAVY, NAVY2, CAP = (11, 27, 63), (19, 40, 90), (7, 18, 44)
GOLD, IVORY, WHITE = (212, 167, 58), (248, 245, 238), (255, 255, 255)
RES = pathlib.Path(__file__).resolve().parent.parent / "app" / "android" / "app" / "src" / "main" / "res"


def owl(size, with_bg=True, scale=1.0):
    """Owl on a size x size canvas. Drawn at 4x then downsampled for smooth edges."""
    S = size * 4
    img = Image.new("RGBA", (S, S), NAVY + (255,) if with_bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = S / 200 * scale  # design grid is 200x200, like the in-app painter
    off = (S - 200 * k) / 2

    def P(x, y):
        return (off + x * k, off + y * k)

    def E(cx, cy, w, h, fill):
        d.ellipse([P(cx - w / 2, cy - h / 2), P(cx + w / 2, cy + h / 2)], fill=fill)

    if with_bg:  # soft gold glow behind the owl, blended on its own layer
        glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        g = ImageDraw.Draw(glow)
        for r, a in ((96, 28), (84, 26), (72, 24)):
            g.ellipse([P(100 - r, 106 - r), P(100 + r, 106 + r)], fill=(GOLD[0], GOLD[1], GOLD[2], a))
        img = Image.alpha_composite(img, glow)
        d = ImageDraw.Draw(img)
    d.polygon([P(52, 62), P(60, 30), P(80, 52)], fill=NAVY if not with_bg else NAVY2)  # ear tufts
    d.polygon([P(148, 62), P(140, 30), P(120, 52)], fill=NAVY if not with_bg else NAVY2)
    E(100, 112, 124, 140, NAVY2 if with_bg else NAVY)  # body
    E(100, 132, 78, 84, IVORY)  # belly
    for i, xs in enumerate(((86, 100, 114), (86, 100, 114), (100,))):  # gold chevrons
        y = 122 + i * 14
        for x in xs:
            d.arc([P(x - 5, y - 5), P(x + 5, y + 6)], 20, 160, fill=GOLD, width=int(3 * k))
    E(100, 84, 104, 70, (30, 58, 122))  # face disc
    for cx in (78, 122):  # eyes
        E(cx, 84, 44, 44, GOLD)
        E(cx, 84, 37, 37, WHITE)
        E(cx + 1, 85, 17, 17, NAVY)
        E(cx + 4, 81.5, 5.2, 5.2, WHITE)
    d.polygon([P(93, 96), P(107, 96), P(100, 110)], fill=GOLD)  # beak
    for x in (86, 114):  # feet
        d.rounded_rectangle([P(x - 9, 176), P(x + 9, 184)], radius=4 * k, fill=GOLD)
    d.polygon([P(100, 22), P(150, 38), P(100, 54), P(50, 38)], fill=CAP)  # mortarboard
    d.rounded_rectangle([P(74, 45), P(126, 59)], radius=4 * k, fill=CAP)
    d.line([P(100, 38), P(140, 40), P(140, 62)], fill=GOLD, width=int(2.5 * k))  # tassel
    E(100, 38, 7, 7, GOLD)
    E(140, 64, 8, 8, GOLD)
    return img.resize((size, size), Image.LANCZOS)


def rounded(img, radius_frac=0.22):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0], img.size[1]], radius=int(img.size[0] * radius_frac), fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main():
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for name, px in legacy.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        rounded(owl(px, scale=0.86)).save(folder / "ic_launcher.png")
        # adaptive-icon foreground: 108dp canvas, owl kept inside the 66dp safe zone
        owl(int(px * 108 / 48), with_bg=False, scale=0.58).save(folder / "ic_launcher_foreground.png")
    (RES / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (RES / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )
    (RES / "values").mkdir(exist_ok=True)
    (RES / "values" / "colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#0B1B3F</color>\n'
        '    <color name="splash_background">#0B1B3F</color>\n</resources>\n'
    )
    # splash image (pre-Android-12 launch screen)
    (RES / "drawable-nodpi").mkdir(exist_ok=True)
    owl(288, with_bg=False, scale=0.9).save(RES / "drawable-nodpi" / "splash_owl.png")
    owl(512).save(pathlib.Path(__file__).resolve().parent.parent / "docs" / "icon.png")
    print("icons written to", RES)


if __name__ == "__main__":
    main()
