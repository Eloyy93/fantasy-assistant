"""Genera el icono de la app (Master Fantasy): fondo oscuro + insignia
verde menta con una "M" y una estrella, a juego con el tema de la app
(kBgColor #0A0B0D, kMintAccent #21E6A4). Genera:
- app_icon.png: 1024x1024 con fondo, para el icono "legacy" (iOS/fallback).
- app_icon_foreground.png: 1024x1024 transparente, insignia centrada en la
  zona segura (~66%), para el foreground del icono adaptativo de Android.
"""
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
BG = (10, 11, 13, 255)  # kBgColor
MINT = (33, 230, 164, 255)  # kMintAccent
MINT_DARK = (18, 158, 112, 255)
DARK_TEXT = (7, 8, 9, 255)

FONT_PATH = r"C:\Windows\Fonts\arialbd.ttf"


def _badge(canvas_size: int, transparent_bg: bool) -> Image.Image:
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0) if transparent_bg else BG)
    draw = ImageDraw.Draw(img)

    center = canvas_size / 2
    # En el icono con fondo, la insignia ocupa ~62% del lienzo (deja aire
    # alrededor, como los iconos de otras apps). En el foreground adaptativo
    # (que Android recorta/anima), ocupa ~46% para quedar dentro de la zona
    # segura tras el recorte.
    badge_radius = canvas_size * (0.23 if transparent_bg else 0.31)

    # Sombra sutil bajo la insignia.
    if not transparent_bg:
        shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        sd.ellipse(
            [center - badge_radius, center - badge_radius + canvas_size * 0.02,
             center + badge_radius, center + badge_radius + canvas_size * 0.02],
            fill=(0, 0, 0, 90),
        )
        shadow = shadow.filter(__import__("PIL.ImageFilter", fromlist=["ImageFilter"]).GaussianBlur(canvas_size * 0.015))
        img.alpha_composite(shadow)
        draw = ImageDraw.Draw(img)

    # Insignia circular en degradado (simulado con dos círculos superpuestos).
    draw.ellipse(
        [center - badge_radius, center - badge_radius, center + badge_radius, center + badge_radius],
        fill=MINT,
    )
    inner_r = badge_radius * 0.94
    draw.ellipse(
        [center - inner_r, center - inner_r * 0.98, center + inner_r, center + inner_r * 1.0],
        fill=MINT_DARK,
    )
    draw.ellipse(
        [center - badge_radius, center - badge_radius, center + badge_radius, center + badge_radius * 0.55],
        fill=MINT,
    )

    # "M" centrada.
    font_size = int(badge_radius * 1.55)
    font = ImageFont.truetype(FONT_PATH, font_size)
    text = "M"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((center - tw / 2 - bbox[0], center - th / 2 - bbox[1] - badge_radius * 0.06), text, font=font, fill=DARK_TEXT)

    # Estrellita arriba a la derecha de la insignia (toque "master"),
    # completamente dentro del círculo para que no quede cortada.
    star_cx = center + badge_radius * 0.46
    star_cy = center - badge_radius * 0.62
    star_r = badge_radius * 0.16
    _draw_star(draw, star_cx, star_cy, star_r, DARK_TEXT)

    return img


def _draw_star(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill) -> None:
    import math
    points = []
    for i in range(10):
        angle = math.pi / 2 + i * math.pi / 5
        radius = r if i % 2 == 0 else r * 0.42
        points.append((cx + radius * math.cos(angle), cy - radius * math.sin(angle)))
    draw.polygon(points, fill=fill)


if __name__ == "__main__":
    out_dir = r"C:\Users\Eloy\Desktop\Biwengerfantasy\app\assets\icon"
    _badge(SIZE, transparent_bg=False).convert("RGB").save(f"{out_dir}\\app_icon.png")
    _badge(SIZE, transparent_bg=True).save(f"{out_dir}\\app_icon_foreground.png")
    print("OK")
