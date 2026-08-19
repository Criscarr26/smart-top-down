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

Abre `project.godot` en Godot y pulsa `F5`. Arranca en el menú principal, con pestañas para jugar, entrenar, ver récords y consultar los controles.

| Control | Acción |
|---|---|
| `↑ ↓ ← →` | Mover |
| Ratón | Apuntar (el cuerpo va a un lado y el arma a otro) |
| Click izq. / der. | Melee / disparo |
| `Espacio` | Impulso: x3,2 durante 0,17 s, recarga 1,2 s |
| `Shift` | Defender (inmoviliza, gasta escudo) |
| `Q` | Usar poción |
| `R` | Reiniciar |
| `F1` | Ver estados de la FSM, radios y líneas de visión |
| `Esc` | Pausa |

### Modo oleadas

Los enemigos llegan en tandas que crecen. Las cinco primeras están escritas a mano y cada una introduce **un** concepto: perseguidores (moverse y golpear) → torreta (usar las paredes) → kiter (acorralar en vez de perseguir) → sanador (priorizar objetivos) → todos juntos. De la sexta en adelante la composición sale de una fórmula acotada a 12 enemigos simultáneos, así que el modo no tiene final artificial.

**Puntuación con cadena.** Encadenar bajas dentro de una ventana de 3 segundos multiplica los puntos hasta x3,8. Sin eso, la estrategia óptima sería esconderse tras una esquina y matar de uno en uno; con la ventana, hay que avanzar hacia el siguiente mientras todavía te disparan. Es la misma idea que la función de fitness del agente: **la recompensa define el juego que se acaba jugando**. Bonus por oleada sin recibir daño y por precisión de melee. Los récords se guardan por nivel en `user://perfil.json`.

En pantalla: barras de salud, escudo y recarga del impulso, contador de oleada, cronómetro y **minimapa** con paredes, púas, pociones y actores.

## Los cuatro enemigos

Los cuatro tipos son **el mismo script** (`enemy.gd`) con distinto `EnemyProfile`: el perfil decide qué estados se registran en la FSM y con qué umbrales. Añadir un tipo es escribir otra factoría, no otra clase.

| Tipo | Comportamiento | Por qué existe |
|---|---|---|
| A | Persigue y golpea. **Pesado**: se pasa de frenada | Ese sobrepaso es la ventana para rodearlo |
| B | Torreta: no se mueve, dispara, levanta la guardia | Obliga a usar las paredes como cobertura |
| C | Kiter: dispara, huye, contraataca a quemarropa. **Ligero** | Cambia de sentido en seco: cuesta acorralarlo |
| D | Sanador: cura aliados heridos, huye si lo presionan | **Cambia el orden en que conviene matar** |

El Tipo D es el único que altera la decisión táctica: mientras viva, el daño hecho a los demás se deshace. Es profundidad sin añadir ni una mecánica de combate nueva.

## Entrenar al agente

Menú → **ENTRENAR** → *Abrir el laboratorio*. Pantalla completa, tres columnas.

**Izquierda — configuración.** Se edita en caliente, sin tocar código:
- **Función de fitness**: los 11 pesos más el radio de combate. Es *la heurística*: cambiarla cambia el problema, no solo la búsqueda.
- **Algoritmo genético**: las ocho variables del §3.3.4.c más la topología de la red.
- **Corrida**: qué etapas del currículum, duración del episodio, arenas en paralelo, aceleración y semilla.

**Centro — la arena de verdad, dibujándose.** Con **la IA hecha visible** encima del agente:
- los 7 sensores con su valor normalizado en tiempo real;
- las 6 salidas de la red como probabilidades, con la elegida marcada — la decisión, no solo el resultado;
- la ruta A\* que está siguiendo y por dónde ha pasado;
- un anillo que pulsa al ritmo de las decisiones (una cada 6 ticks).

Cada capa se enciende y apaga por separado. El botón **Ventana aparte** abre la arena como ventana independiente del sistema operativo, redimensionable y llevable a otro monitor.

**Derecha — métricas reales.** Generación, etapa, episodios, pasos simulados, fitness mejor/medio, mejor histórico y dónde se dio, tasa de éxito, bajas, tiempo efectivo (descontando pausas), episodios por segundo y estado (Listo / Entrenando / Pausado / Evaluando / Completado / Detenido). Más dos gráficas — fitness y tasa de victoria por generación, con marca vertical en cada cambio de etapa — y el reparto de acciones del agente.

Ninguna cifra es decorativa: todas salen de `TrainingMetrics`, que solo acumula episodios que ocurrieron.

**Evaluar** corre los 13 escenarios con el agente entrenado, en el nivel de validación y con las mismas semillas y repeticiones que el barrido, y saca la tabla por escenario. Es lo que convierte «el fitness subió» en «gana o no gana». También se guarda en `user://evaluacion_agente.csv`.

El agente entrenado se guarda en `user://genoma_entrenado.json` junto con los pesos, la configuración y la curva que lo produjeron, y **los niveles lo cargan con prioridad** sobre el que trae el proyecto.

### Cómo saber que entrenó bien

| Lo que ves en la curva | Qué significa |
|---|---|
| Verde sube y azul la sigue por debajo | **Sano**: hay presión selectiva y la población consolida |
| Verde y azul pegadas y planas | **Roto**: cero presión selectiva (el agente-estatua) |
| Dientes de sierra | **Normal**: cada generación rota el nivel y usa semillas nuevas |
| Salto en las marcas naranjas | **Normal**: cambia la etapa y el rival |

El entrenamiento usa `level_01/02/03`; la evaluación corre en `validation`, un nivel que el agente **nunca vio**. Si rindiera bien entrenando y mal evaluando, estaría memorizando geometría en vez de aprendiendo a pelear.

## Benchmark

```bash
cmd /c run_benchmark.bat
```

Entrena y evalúa los 13 escenarios sobre la matriz de 16 configuraciones (OFAT: una variable a la vez). Escribe a `results/`: `benchmark.xlsx` (5 hojas), `benchmark.csv`, `benchmark.json`, `benchmark_cualitativo.md`, más `convergencia_*.json` y `genoma_*.json` por configuración.

Progreso: `Get-Content results\barrido.log -Tail 20`. Termina con `TERMINADO_CON_CODIGO_0`.

Opciones (tras `--`): `--repeats N`, `--parallel N`, `--speed N`, `--generations N`, `--population N`, `--seed N`, `--out RUTA`, `--quick`, `--only-eval`, `--rebuild-xlsx`.

`--only-eval` evalúa **sin entrenar**, con pesos aleatorios: es el grupo de control contra el que comparar.

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
2. **Se acelera subiendo `physics_ticks_per_second`, no `Engine.time_scale`.** Medido: `time_scale = 40` da una aceleración real de x1.2. Como corolario, la aceleración se puede mover **en mitad de una corrida** sin alterar nada.
3. **Cada arena tiene su propio `World2D` y su propio RNG.** Es lo que permite correr episodios en paralelo sin que se contaminen ni pierdan reproducibilidad.
4. **Los cuatro tipos de enemigo son un solo script** (`enemy.gd` + `EnemyProfile`). El perfil decide qué estados se registran.
5. **Las púas son sólidas en el grid de A\* pero no en la física.** Quien planifica ruta las esquiva; quien va en línea recta muere en ellas.
6. **El movimiento tiene inercia.** `move_in_direction()` acelera hacia la velocidad objetivo en vez de asignarla, y al chocar la velocidad se proyecta sobre la pared. Con asignación directa el control era perfecto y por eso mismo no había nada que dominar: esquivar era apretar la tecla contraria.
7. **Dibujar una arena no la altera.** El modo interactivo solo enciende sprites, `_process` y `_draw`; verificado midiendo que el mismo episodio da resultado idéntico con la ranura visible y sin ella. Por eso el individuo que cae en la ranura observada no compite en condiciones distintas.

## Arquitectura

Tres capas que no se conocen entre sí más de lo necesario:

- **Simulación** — `Arena`, `Actor`, `SimPool`. Determinista, sin interfaz, compartida por el juego y el benchmark.
- **Decisión** — FSM (`StateMachine` + estados) para los enemigos; `NeuralNetwork` + `Thresholding` para el agente. Ambas producen una intención; `PathfindingComponent` la convierte en movimiento.
- **Presentación** — `UI` (paleta y fábricas), `Effects`, `Chart`, `ArenaView`, `AgentOverlay`, HUD. Nada de aquí existe durante el barrido.

`UI` es la única fuente de colores, tipografías y controles: antes cada pantalla declaraba su propia paleta y ajustar un color eran tres ediciones.

## Limitaciones

- Los escenarios "vs jugador humano" (4 y 10) usan un bot sustituto; un humano no cabe en un barrido automatizado. Repórtalos como oponente **simulado** y compleméntalos con partidas manuales.
- El barrido es OFAT (una variable a la vez), no factorial completo: mide efectos marginales, no interacciones.
- El paralelismo es de simulación, no de CPU. Para usar varios núcleos, lanza varios procesos con distinta `--seed` y `--out`.
- El agente recibe distancia y ángulo al objetivo aunque no lo vea; la oclusión va aparte en el sensor de línea de visión.
- El agente **no tiene un sensor específico del sanador**: lo percibe como un objetivo más. Los escenarios s11–s13 miden si aun así aprende a priorizarlo, no dan por hecho que pueda.
