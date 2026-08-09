class_name Fitness
extends RefCounted
## Funcion de rendimiento del agente.
##
## El PDF (seccion 3.2) deja la recompensa "definida de forma arbitraria" pero
## exige documentar los pesos elegidos. Estos son, y estos son los porques.
##
## NOTA DE DISENO (importante, salio de medir):
## La primera version pesaba el tiempo de vida a +0.015/tick. Con episodios de
## 1800 ticks, un agente que no hacia absolutamente nada puntuaba 27.00, y como
## pelear arriesga dano (-0.6/punto) y muerte (-30), la poblacion entera
## convergia a agentes-estatua: en el log de entrenamiento se veia
## "mejor=27.00 medio=27.00" durante etapas enteras, es decir, cero presion
## selectiva. Sobrevivir sin combatir era el optimo local, y el GA lo encontro.
##
## La correccion tiene tres partes:
##   1. Bajar mucho el premio por sobrevivir (0.015 -> 0.004).
##   2. Anadir W_TICK_ENGAGED: premiar ESTAR en rango de combate. Es el termino
##      de shaping que da gradiente en las primeras generaciones, cuando ningun
##      individuo consigue hacer dano todavia y sin el todos los fitness serian
##      identicos.
##   3. Penalizar el empate por tiempo agotado, para que dejar correr el reloj
##      deje de ser una salida comoda.
##
## SEGUNDO AJUSTE (tambien medido):
## Con la correccion anterior el agente seguia clavado en el valor pasivo
## (-4.80) contra el Tipo B y contra el bot. El motivo: acercarse a una torreta
## cuesta ~85 de dano, y con W_DAMAGE_TAKEN=-0.6 y W_DEATH=-30 eso son -81
## puntos frente a los +18 del acercamiento. Esconderse seguia siendo optimo.
##
## Se bajo el castigo defensivo (dano recibido -0.6 -> -0.25, muerte -30 -> -15)
## y se subio el premio por combatir (0.020 -> 0.030). El resultado buscado es
## esta jerarquia, que es la que hace que el GA explore:
##   esconderse            ~ -7.8   (peor opcion)
##   acercarse y morir     ~ -5.7   (ligeramente mejor que esconderse)
##   acercarse y hacer dano  positivo y creciente
##   matar                 +60 y +40 de victoria (domina todo lo demas)
## Castigar mas la muerte produce agentes cobardes; castigarla menos produce
## agentes suicidas. Estos valores son un punto de partida razonable, no un
## optimo: ajustarlos es parte del trabajo experimental del informe.
##
## Desglose de pesos:
##  DAMAGE_DEALT  (+1.0/punto)   Senal principal. Es la unica forma de ganar.
##  DAMAGE_TAKEN  (-0.6/punto)   Menor que el dano hecho a proposito: si
##                               castigara igual o mas, huir seria optimo.
##  DAMAGE_BLOCKED(+0.35/punto)  El "esquivar/evitar dano" del PDF. Por debajo
##                               de lo que cuesta recibir el golpe, para que
##                               bloquear no sea mejor que no ser alcanzado.
##  KILL          (+60.0)        Bono discreto grande: define la meta.
##  DEATH         (-30.0)        Morir duele, pero menos que matar recompensa, o
##                               el agente no arriesgaria nunca.
##  TICK_ALIVE    (+0.004/tick)  Sobrevivir 30 s vale ~7 puntos: gradiente
##                               minimo, no una estrategia.
##  TICK_ENGAGED  (+0.020/tick)  Estar en rango de combate vale 5x sobrevivir.
##                               Empuja a buscar pelea desde la generacion 1.
##  POTION_USED   (+8.0)         Empuja a descubrir la mecanica de curacion.
##  IDLE_TICK     (-0.004/tick)  Castiga los ticks sin accion (thresholding por
##                               umbral). Evita el agente-estatua.
##  VICTORY       (+40.0)        Bono por dejar el campo sin oponentes vivos.
##  DRAW          (-12.0)        Empate por tiempo agotado.

const W_DAMAGE_DEALT := 1.0
const W_DAMAGE_TAKEN := -0.25
const W_DAMAGE_BLOCKED := 0.35
const W_KILL := 60.0
const W_DEATH := -15.0
const W_TICK_ALIVE := 0.004
const W_TICK_ENGAGED := 0.030
const W_POTION_USED := 8.0
const W_IDLE_TICK := -0.004
const W_VICTORY := 40.0
const W_DRAW := -15.0

## Distancia a la que se considera que el actor esta "en combate".
const ENGAGE_RANGE := 210.0


static func evaluate(agent: Actor, victory: bool, draw: bool = false,
		idle_ticks: int = 0) -> float:
	var score := 0.0
	score += agent.damage_dealt * W_DAMAGE_DEALT
	score += agent.damage_taken * W_DAMAGE_TAKEN
	score += agent.damage_blocked * W_DAMAGE_BLOCKED
	score += float(agent.kills) * W_KILL
	score += float(agent.deaths) * W_DEATH
	score += float(agent.ticks_alive) * W_TICK_ALIVE
	score += float(agent.ticks_engaged) * W_TICK_ENGAGED
	score += float(agent.potions_used) * W_POTION_USED
	score += float(idle_ticks) * W_IDLE_TICK
	if victory:
		score += W_VICTORY
	if draw:
		score += W_DRAW
	return score


## Desglose termino a termino, para poder mostrar en el informe de que se
## compone el fitness de un agente y no solo el numero final.
static func breakdown(agent: Actor, victory: bool, draw: bool = false,
		idle_ticks: int = 0) -> Dictionary:
	return {
		"dano_hecho": agent.damage_dealt * W_DAMAGE_DEALT,
		"dano_recibido": agent.damage_taken * W_DAMAGE_TAKEN,
		"dano_bloqueado": agent.damage_blocked * W_DAMAGE_BLOCKED,
		"kills": float(agent.kills) * W_KILL,
		"muertes": float(agent.deaths) * W_DEATH,
		"tiempo_vida": float(agent.ticks_alive) * W_TICK_ALIVE,
		"en_combate": float(agent.ticks_engaged) * W_TICK_ENGAGED,
		"pociones": float(agent.potions_used) * W_POTION_USED,
		"inactividad": float(idle_ticks) * W_IDLE_TICK,
		"victoria": W_VICTORY if victory else 0.0,
		"empate": W_DRAW if draw else 0.0,
		"total": evaluate(agent, victory, draw, idle_ticks),
	}
