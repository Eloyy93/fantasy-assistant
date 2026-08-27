"""Genera los gráficos que pide la ficha de Play Store a partir del icono
ya diseñado (assets/icon/app_icon.png): el icono de 512x512 que exige la
Play Console, y el "gráfico de funciones" (feature graphic) de 1024x500
que se ve en la cabecera de la ficha.
"""
from PIL import Image, ImageDraw, ImageFont

SRC_ICON = r"C:\Users\Eloy\Desktop\Biwengerfantasy\app\assets\icon\app_icon.png"
OUT_DIR = r"C:\Users\Eloy\Desktop\Biwengerfantasy\store_assets"

BG = (10, 11, 13, 255)
MINT = (33, 230, 164, 255)
FONT_PATH = r"C:\Windows\Fonts\arialbd.ttf"


def make_icon_512():
    img = Image.open(SRC_ICON).convert("RGB").resize((512, 512), Image.LANCZOS)
    img.save(f"{OUT_DIR}\\icon_512.png")


def make_feature_graphic():
    W, H = 1024, 500
    img = Image.new("RGB", (W, H), BG[:3])
    draw = ImageDraw.Draw(img)

    # Insignia a la izquierda.
    badge = Image.open(SRC_ICON).convert("RGBA")
    badge_size = 340
    badge = badge.resize((badge_size, badge_size), Image.LANCZOS)
    img.paste(badge, (60, (H - badge_size) // 2), badge)

    # Texto a la derecha.
    title_font = ImageFont.truetype(FONT_PATH, 64)
    subtitle_font = ImageFont.truetype(FONT_PATH, 28)

    tx = 60 + badge_size + 50
    draw.text((tx, 175), "Master Fantasy", font=title_font, fill=(255, 255, 255))
    draw.text(
        (tx, 265),
        "Biwenger y LaLiga Fantasy,",
        font=subtitle_font,
        fill=(154, 163, 168),
    )
    draw.text(
        (tx, 302),
        "en una sola app",
        font=subtitle_font,
        fill=(154, 163, 168),
    )

    # Línea de acento.
    draw.rectangle([tx, 350, tx + 90, 356], fill=MINT[:3])

    img.save(f"{OUT_DIR}\\feature_graphic.png")


if __name__ == "__main__":
    import os
    os.makedirs(OUT_DIR, exist_ok=True)
    make_icon_512()
    make_feature_graphic()
    print("OK")
