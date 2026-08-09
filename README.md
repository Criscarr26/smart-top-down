# Smart Top Down

Juego top-down 2D estilo *Hotline Miami* con enemigos por máquina de estado finito, pathfinding A\*, y un enemigo entrenado por red neuronal optimizada con algoritmos genéticos.

Introducción a la IA — Juegos Inteligentes 2026-C1, ITLA · Prof. Carlos B. Ogando M. · Godot 4.7.1

## Estructura

```
game/      todo el código (.gd) y las escenas (.tscn)
assets/    sprites y sonidos (generados por tools/)
tools/     scripts de Python: generar assets y analizar resultados
results/   salida del benchmark
```

## Jugar

Abre `project.godot` en Godot y pulsa `F5`. Arranca en el menú principal, que muestra los controles, describe los cuatro enemigos y deja elegir entre los tres niveles.

| Control | Acción |
|---|---|
| `WASD` | Mover |
| Click izq. / der. | Melee / disparo (hacia el ratón) |
| `Shift` | Defender (inmoviliza, gasta escudo) |
| `Q` | Usar poción |
| `R` | Reiniciar |
| `F1` | Ver estados de la FSM, radios y líneas de visión |
| `Esc` | Volver al menú |

## Benchmark

```bash
cmd /c run_benchmark.bat
```

Entrena y evalúa los 10 escenarios sobre la matriz de configuraciones. Escribe a `results/`:
`benchmark.xlsx` (4 hojas), `benchmark.csv`, `benchmark.json`, `benchmark_cualitativo.md`,
más `convergencia_*.json` y `genoma_*.json` por configuración.

Progreso: `Get-Content results\barrido.log -Tail 20`. Termina con `TERMINADO_CON_CODIGO_0`.

Opciones (tras `--`): `--repeats N`, `--parallel N`, `--speed N`, `--generations N`,
`--population N`, `--seed N`, `--out RUTA`, `--quick`, `--only-eval`.

Gráficas y tablas adicionales:

```bash
pip install pandas matplotlib tabulate
python tools/analyze_results.py
```

## Assets

Originales, generados por código (sin descargas ni dudas de licencia):

```bash
python tools/generate_sprites.py
python tools/generate_sfx.py
```

Para sustituirlos por otros mejores, deja los archivos con el **mismo nombre** en `assets/`.
Gratis y sin atribución obligatoria: [kenney.nl/assets](https://kenney.nl/assets) (CC0) y
[sfxr.me](https://sfxr.me). Con atribución: [freesound.org](https://freesound.org),
[opengameart.org](https://opengameart.org), [itch.io](https://itch.io/game-assets/free).

## Decisiones que condicionan el resto

1. **La simulación no usa el `delta` del motor.** Todo avanza con `SIM_DT` fijo y contadores de ticks; los actores usan `move_and_collide()`, no `move_and_slide()`. Sin esto, acelerar el benchmark cambiaría los resultados.
2. **Se acelera subiendo `physics_ticks_per_second`, no `Engine.time_scale`.** Medido: `time_scale = 40` da una aceleración real de x1.2.
3. **Cada arena tiene su propio `World2D` y su propio RNG.** Es lo que permite correr episodios en paralelo sin que se contaminen ni pierdan reproducibilidad.
4. **Los tres tipos de enemigo son un solo script** (`enemy.gd` + `EnemyProfile`). El perfil decide qué estados se registran.
5. **Las púas son sólidas en el grid de A\* pero no en la física.** Quien planifica ruta las esquiva; quien va en línea recta muere en ellas.

## Limitaciones

- Los escenarios "vs jugador humano" (4 y 10) usan un bot sustituto; un humano no cabe en un barrido automatizado. Repórtalos como oponente **simulado** y compleméntalos con partidas manuales.
- El barrido es OFAT (una variable a la vez), no factorial completo: mide efectos marginales, no interacciones.
- El paralelismo es de simulación, no de CPU. Para usar varios núcleos, lanza varios procesos con distinta `--seed` y `--out`.
- El agente recibe distancia y ángulo al objetivo aunque no lo vea; la oclusión va aparte en el sensor de línea de visión.
