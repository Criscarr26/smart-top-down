#!/usr/bin/env python3
"""Genera los efectos de sonido del juego por sintesis, a assets/audio/*.wav

Por que generarlos en vez de descargarlos:
  - No dependen de ninguna descarga ni de una conexion; el proyecto se clona y
    suena.
  - No hay duda de licencia ni de atribucion, cosa que importa con la clausula
    de honestidad academica del PDF: son 100% originales y este script es la
    prueba de como se hicieron.
  - Son regenerables y ajustables: cambia un numero y vuelve a correr.

Solo usa la biblioteca estandar (wave, struct, math, random). No hace falta
instalar nada.

Uso:
    python tools/generate_sfx.py
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio"


# --- Bloques basicos ---------------------------------------------------------

def _n(duration: float) -> int:
    return int(SAMPLE_RATE * duration)


def square(freq_start: float, freq_end: float, duration: float,
           duty: float = 0.5) -> list[float]:
    """Onda cuadrada con barrido de frecuencia. El timbre 8-bit clasico."""
    out = []
    phase = 0.0
    total = _n(duration)
    for i in range(total):
        t = i / total
        freq = freq_start + (freq_end - freq_start) * t
        phase += freq / SAMPLE_RATE
        out.append(1.0 if (phase % 1.0) < duty else -1.0)
    return out


def sine(freq_start: float, freq_end: float, duration: float) -> list[float]:
    out = []
    phase = 0.0
    total = _n(duration)
    for i in range(total):
        t = i / total
        freq = freq_start + (freq_end - freq_start) * t
        phase += freq / SAMPLE_RATE
        out.append(math.sin(phase * 2.0 * math.pi))
    return out


def noise(duration: float, rng: random.Random) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(_n(duration))]


def lowpass(samples: list[float], alpha: float) -> list[float]:
    """Filtro paso bajo de un polo. Quita el brillo del ruido blanco."""
    out = []
    prev = 0.0
    for s in samples:
        prev = prev + alpha * (s - prev)
        out.append(prev)
    return out


def envelope(samples: list[float], attack: float = 0.005,
             decay: float = 0.0, power: float = 1.0) -> list[float]:
    """Ataque lineal + caida exponencial. `power` > 1 acorta la cola."""
    total = len(samples)
    a = max(1, int(SAMPLE_RATE * attack))
    out = []
    for i, s in enumerate(samples):
        if i < a:
            gain = i / a
        else:
            rest = (i - a) / max(1, total - a)
            gain = (1.0 - rest) ** power
        out.append(s * gain)
    if decay:  # silencio de cola para que no chasquee al cortar
        for i in range(min(len(out), _n(decay))):
            out[-1 - i] *= i / max(1, _n(decay))
    return out


def mix(*tracks: list[float]) -> list[float]:
    length = max(len(t) for t in tracks)
    out = [0.0] * length
    for track in tracks:
        for i, s in enumerate(track):
            out[i] += s
    return out


def gain(samples: list[float], g: float) -> list[float]:
    return [s * g for s in samples]


def write_wav(name: str, samples: list[float]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    # Normaliza a -3 dBFS: deja aire para que varios sonidos a la vez no saturen.
    scale = 0.707 / peak
    path = OUT_DIR / name
    with wave.open(str(path), "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
            for s in samples
        )
        f.writeframes(frames)
    print(f"  {path.name}  ({len(samples)/SAMPLE_RATE:.2f}s)")


# --- Los sonidos del juego ---------------------------------------------------

def build_all() -> None:
    rng = random.Random(20260408)  # semilla fija: mismos WAV en cada corrida

    print("Generando efectos en", OUT_DIR)

    # Disparo del jugador: barrido descendente, brillante.
    write_wav("shoot_player.wav",
              envelope(square(880, 180, 0.14, duty=0.35), power=2.5))

    # Disparo enemigo: mas grave, para distinguirlo de oido en pleno combate.
    write_wav("shoot_enemy.wav",
              envelope(square(520, 120, 0.16, duty=0.5), power=2.2))

    # Melee: golpe de aire. Ruido filtrado con caida rapida.
    write_wav("melee.wav",
              envelope(lowpass(noise(0.13, rng), 0.22), attack=0.002, power=3.0))

    # Impacto: capa grave de cuerpo + capa de ruido corta.
    write_wav("hit.wav", mix(
        gain(envelope(sine(220, 70, 0.12), power=3.0), 0.8),
        gain(envelope(lowpass(noise(0.07, rng), 0.5), power=4.0), 0.5),
    ))

    # Muerte: caida larga y grave.
    write_wav("death.wav", mix(
        gain(envelope(square(300, 40, 0.5, duty=0.3), power=1.6), 0.7),
        gain(envelope(lowpass(noise(0.45, rng), 0.12), power=2.0), 0.6),
    ))

    # Pocion: arpegio ascendente de tres notas (do-mi-sol).
    potion: list[float] = []
    for freq in (523.25, 659.25, 783.99):
        potion += envelope(sine(freq, freq, 0.09), attack=0.004, power=2.0)
    write_wav("potion.wav", potion)

    # Escudo bloqueando: ping metalico con dos parciales inarmonicos.
    write_wav("shield_hit.wav", mix(
        gain(envelope(sine(1200, 900, 0.12), power=3.0), 0.6),
        gain(envelope(sine(1830, 1400, 0.12), power=4.0), 0.4),
    ))

    # Escudo roto: estallido de ruido con cola.
    write_wav("shield_break.wav", mix(
        gain(envelope(lowpass(noise(0.35, rng), 0.65), power=1.8), 0.9),
        gain(envelope(square(700, 90, 0.3, duty=0.2), power=2.2), 0.5),
    ))

    # Pua: estocada seca y aguda.
    write_wav("spike.wav", mix(
        gain(envelope(square(1400, 200, 0.18, duty=0.15), power=3.0), 0.8),
        gain(envelope(lowpass(noise(0.12, rng), 0.8), power=3.5), 0.6),
    ))

    # Enemigo te detecta: blip ascendente corto. Da la senal de lectura que
    # necesita un top-down rapido: sabes que te vieron sin mirar la pantalla.
    write_wav("alert.wav",
              envelope(square(400, 900, 0.10, duty=0.5), attack=0.003, power=2.0))

    print("Listo. Reimportalos en Godot (se detectan solos al abrir el editor).")


if __name__ == "__main__":
    build_all()
