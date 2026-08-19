#!/usr/bin/env python3
"""Genera los sprites del juego a assets/sprites/*.png

Mismo criterio que generate_sfx.py: arte 100% original y regenerable, sin
descargas ni dudas de licencia frente a la clausula de honestidad academica.

Los personajes se dibujan vistos DESDE ARRIBA y mirando a la DERECHA (+X),
porque en Godot una rotacion de 0 rad apunta a +X: el sprite se rota con
`rotation = facing.angle()` y encara solo.

Requiere Pillow:  pip install pillow
Uso:              python tools/generate_sprites.py
"""

from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# Plano dentro de assets/, que es donde AssetLibrary los busca
# (SPRITE_DIR = "res://assets/"). Antes apuntaba a assets/sprites/ y los PNG
# generados quedaban en una carpeta que el juego no mira.
OUT_DIR = Path(__file__).resolve().parent.parent / "assets"

# Se dibuja a 4x y se reduce: da bordes limpios sin tener que antialiasear a mano.
SS = 4

COLORS = {
    "player": (89, 217, 242),
    "a": (222, 77, 66),
    "b": (92, 140, 235),
    "c": (237, 184, 61),
    "agent": (140, 242, 153),
}

OUTLINE = (18, 16, 24, 255)


def _shade(color: tuple[int, int, int], factor: float) -> tuple[int, int, int, int]:
    return (
        max(0, min(255, int(color[0] * factor))),
        max(0, min(255, int(color[1] * factor))),
        max(0, min(255, int(color[2] * factor))),
        255,
    )


def _canvas(size: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _finish(img: Image.Image, size: int, name: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = img.resize((size, size), Image.LANCZOS)
    out.save(OUT_DIR / name)
    print(f"  {name}  ({size}x{size})")


def actor(name: str, color: tuple[int, int, int], size: int = 32) -> None:
    """Personaje visto desde arriba, mirando a +X.

    Composicion: hombros (elipse ancha en vertical), cabeza (circulo) desplazada
    hacia el frente, y un arma corta saliendo por delante. Con eso se lee la
    direccion de un vistazo incluso a 32 px, que es lo que importa en un
    top-down rapido.
    """
    img, d = _canvas(size)
    c = size * SS / 2
    u = size * SS / 32  # unidad relativa, para que escale a cualquier tamano

    # Sombra proyectada: despega al personaje del suelo.
    d.ellipse([c - 11 * u, c - 10 * u, c + 11 * u, c + 10 * u], fill=(0, 0, 0, 70))

    # Arma
    d.rounded_rectangle([c + 4 * u, c - 2 * u, c + 15 * u, c + 2 * u],
                        radius=1.5 * u, fill=(46, 44, 56, 255))

    # Hombros / torso
    d.ellipse([c - 9 * u, c - 10 * u, c + 8 * u, c + 10 * u],
              fill=_shade(color, 0.72), outline=OUTLINE, width=int(1.6 * u))

    # Brazos
    for sign in (-1, 1):
        d.ellipse([c + 2 * u, c + sign * 5 * u - 3.5 * u,
                   c + 9 * u, c + sign * 5 * u + 3.5 * u],
                  fill=_shade(color, 0.58), outline=OUTLINE, width=int(1.2 * u))

    # Cabeza, adelantada hacia el frente
    d.ellipse([c - 4 * u, c - 6.5 * u, c + 9 * u, c + 6.5 * u],
              fill=_shade(color, 1.0), outline=OUTLINE, width=int(1.6 * u))

    # Brillo especular arriba-izquierda: da volumen
    d.ellipse([c - 1 * u, c - 4.5 * u, c + 3 * u, c - 1 * u],
              fill=_shade(color, 1.35))

    _finish(img, size, f"actor_{name}.png")


def wall(size: int = 32) -> None:
    img, d = _canvas(size)
    u = size * SS / 32
    d.rectangle([0, 0, size * SS, size * SS], fill=(84, 78, 102, 255))
    d.rectangle([0, 0, size * SS, size * SS], outline=(56, 52, 70, 255),
                width=int(2 * u))
    # Ladrillos alternos
    for row in range(4):
        y = row * 8 * u
        offset = 0 if row % 2 == 0 else 8 * u
        d.line([0, y, size * SS, y], fill=(64, 60, 80, 255), width=int(1.5 * u))
        for col in range(3):
            x = offset + col * 16 * u
            if x < size * SS:
                d.line([x, y, x, y + 8 * u], fill=(64, 60, 80, 255),
                       width=int(1.5 * u))
    # Luz cenital en el borde superior
    d.rectangle([0, 0, size * SS, 3 * u], fill=(104, 98, 124, 255))
    _finish(img, size, "wall.png")


def floor_tile(size: int = 32) -> None:
    img, d = _canvas(size)
    u = size * SS / 32
    d.rectangle([0, 0, size * SS, size * SS], fill=(38, 35, 48, 255))
    rng = random.Random(7)
    # Grano sutil: evita que las zonas grandes se vean planas
    for _ in range(90):
        x = rng.uniform(0, size * SS)
        y = rng.uniform(0, size * SS)
        v = rng.randint(-6, 8)
        d.ellipse([x, y, x + 2 * u, y + 2 * u],
                  fill=(38 + v, 35 + v, 48 + v, 255))
    d.line([0, 0, size * SS, 0], fill=(46, 43, 58, 255), width=int(1 * u))
    d.line([0, 0, 0, size * SS], fill=(46, 43, 58, 255), width=int(1 * u))
    _finish(img, size, "floor.png")


def spike(size: int = 32) -> None:
    img, d = _canvas(size)
    c = size * SS / 2
    u = size * SS / 32
    d.rounded_rectangle([2 * u, 2 * u, 30 * u, 30 * u], radius=3 * u,
                        fill=(28, 20, 26, 255), outline=(58, 44, 54, 255),
                        width=int(1.5 * u))
    # Cuatro puas metalicas en diagonal
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        tip_x, tip_y = c + dx * 10 * u, c + dy * 10 * u
        d.polygon([(tip_x, tip_y),
                   (c + dx * 2 * u, c + dy * 5.5 * u),
                   (c + dx * 5.5 * u, c + dy * 2 * u)],
                  fill=(206, 208, 224, 255), outline=(148, 150, 168, 255))
    d.ellipse([c - 3 * u, c - 3 * u, c + 3 * u, c + 3 * u],
              fill=(176, 60, 60, 255))
    _finish(img, size, "spike.png")


def potion(size: int = 16) -> None:
    img, d = _canvas(size)
    u = size * SS / 16
    # Frasco
    d.rounded_rectangle([4 * u, 5 * u, 12 * u, 14 * u], radius=3 * u,
                        fill=(70, 226, 128, 255), outline=OUTLINE,
                        width=int(1.2 * u))
    # Cuello y tapon
    d.rectangle([6.5 * u, 2.5 * u, 9.5 * u, 6 * u], fill=(70, 226, 128, 255),
                outline=OUTLINE, width=int(1.2 * u))
    d.rounded_rectangle([5.5 * u, 1 * u, 10.5 * u, 3.5 * u], radius=1 * u,
                        fill=(180, 140, 90, 255), outline=OUTLINE,
                        width=int(1.2 * u))
    # Reflejo
    d.ellipse([5.5 * u, 7 * u, 7.5 * u, 10 * u], fill=(200, 255, 220, 220))
    _finish(img, size, "potion.png")


def bullet(name: str, color: tuple[int, int, int], size: int = 8) -> None:
    img, d = _canvas(size)
    c = size * SS / 2
    u = size * SS / 8
    # Estela hacia atras (-X): se lee la direccion del proyectil
    d.ellipse([c - 4 * u, c - 1.2 * u, c + 1 * u, c + 1.2 * u],
              fill=(*color, 90))
    d.ellipse([c - 1.8 * u, c - 1.8 * u, c + 2.2 * u, c + 1.8 * u],
              fill=(*color, 255))
    d.ellipse([c - 0.6 * u, c - 0.9 * u, c + 1.4 * u, c + 0.9 * u],
              fill=(255, 255, 255, 230))
    _finish(img, size, f"bullet_{name}.png")


def muzzle_flash(size: int = 16) -> None:
    img, d = _canvas(size)
    c = size * SS / 2
    u = size * SS / 16
    d.polygon([(c + 7 * u, c), (c - 2 * u, c - 4 * u), (c - 2 * u, c + 4 * u)],
              fill=(255, 236, 160, 255))
    d.polygon([(c + 4 * u, c), (c - 1 * u, c - 2 * u), (c - 1 * u, c + 2 * u)],
              fill=(255, 255, 240, 255))
    img = img.filter(ImageFilter.GaussianBlur(radius=1.2 * SS))
    _finish(img, size, "muzzle_flash.png")


def main() -> None:
    print("Generando sprites en", OUT_DIR)
    for key, color in COLORS.items():
        actor(key, color)
    wall()
    floor_tile()
    spike()
    potion()
    bullet("player", (255, 226, 120))
    bullet("enemy", (255, 130, 110))
    muzzle_flash()
    print("Listo. Godot los importa solo al abrir el editor.")


if __name__ == "__main__":
    main()
