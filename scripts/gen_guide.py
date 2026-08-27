"""Genera store_assets/deployment_guide.html con las capturas e imágenes
embebidas como data URIs, para que la guía sea un único archivo
autocontenido publicable como Artifact."""
import base64

ROOT = r"C:\Users\Eloy\Desktop\Biwengerfantasy"


def b64(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


IMAGES = {
    "icon": f"{ROOT}\\store_assets\\icon_512.png",
    "feature": f"{ROOT}\\store_assets\\feature_graphic.png",
    "s1": f"{ROOT}\\screenshots\\01_busqueda.png",
    "s2": f"{ROOT}\\screenshots\\02_ficha.png",
    "s3": f"{ROOT}\\screenshots\\03_plantilla.png",
    "s4": f"{ROOT}\\screenshots\\04_optimizador.png",
    "s5": f"{ROOT}\\screenshots\\05_comparador.png",
}

DATA = {k: f"data:image/png;base64,{b64(v)}" for k, v in IMAGES.items()}

with open(f"{ROOT}\\store_assets\\deployment_guide_template.html", "r", encoding="utf-8") as f:
    html = f.read()

for key, uri in DATA.items():
    html = html.replace(f"{{{{{key}}}}}", uri)

with open(f"{ROOT}\\store_assets\\deployment_guide.html", "w", encoding="utf-8") as f:
    f.write(html)

print("OK", len(html), "bytes")
