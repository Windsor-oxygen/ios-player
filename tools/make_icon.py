#!/usr/bin/env python3
"""Генератор иконок приложения Player и логотипа для launch screen.

Зависимость: только Pillow (`pip install Pillow`).
Запуск из корня репозитория:  python3 tools/make_icon.py

Создаёт:
  App/Resources/Assets.xcassets/AppIcon*.appiconset/<имя>{,-Dark,-Tinted}.png
      основная иконка и альтернативные, 1024×1024, RGB без альфа-канала
      (single-size формат iOS 18: обычная, тёмная и tinted-версия)
  App/Resources/Assets.xcassets/IconPreview-*.imageset/
      превью для экрана выбора иконки (светлое и тёмное)
  App/Resources/Assets.xcassets/LaunchLogo.imageset/LaunchLogo{,@2x,@3x}.png
      логотип с прозрачностью для UILaunchScreen

Дизайн: пять скруглённых «эквалайзерных» полос, образующих ромб звуковой
волны, со свечением. Все варианты — один мотив в разных палитрах.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # суперсэмплинг для сглаживания краёв
BIG = SIZE * SS

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App" / "Resources" / "Assets.xcassets"
PREVIEW = 240  # px, превью в сетке выбора иконки
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


def bars_mask(size: int, scale: float = 1.0, outline: float = 0.0) -> Image.Image:
    """Маска «L» с пятью скруглёнными вертикальными полосами по центру.
    `outline` > 0 — только контур такой толщины (доля ширины полосы)."""
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
        box = (x, cy - h / 2, x + bar_w, cy + h / 2)
        if outline > 0:
            draw.rounded_rectangle(box, radius=bar_w / 2, outline=255, width=max(1, int(bar_w * outline)))
        else:
            draw.rounded_rectangle(box, radius=bar_w / 2, fill=255)
    return mask


def bars_layer(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int],
               scale: float = 1.0, outline: float = 0.0) -> Image.Image:
    fill = vertical_gradient((size, size), top, bottom)
    if outline > 0:
        # Контурные «неоновые» полосы: градиент слева направо.
        fill = fill.transpose(Image.Transpose.ROTATE_90)
    fill = fill.convert("RGBA")
    fill.putalpha(bars_mask(size, scale, outline))
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


def make_tinted(outline: float = 0.0) -> Image.Image:
    # Tinted-вариант: оттенки серого, система сама окрашивает по яркости.
    base = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 255))
    bars = bars_layer(BIG, (255, 255, 255), (170, 170, 170), outline=outline)
    base.alpha_composite(bars)
    return flatten(base).convert("L").convert("RGB")



RGB = tuple[int, int, int]


@dataclass(frozen=True)
class Variant:
    """Альтернативная иконка: палитра светлой и тёмной версии и форма полос."""
    name: str            # имя набора в asset catalog
    bg: tuple[RGB, RGB]  # градиент фона сверху вниз
    glows: tuple[tuple[RGB, float, tuple[float, float], float], ...]
    bars: tuple[RGB, RGB]
    halo: RGB
    halo_strength: float
    dark_bg: tuple[RGB, RGB]
    dark_bars: tuple[RGB, RGB]
    outline: float = 0.0  # > 0 — контурные «неоновые» полосы


VARIANTS = (
    Variant("AppIcon-Sunset",
            bg=((255, 138, 76), (196, 30, 98)),
            glows=(((255, 214, 102), 0.60, (0.25, 0.20), 0.60), ((120, 20, 90), 0.55, (0.80, 0.85), 0.45)),
            bars=((255, 255, 255), (255, 226, 204)), halo=(255, 196, 120), halo_strength=0.45,
            dark_bg=((34, 16, 22), (8, 4, 8)), dark_bars=((255, 160, 96), (232, 64, 120))),
    Variant("AppIcon-Ocean",
            bg=((0, 168, 180), (6, 32, 92)),
            glows=(((120, 240, 255), 0.60, (0.28, 0.22), 0.50), ((20, 60, 160), 0.50, (0.78, 0.82), 0.50)),
            bars=((255, 255, 255), (176, 240, 255)), halo=(110, 230, 255), halo_strength=0.50,
            dark_bg=((10, 22, 34), (2, 6, 12)), dark_bars=((96, 228, 244), (48, 116, 236))),
    Variant("AppIcon-Mint",
            bg=((18, 92, 72), (4, 24, 22)),
            glows=(((90, 255, 190), 0.58, (0.30, 0.24), 0.40), ((0, 120, 110), 0.50, (0.76, 0.84), 0.40)),
            bars=((232, 255, 244), (120, 240, 196)), halo=(90, 255, 190), halo_strength=0.40,
            dark_bg=((12, 24, 20), (3, 7, 6)), dark_bars=((140, 250, 204), (40, 190, 150))),
    Variant("AppIcon-Graphite",
            bg=((62, 64, 70), (14, 14, 16)),
            glows=(((190, 190, 200), 0.60, (0.30, 0.20), 0.18),),
            bars=((252, 252, 254), (164, 168, 176)), halo=(200, 200, 210), halo_strength=0.20,
            dark_bg=((22, 22, 24), (4, 4, 5)), dark_bars=((206, 206, 212), (112, 114, 122))),
    Variant("AppIcon-Paper",
            bg=((252, 247, 236), (232, 221, 202)),
            glows=(((255, 210, 160), 0.60, (0.75, 0.80), 0.25),),
            bars=((44, 38, 70), (92, 66, 122)), halo=(255, 255, 255), halo_strength=0.0,
            dark_bg=((30, 28, 26), (10, 10, 10)), dark_bars=((248, 238, 220), (200, 188, 166))),
    Variant("AppIcon-Neon",
            bg=((14, 8, 30), (0, 0, 4)),
            glows=(((255, 43, 214), 0.50, (0.25, 0.80), 0.30), ((34, 228, 255), 0.50, (0.78, 0.20), 0.30)),
            bars=((34, 228, 255), (255, 43, 214)), halo=(120, 160, 255), halo_strength=0.95,
            dark_bg=((6, 4, 14), (0, 0, 0)), dark_bars=((34, 228, 255), (255, 43, 214)),
            outline=0.26),
)


def render_variant(bg: tuple[RGB, RGB], glows, bars_colors: tuple[RGB, RGB], halo: RGB,
                   halo_strength: float, outline: float) -> Image.Image:
    base = vertical_gradient((BIG, BIG), *bg).convert("RGBA")
    for color, radius, center, strength in glows:
        base.alpha_composite(radial_glow(BIG, color, radius, center, strength))
    bars = bars_layer(BIG, *bars_colors, outline=outline)
    if halo_strength > 0:
        glow = bars.getchannel("A").filter(ImageFilter.GaussianBlur(BIG * (0.02 if outline else 0.03)))
        light = Image.new("RGBA", (BIG, BIG), (*halo, 255))
        light.putalpha(glow.point(lambda v: int(min(255, v * halo_strength * (1.6 if outline else 1)))))
        base.alpha_composite(light)
    if not outline:
        base.alpha_composite(soft_shadow(bars, BIG * 0.012, 0.30), (0, int(BIG * 0.008)))
    base.alpha_composite(bars)
    return flatten(base)


def make_variant(v: Variant) -> dict[str, Image.Image]:
    light = render_variant(v.bg, v.glows, v.bars, v.halo, v.halo_strength, v.outline)
    dark = render_variant(v.dark_bg, tuple((c, r, ctr, s * 0.5) for c, r, ctr, s in v.glows),
                          v.dark_bars, v.dark_bars[0], v.halo_strength * 0.6, v.outline)
    return {"": light, "-Dark": dark, "-Tinted": make_tinted(v.outline)}


def make_logo(px: int) -> Image.Image:
    big = px * SS
    layer = bars_layer(big, BAR_TOP, BAR_BOTTOM, scale=1.6)
    return layer.resize((px, px), Image.Resampling.LANCZOS)


def icon_contents(name: str) -> dict:
    def image(suffix: str, appearance: str | None) -> dict:
        entry = {"filename": f"{name}{suffix}.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry = {"appearances": [{"appearance": "luminosity", "value": appearance}], **entry}
        return entry
    return {"images": [image("", None), image("-Dark", "dark"), image("-Tinted", "tinted")],
            "info": {"author": "xcode", "version": 1}}


def preview_contents(name: str) -> dict:
    return {"images": [
        {"filename": f"{name}.png", "idiom": "universal"},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}],
         "filename": f"{name}-Dark.png", "idiom": "universal"},
    ], "info": {"author": "xcode", "version": 1}}


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, separators=(",", " : ")) + "\n", encoding="utf-8")


def save_icon_set(name: str, images: dict[str, Image.Image]) -> None:
    folder = ASSETS / f"{name}.appiconset"
    folder.mkdir(parents=True, exist_ok=True)
    for suffix, image in images.items():
        assert image.mode == "RGB" and image.size == (SIZE, SIZE), name
        image.save(folder / f"{name}{suffix}.png", optimize=True)
    write_json(folder / "Contents.json", icon_contents(name))
    # Превью для экрана выбора иконки (из обычной и тёмной версии).
    preview_name = f"IconPreview-{name}"
    preview = ASSETS / f"{preview_name}.imageset"
    preview.mkdir(parents=True, exist_ok=True)
    for suffix in ("", "-Dark"):
        small = images[suffix].resize((PREVIEW, PREVIEW), Image.Resampling.LANCZOS)
        small.save(preview / f"{preview_name}{suffix}.png", optimize=True)
    write_json(preview / "Contents.json", preview_contents(preview_name))
    print("wrote", folder.name, preview.name)


def main() -> None:
    LOGO_DIR.mkdir(parents=True, exist_ok=True)
    save_icon_set("AppIcon", {"": make_light(), "-Dark": make_dark(), "-Tinted": make_tinted()})
    for variant in VARIANTS:
        save_icon_set(variant.name, make_variant(variant))
    for suffix, px in (("", 120), ("@2x", 240), ("@3x", 360)):
        path = LOGO_DIR / f"LaunchLogo{suffix}.png"
        make_logo(px).save(path, optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
