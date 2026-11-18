#!/usr/bin/env python3
"""Generates the legacy PNG launcher icons from the same geometry as the
vector mark. Run from android/: python3 scripts/generate-icons.py"""
from pathlib import Path
from PIL import Image, ImageDraw

RES = Path(__file__).resolve().parent.parent / "app" / "src" / "main" / "res"
S = 1024
SS = 2
W = S * SS

NAVY = (11, 18, 32, 255)
WHITE = (255, 255, 255, 255)
START = (22, 185, 143)
END = (47, 125, 225)


def gradient(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = (
                round(START[0] + (END[0] - START[0]) * t),
                round(START[1] + (END[1] - START[1]) * t),
                round(START[2] + (END[2] - START[2]) * t),
                255,
            )
    return img


def shield_points() -> list[tuple[float, float]]:
    # 48x48 source geometry, sampled as a polygon. The curved bottom is
    # approximated by a polyline; antialiasing hides the tiny facets.
    pts = [(24, 2), (44, 10), (44, 25)]
    # quadratic-ish curve from (44,25) to (24,46.8) to (4,25)
    for i in range(1, 33):
        t = i / 32
        # Bezier with control points (44,36), (35,43), (24,46.8)
        x = (1 - t) ** 2 * 44 + 2 * (1 - t) * t * 35.2 + t ** 2 * 24
        y = (1 - t) ** 2 * 25 + 2 * (1 - t) * t * 43.6 + t ** 2 * 46.8
        pts.append((x, y))
    for i in range(1, 33):
        t = i / 32
        x = (1 - t) ** 2 * 24 + 2 * (1 - t) * t * 12.8 + t ** 2 * 4
        y = (1 - t) ** 2 * 46.8 + 2 * (1 - t) * t * 43.6 + t ** 2 * 25
        pts.append((x, y))
    pts.append((4, 10))
    return pts


def x_points() -> list[tuple[float, float]]:
    # Even-odd style X built as two crossing bars.
    return [
        (15.5, 14.5), (20.7, 14.5), (24.0, 19.6), (27.3, 14.5), (32.5, 14.5),
        (26.6, 23.5), (32.7, 33.0), (27.5, 33.0), (24.0, 27.5), (20.5, 33.0),
        (15.3, 33.0), (21.4, 23.5),
    ]


def draw_icon(round_icon: bool) -> Image.Image:
    scale = W * 0.62 / 48
    ox = (W - 48 * scale) / 2
    oy = (W - 48 * scale) / 2

    def tr(points):
        return [(ox + x * scale, oy + y * scale) for x, y in points]

    icon = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    mask = Image.new("L", (W, W), 0)
    md = ImageDraw.Draw(mask)
    if round_icon:
        md.ellipse((0, 0, W - 1, W - 1), fill=255)
    else:
        md.rounded_rectangle((0, 0, W - 1, W - 1), radius=int(W * 0.22), fill=255)
    bg = gradient(W)
    icon.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(icon)
    draw.polygon(tr(shield_points()), fill=WHITE)
    draw.polygon(tr(x_points()), fill=NAVY)
    return icon.resize((S, S), Image.LANCZOS)


def draw_notification(size: int) -> Image.Image:
    ss = 8
    w = size * ss
    scale = w * 0.92 / 48
    ox = (w - 48 * scale) / 2
    oy = (w - 48 * scale) / 2

    def tr(points):
        return [(ox + x * scale, oy + y * scale) for x, y in points]

    icon = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)
    draw.polygon(tr(shield_points()), fill=WHITE)
    # Notification icons use alpha only; punch the X out so it reads as a
    # silhouette at 24dp.
    draw.polygon(tr(x_points()), fill=(0, 0, 0, 0))
    return icon.resize((size, size), Image.LANCZOS)


def main():
    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    square = draw_icon(False)
    circle = draw_icon(True)
    for density, size in sizes.items():
        out = RES / f"mipmap-{density}"
        out.mkdir(parents=True, exist_ok=True)
        square.resize((size, size), Image.LANCZOS).save(out / "ic_launcher.png")
        circle.resize((size, size), Image.LANCZOS).save(out / "ic_launcher_round.png")

    stat_sizes = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}
    for density, size in stat_sizes.items():
        out = RES / f"drawable-{density}"
        out.mkdir(parents=True, exist_ok=True)
        draw_notification(size).save(out / "ic_stat_xrv.png")

    square.resize((512, 512), Image.LANCZOS).save(
        Path(__file__).resolve().parent.parent / "XRV-arm64-icon.png"
    )
    print("Launcher and notification icons generated.")


if __name__ == "__main__":
    main()
