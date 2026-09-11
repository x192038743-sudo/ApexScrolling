"""生成 ApexScrolling 应用图标（Android mipmap + iOS AppIcon）。

用法（Windows，需 Pillow）：  python tool/make_icon.py

设计：深色底 + 衬线大写 A + 琥珀色下划线，呼应 App 的「纯文字 + 衬线排版」。
主图另存到 assets/branding/app_icon_1024.png，作为后续改图的源文件。
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MASTER = 1024

BG_TOP = (23, 23, 26)
BG_BOTTOM = (12, 12, 14)
FG = (237, 234, 227)
ACCENT = (201, 162, 39)

SERIF_CANDIDATES = [
    Path(r"C:\Windows\Fonts\georgia.ttf"),
    Path(r"C:\Windows\Fonts\times.ttf"),
    Path(r"C:\Windows\Fonts\constan.ttf"),
]

ANDROID_MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def pick_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in SERIF_CANDIDATES:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def render_master() -> Image.Image:
    gradient = Image.new("RGB", (1, MASTER))
    for y in range(MASTER):
        t = y / (MASTER - 1)
        gradient.putpixel(
            (0, y),
            tuple(int(top + (bottom - top) * t) for top, bottom in zip(BG_TOP, BG_BOTTOM)),
        )
    image = gradient.resize((MASTER, MASTER)).convert("RGBA")
    draw = ImageDraw.Draw(image)

    font = pick_font(int(MASTER * 0.60))
    text = "A"
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    width, height = right - left, bottom - top
    x = (MASTER - width) / 2 - left
    y = (MASTER - height) / 2 - top - int(MASTER * 0.07)
    draw.text((x, y), text, font=font, fill=FG)

    bar_width = int(MASTER * 0.32)
    bar_height = max(3, int(MASTER * 0.026))
    bar_x = (MASTER - bar_width) // 2
    bar_y = int(y + bottom + MASTER * 0.075)
    draw.rounded_rectangle(
        (bar_x, bar_y, bar_x + bar_width, bar_y + bar_height),
        radius=bar_height // 2,
        fill=ACCENT,
    )
    return image


def write_png(image: Image.Image, size: int, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.LANCZOS)
    resized.save(path, format="PNG", optimize=True)
    print(f"  {size:>4}px -> {path.relative_to(ROOT)}")


def main() -> None:
    master = render_master()
    branding = ROOT / "assets" / "branding" / "app_icon_1024.png"
    branding.parent.mkdir(parents=True, exist_ok=True)
    master.save(branding, format="PNG")
    print(f"主图: {branding.relative_to(ROOT)}")

    print("Android mipmap:")
    for folder, size in ANDROID_MIPMAPS.items():
        write_png(
            master,
            size,
            ROOT / "android" / "app" / "src" / "main" / "res" / folder / "ic_launcher.png",
        )

    print("iOS AppIcon:")
    appicon_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((appicon_dir / "Contents.json").read_text(encoding="utf-8"))
    pattern = re.compile(r"Icon-App-([\d.]+)x([\d.]+)@(\d)x\.png")
    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        match = pattern.match(filename)
        if not match:
            continue
        size = round(float(match.group(1)) * int(match.group(3)))
        write_png(master, size, appicon_dir / filename)


if __name__ == "__main__":
    main()
