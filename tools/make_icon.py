#!/usr/bin/env python3
"""Генератор иконки приложения «Плеер» и логотипа для launch screen.

Зависимость: только Pillow (`pip install Pillow`).
Запуск из корня репозитория:  python3 tools/make_icon.py

Создаёт:
  App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon{,-Dark,-Tinted}.png
      1024×1024, RGB без альфа-канала (single-size формат iOS 18)
  App/Resources/Assets.xcassets/LaunchLogo.imageset/LaunchLogo{,@2x,@3x}.png
      логотип с прозрачностью для UILaunchScreen

Дизайн: пять скруглённых «эквалайзерных» полос, образующих ромб звуковой
волны, на глубоком фиолетово-синем градиенте с мягким свечением.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # суперсэмплинг для сглаживания краёв
BIG = SIZE * SS

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App" / "Resources" / "Assets.xcassets"
ICON_DIR = ASSETS / "AppIcon.appiconset"
LOGO_DIR = ASSETS / "LaunchLogo.imageset"

# Палитра
BG_TOP = (44, 26, 102)        # #2C1A66
BG_BOTTOM = (12, 10, 34)      # #0C0A22
GLOW = (255, 77, 141)         # #FF4D8D
GLOW_2 = (122, 92, 255)       # #7A5CFF
BAR_TOP = (255, 255, 255)
BAR_BOTTOM = (255, 196, 222)  # #FFC4DE

# Относительные высоты полос (симметричный «ромб» волны)
BAR_HEIGHTS = (0.34, 0.62, 0.88, 0.62, 0.34)


def vertical_gradient(size: tuple[int, int], top: tuple[int, int, int],
                      bottom: tuple[int, int, int]) -> Image.Image:
    mask = Image.linear_gradient("L").resize(size, Image.Resampling.BICUBIC)
    return Image.composite(Image.new("RGB", size, bottom),
                           Image.new("RGB", size, top), mask)


def radial_glow(size: int, color: tuple[int, int, int], radius: float,
                center: tuple[float, float], strength: float) -> Image.Image:
    """RGBA-пятно света: непрозрачное в центре, затухающее к радиусу."""
    diameter = int(size * radius * 2)
    falloff = Image.radial_gradient("L").resize((diameter, diameter),
                                                Image.Resampling.BICUBIC)
    # radial_gradient даёт 0 в центре и ≈181 на середине стороны квадрата
    # (255 — в углах), поэтому нормируем на 181, чтобы край был прозрачным.
    alpha = falloff.point(lambda v: int(max(0.0, 1.0 - v / 181.0) ** 2 * 255 * strength))
    layer = Image.new("RGBA", (size, size), (*color, 0))
    spot = Image.new("RGBA", (diameter, diameter), (*color, 255))
    spot.putalpha(alpha)
    cx, cy = int(center[0] * size), int(center[1] * size)
    layer.alpha_composite(spot, (cx - diameter // 2, cy - diameter // 2))
    return layer


def bars_mask(size: int, scale: float = 1.0) -> Image.Image:
    """Маска «L» с пятью скруглёнными вертикальными полосами по центру."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    count = len(BAR_HEIGHTS)
    content = size * 0.56 * scale
    bar_w = content / (count * 1.0 + (count - 1) * 0.55)
    gap = bar_w * 0.55
    total_w = count * bar_w + (count - 1) * gap
    x0 = (size - total_w) / 2
    cy = size / 2
    for i, rel in enumerate(BAR_HEIGHTS):
        h = content * rel
        x = x0 + i * (bar_w + gap)
        draw.rounded_rectangle((x, cy - h / 2, x + bar_w, cy + h / 2),
                               radius=bar_w / 2, fill=255)
    return mask


def bars_layer(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int],
               scale: float = 1.0) -> Image.Image:
    fill = vertical_gradient((size, size), top, bottom).convert("RGBA")
    fill.putalpha(bars_mask(size, scale))
    return fill


def soft_shadow(layer: Image.Image, blur: float, opacity: float) -> Image.Image:
    alpha = layer.getchannel("A").filter(ImageFilter.GaussianBlur(blur))
    alpha = alpha.point(lambda v: int(v * opacity))
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 255))
    shadow.putalpha(alpha)
    return shadow


def flatten(img: Image.Image) -> Image.Image:
    """Уменьшает до 1024 и убирает альфа-канал (требование App Store / actool)."""
    small = img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    if small.mode != "RGB":
        background = Image.new("RGB", small.size, (0, 0, 0))
        background.paste(small, mask=small.getchannel("A"))
        small = background
    return small


def make_light() -> Image.Image:
    base = vertical_gradient((BIG, BIG), BG_TOP, BG_BOTTOM).convert("RGBA")
    base.alpha_composite(radial_glow(BIG, GLOW_2, 0.62, (0.30, 0.25), 0.55))
    base.alpha_composite(radial_glow(BIG, GLOW, 0.48, (0.72, 0.80), 0.50))
    bars = bars_layer(BIG, BAR_TOP, BAR_BOTTOM)
    glow = bars.getchannel("A").filter(ImageFilter.GaussianBlur(BIG * 0.03))
    halo = Image.new("RGBA", (BIG, BIG), (*GLOW, 255))
    halo.putalpha(glow.point(lambda v: int(v * 0.55)))
    base.alpha_composite(halo)
    base.alpha_composite(soft_shadow(bars, BIG * 0.012, 0.35), (0, int(BIG * 0.008)))
    base.alpha_composite(bars)
    return flatten(base)


def make_dark() -> Image.Image:
    base = vertical_gradient((BIG, BIG), (22, 20, 30), (6, 6, 10)).convert("RGBA")
    base.alpha_composite(radial_glow(BIG, GLOW_2, 0.55, (0.5, 0.5), 0.22))
    bars = bars_layer(BIG, (255, 120, 170), (150, 110, 255))
    base.alpha_composite(soft_shadow(bars, BIG * 0.02, 0.6))
    base.alpha_composite(bars)
    return flatten(base)


def make_tinted() -> Image.Image:
    # Tinted-вариант: оттенки серого, система сама окрашивает по яркости.
    base = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 255))
    bars = bars_layer(BIG, (255, 255, 255), (170, 170, 170))
    base.alpha_composite(bars)
    return flatten(base).convert("L").convert("RGB")


def make_logo(px: int) -> Image.Image:
    big = px * SS
    layer = bars_layer(big, BAR_TOP, BAR_BOTTOM, scale=1.6)
    return layer.resize((px, px), Image.Resampling.LANCZOS)


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    LOGO_DIR.mkdir(parents=True, exist_ok=True)
    for name, image in (("AppIcon.png", make_light()),
                        ("AppIcon-Dark.png", make_dark()),
                        ("AppIcon-Tinted.png", make_tinted())):
        assert image.mode == "RGB" and image.size == (SIZE, SIZE)
        image.save(ICON_DIR / name, optimize=True)
        print("wrote", ICON_DIR / name)
    for suffix, px in (("", 120), ("@2x", 240), ("@3x", 360)):
        path = LOGO_DIR / f"LaunchLogo{suffix}.png"
        make_logo(px).save(path, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
