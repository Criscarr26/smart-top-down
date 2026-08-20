class_name Fitness
extends RefCounted
## Funcion de rendimiento del agente.
##
## La recompensa es una eleccion de diseno, no una verdad. Lo unico que no es
## opcional es documentar por que vale lo que vale cada peso. Aqui estan.
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
## optimo: ajustarlos es parte del trabajo experimental del informe, y para eso
## esta la pantalla "Entrenar agente" del menu, que los edita en caliente.
##
## Desglose de los 11 pesos:
##  DAMAGE_DEALT  (+1.0/punto)   Senal principal. Es la unica forma de ganar.
##  DAMAGE_TAKEN  (-0.25/punto)  Menor que el dano hecho a proposito: si
##                               castigara igual o mas, huir seria optimo.
##  DAMAGE_BLOCKED(+0.35/punto)  El "esquivar/evitar dano". Por debajo
##                               de lo que cuesta recibir el golpe, para que
##                               bloquear no sea mejor que no ser alcanzado.
##  KILL          (+60.0)        Bono discreto grande: define la meta.
##  DEATH         (-15.0)        Morir duele, pero mucho menos que matar
##                               recompensa, o el agente no arriesgaria nunca.
##  TICK_ALIVE    (+0.004/tick)  Sobrevivir 30 s vale ~7 puntos: gradiente
##                               minimo, no una estrategia.
##  TICK_ENGAGED  (+0.030/tick)  Estar en rango de combate vale 7.5x sobrevivir.
##                               Empuja a buscar pelea desde la generacion 1.
##  POTION_USED   (+8.0)         Empuja a descubrir la mecanica de curacion.
##  IDLE_TICK     (-0.004/tick)  Castiga los ticks sin accion (thresholding por
##                               umbral). Evita el agente-estatua por esa via.
##  VICTORY       (+40.0)        Bono por dejar el campo sin oponentes vivos.
##  DRAW          (-15.0)        Empate por tiempo agotado.

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


## Descripcion de cada peso editable: nombre del campo en Weights, etiqueta para
## la interfaz, limites del control y una linea de ayuda.
##
## Esta lista es la UNICA fuente de la que salen los campos de la pantalla de
## entrenamiento, la serializacion a JSON y el boton de restaurar. Anadir un peso
## nuevo aqui lo hace aparecer en los tres sitios sin tocar nada mas; tenerlos
## repetidos en la interfaz fue lo primero que se descarto, porque un peso que
## exista en el codigo pero no en el formulario es invisible y no se documenta.
const FIELDS := [
	{"key": "damage_dealt", "label": "Dano hecho", "unidad": "por punto",
		"min": 0.0, "max": 5.0, "step": 0.05,
		"hint": "Senal principal: es la unica forma de ganar."},
	{"key": "damage_taken", "label": "Dano recibido", "unidad": "por punto",
		"min": -3.0, "max": 0.0, "step": 0.05,
		"hint": "Si castiga igual o mas que el dano hecho, huir se vuelve optimo."},
	{"key": "damage_blocked", "label": "Dano bloqueado", "unidad": "por punto",
		"min": 0.0, "max": 3.0, "step": 0.05,
		"hint": "El 'evitar dano'. Por debajo de lo que cuesta el golpe."},
	{"key": "kill", "label": "Matar a un oponente", "unidad": "bono",
		"min": 0.0, "max": 200.0, "step": 1.0,
		"hint": "Bono discreto grande: es lo que define la meta."},
	{"key": "death", "label": "Morir", "unidad": "castigo",
		"min": -100.0, "max": 0.0, "step": 1.0,
		"hint": "Muy negativo produce agentes cobardes; cerca de cero, suicidas."},
	{"key": "tick_alive", "label": "Seguir vivo", "unidad": "por tick",
		"min": -0.05, "max": 0.05, "step": 0.001,
		"hint": "Subirlo mucho crea el agente-estatua: esconderse pasa a ser optimo."},
	{"key": "tick_engaged", "label": "Estar en combate", "unidad": "por tick",
		"min": -0.05, "max": 0.2, "step": 0.001,
		"hint": "Termino de shaping: da gradiente antes de que nadie sepa hacer dano."},
	{"key": "potion_used", "label": "Usar una pocion", "unidad": "bono",
		"min": -20.0, "max": 40.0, "step": 0.5,
		"hint": "Empuja a descubrir la mecanica de curacion."},
	{"key": "idle_tick", "label": "Tick sin accion", "unidad": "por tick",
		"min": -0.05, "max": 0.05, "step": 0.001,
		"hint": "Solo se acumula con thresholding por umbral, que puede no actuar."},
	{"key": "victory", "label": "Ganar el episodio", "unidad": "bono",
		"min": 0.0, "max": 200.0, "step": 1.0,
		"hint": "Se cobra al dejar el campo sin oponentes vivos."},
	{"key": "draw", "label": "Empate por tiempo", "unidad": "castigo",
		"min": -100.0, "max": 50.0, "step": 1.0,
		"hint": "En positivo, dejar correr el reloj se convierte en estrategia."},
	{"key": "engage_range", "label": "Radio de combate", "unidad": "pixeles",
		"min": 40.0, "max": 600.0, "step": 10.0,
		"hint": "Distancia a la que cuenta como 'en combate'. Afecta al shaping."},
]


## Los pesos como objeto editable, para poder cambiarlos sin tocar el codigo.
##
## Viaja POR EPISODIO dentro de ArenaSpec y no en una variable global mutable, a
## proposito: el SimPool corre hasta 16 arenas a la vez, y con estado compartido
## no se podria entrenar con unos pesos mientras el resto del proyecto evalua con
## los de siempre, ni reproducir una corrida a partir de su semilla.
##
## Los valores por defecto son exactamente las constantes de arriba, asi que un
## Weights recien creado da resultados identicos a la version anterior, que
## llamaba a las constantes directamente. De eso depende que el Excel ya
## entregado siga siendo reproducible.
class Weights extends RefCounted:
	var damage_dealt: float = Fitness.W_DAMAGE_DEALT
	var damage_taken: float = Fitness.W_DAMAGE_TAKEN
	var damage_blocked: float = Fitness.W_DAMAGE_BLOCKED
	var kill: float = Fitness.W_KILL
	var death: float = Fitness.W_DEATH
	var tick_alive: float = Fitness.W_TICK_ALIVE
	var tick_engaged: float = Fitness.W_TICK_ENGAGED
	var potion_used: float = Fitness.W_POTION_USED
	var idle_tick: float = Fitness.W_IDLE_TICK
	var victory: float = Fitness.W_VICTORY
	var draw: float = Fitness.W_DRAW
	var engage_range: float = Fitness.ENGAGE_RANGE

	func duplicate_weights() -> Weights:
		var w := Weights.new()
		for f in Fitness.FIELDS:
			w.set(str(f["key"]), get(str(f["key"])))
		return w

	func to_dict() -> Dictionary:
		var d := {}
		for f in Fitness.FIELDS:
			d[str(f["key"])] = float(get(str(f["key"])))
		return d

	## Lee solo las claves conocidas: un JSON de otra version o escrito a mano no
	## puede inyectar campos sueltos ni tumbar la carga por una clave de mas.
	func apply_dict(d: Dictionary) -> void:
		for f in Fitness.FIELDS:
			var key := str(f["key"])
			if d.has(key):
				set(key, clampf(float(d[key]), float(f["min"]), float(f["max"])))

	static func from_dict(d: Dictionary) -> Weights:
		var w := Weights.new()
		w.apply_dict(d)
		return w

	## True si algun peso se aparta del valor por defecto. Lo usa la interfaz para
	## avisar de que los resultados ya no son comparables con los del Excel.
	func is_modified() -> bool:
		var base := Weights.new()
		for f in Fitness.FIELDS:
			var key := str(f["key"])
			if not is_equal_approx(float(get(key)), float(base.get(key))):
				return true
		return false


## Pesos por defecto, los documentados arriba.
static func defaults() -> Weights:
	return Weights.new()


static func evaluate(agent: Actor, victory: bool, draw: bool = false,
		idle_ticks: int = 0, w: Weights = null) -> float:
	if w == null:
		w = Weights.new()
	var score := 0.0
	score += agent.damage_dealt * w.damage_dealt
	score += agent.damage_taken * w.damage_taken
	score += agent.damage_blocked * w.damage_blocked
	score += float(agent.kills) * w.kill
	score += float(agent.deaths) * w.death
	score += float(agent.ticks_alive) * w.tick_alive
	score += float(agent.ticks_engaged) * w.tick_engaged
	score += float(agent.potions_used) * w.potion_used
	score += float(idle_ticks) * w.idle_tick
	if victory:
		score += w.victory
	if draw:
		score += w.draw
	return score


## Desglose termino a termino, para poder mostrar en el informe de que se
## compone el fitness de un agente y no solo el numero final.
static func breakdown(agent: Actor, victory: bool, draw: bool = false,
		idle_ticks: int = 0, w: Weights = null) -> Dictionary:
	if w == null:
		w = Weights.new()
	return {
		"dano_hecho": agent.damage_dealt * w.damage_dealt,
		"dano_recibido": agent.damage_taken * w.damage_taken,
		"dano_bloqueado": agent.damage_blocked * w.damage_blocked,
		"kills": float(agent.kills) * w.kill,
		"muertes": float(agent.deaths) * w.death,
		"tiempo_vida": float(agent.ticks_alive) * w.tick_alive,
		"en_combate": float(agent.ticks_engaged) * w.tick_engaged,
		"pociones": float(agent.potions_used) * w.potion_used,
		"inactividad": float(idle_ticks) * w.idle_tick,
		"victoria": w.victory if victory else 0.0,
		"empate": w.draw if draw else 0.0,
		"total": evaluate(agent, victory, draw, idle_ticks, w),
	}
