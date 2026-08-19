# Benchmark cualitativo del agente entrenado

Generado automaticamente a partir de 1040 corridas registradas.

## Resumen por escenario

| Escenario | Corridas | Victorias agente | Vida agente (s) | DPS agente | Tasa de exito |
|---|---|---|---|---|---|
| Un enemigo tipo A vs 1 agente | 80 | 56% | 10.6 | 8.5 | 0.19 |
| Un enemigo tipo B vs 1 agente | 80 | 69% | 24.9 | 5.7 | 0.69 |
| Un enemigo tipo C vs 1 agente | 80 | 94% | 8.5 | 6.6 | 0.19 |
| Un jugador humano (bot) vs 1 agente | 80 | 25% | 14.1 | 5.1 | 0.25 |
| Varios enemigos tipo A vs 1 agente | 80 | 0% | 2.3 | 16.8 | 0.00 |
| Varios enemigos tipo B vs 1 agente | 80 | 25% | 40.6 | 5.3 | 0.52 |
| Varios enemigos tipo C vs 1 agente | 80 | 6% | 11.8 | 10.0 | 0.10 |
| Varios de todos los enemigos vs 1 agente | 80 | 0% | 1.8 | 18.2 | 0.00 |
| Varios de todos los enemigos vs varios agentes | 80 | 6% | 10.0 | 26.9 | 0.18 |
| Un jugador humano (bot) vs varios agentes | 80 | 38% | 21.9 | 5.1 | 0.19 |
| Un enemigo tipo D (sanador) vs 1 agente | 80 | 94% | 13.9 | 8.2 | 0.63 |
| Dos tipo A escoltados por un sanador vs 1 agente | 80 | 0% | 3.1 | 15.1 | 0.02 |
| Uno de cada tipo, sanador incluido, vs 1 agente | 80 | 0% | 2.4 | 16.5 | 0.01 |

## Observaciones

- El agente huyo mas del Tipo A (3%) que del Tipo C (2%), lo que sugiere que aprendio a evitar el combate cuerpo a cuerpo.
- El agente apenas uso la defensa contra el Tipo B (0%): prefirio cerrar distancia antes que bloquear proyectiles.
- AVISO en "Un enemigo tipo A vs 1 agente": el agente gana el 56% de las partidas pero solo mata 0.19 oponentes de media (hace 8.5 de dano por segundo, o sea que pega pero no remata). Esas victorias NO son suyas: los oponentes mueren en las puas del nivel. No interpretar esta fila como desempeno del agente.
- AVISO en "Un enemigo tipo C vs 1 agente": el agente gana el 94% de las partidas pero solo mata 0.19 oponentes de media (hace 6.6 de dano por segundo, o sea que pega pero no remata). Esas victorias NO son suyas: los oponentes mueren en las puas del nivel. No interpretar esta fila como desempeno del agente.
- La tasa de exito cae de 0.35 en los duelos 1v1 a 0.21 contra varios oponentes, que es la prueba de estres que pide la seccion 3.3.2 del PDF.
- Con varios agentes contra el grupo mixto la tasa de exito mejora (0.18 vs 0.00 con un solo agente).
- El escenario mas duro fue "Varios de todos los enemigos vs 1 agente": 0% de victorias y el agente aguanta solo 1.8 s de media. Hay 4 escenarios empatados a ese 0% de victorias; se desempata por tiempo de vida.

## Limitaciones conocidas

- Los escenarios con "jugador humano" (s04_humano_1v1, s10_humano_varios) se corrieron contra el bot sustituto `ScriptedBot`, no contra una persona. Un humano no puede meterse en un barrido automatizado de miles de partidas. Estos resultados miden al agente frente a un oponente HUMANO-SIMULADO de reglas fijas y deben reportarse como tales; complementarlos con partidas manuales contra humano real.
- El barrido de variables es OFAT (una variable a la vez desde una configuracion base), no factorial completo. Mide efectos marginales; no detecta interacciones entre variables.
- El agente recibe distancia y angulo al objetivo aunque no lo vea; la oclusion va aparte en el sensor de linea de vision. Es la lista de sensores que fija el PDF, pero implica que el agente no tiene que resolver busqueda con informacion parcial.
