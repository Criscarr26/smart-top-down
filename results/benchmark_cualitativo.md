# Benchmark cualitativo del agente entrenado

Generado automaticamente a partir de 800 corridas registradas.

## Resumen por escenario

| Escenario | Corridas | Victorias agente | Vida agente (s) | DPS agente | Tasa de exito |
|---|---|---|---|---|---|
| Un enemigo tipo A vs 1 agente | 80 | 63% | 12.0 | 4.0 | 0.00 |
| Un enemigo tipo B vs 1 agente | 80 | 69% | 22.4 | 5.6 | 0.69 |
| Un enemigo tipo C vs 1 agente | 80 | 81% | 12.1 | 4.1 | 0.13 |
| Un jugador humano (bot) vs 1 agente | 80 | 31% | 16.9 | 4.6 | 0.25 |
| Varios enemigos tipo A vs 1 agente | 80 | 0% | 3.2 | 12.8 | 0.00 |
| Varios enemigos tipo B vs 1 agente | 80 | 6% | 40.8 | 2.6 | 0.21 |
| Varios enemigos tipo C vs 1 agente | 80 | 0% | 7.3 | 6.6 | 0.02 |
| Varios de todos los enemigos vs 1 agente | 80 | 0% | 2.6 | 11.6 | 0.00 |
| Varios de todos los enemigos vs varios agentes | 80 | 13% | 12.1 | 16.9 | 0.21 |
| Un jugador humano (bot) vs varios agentes | 80 | 50% | 24.2 | 8.0 | 0.50 |

## Observaciones

- El agente huyo mas del Tipo A (0%) que del Tipo C (0%), lo que sugiere que aprendio a evitar el combate cuerpo a cuerpo.
- El agente apenas uso la defensa contra el Tipo B (15%): prefirio cerrar distancia antes que bloquear proyectiles.
- La tasa de exito cae de 0.27 en los duelos 1v1 a 0.08 contra varios oponentes, que es la prueba de estres que pide la seccion 3.3.2 del PDF.
- Con varios agentes contra el grupo mixto la tasa de exito mejora (0.21 vs 0.00 con un solo agente).
- El escenario mas duro fue "Varios enemigos tipo A vs 1 agente", con 0% de victorias del agente.

## Limitaciones conocidas

- Los escenarios con "jugador humano" (s04_humano_1v1, s10_humano_varios) se corrieron contra el bot sustituto `ScriptedBot`, no contra una persona. Un humano no puede meterse en un barrido automatizado de miles de partidas. Estos resultados miden al agente frente a un oponente HUMANO-SIMULADO de reglas fijas y deben reportarse como tales; complementarlos con partidas manuales contra humano real.
- El barrido de variables es OFAT (una variable a la vez desde una configuracion base), no factorial completo. Mide efectos marginales; no detecta interacciones entre variables.
