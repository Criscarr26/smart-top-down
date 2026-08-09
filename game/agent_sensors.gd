class_name AgentSensors
extends RefCounted
## Los 7 sensores que forman la capa de entrada de la red (supera el minimo de 5
## que exige la seccion 3.2 del PDF).
##
## TODOS salen normalizados: seis en [0, 1] y el angulo en [-1, 1]. Es la
## recomendacion IV.4 del PDF y no es cosmetica: si un sensor entregara pixeles
## crudos (0-320) y otro un booleano (0-1), el algoritmo genetico tendria que
## gastar generaciones solo en descubrir la escala de cada peso, y el sensor de
## rango grande dominaria la suma ponderada por accidente de unidades.

enum {
	DIST_TO_TARGET = 0,   ## 0 = encima, 1 = fuera de rango util
	ANGLE_TO_TARGET = 1,  ## -1 = a la izquierda, 0 = al frente, 1 = a la derecha
	OWN_HEALTH = 2,       ## 0 = muerto, 1 = salud llena
	LINE_OF_SIGHT = 3,    ## 0 = bloqueado, 1 = despejado
	DIST_TO_POTION = 4,   ## 1 = no hay pocion disponible
	TARGET_SHIELD = 5,    ## escudo del oponente, 0..1
	OWN_ATTACK_COOLDOWN = 6,  ## 0 = listo para atacar, 1 = recien atacado
}

const COUNT := 7

const NAMES := [
	"dist_objetivo", "angulo_objetivo", "salud_propia", "linea_vision",
	"dist_pocion", "escudo_objetivo", "cooldown_propio",
]

## Rango de referencia para normalizar distancias.
const MAX_SENSE_RANGE := 420.0


## Indices de sensores que no aportan informacion en una etapa concreta del
## curriculum. Alimenta la mascara de congelacion del GA (recomendacion IV.2 del
## PDF: "frisar la optimizacion de los sensores relacionados a mecanicas no
## relacionadas con el nivel").
##
## Se evalua POR ETAPA y no una sola vez para todo el entrenamiento, porque el
## caso que de verdad se da en este proyecto es el del escudo: solo el enemigo
## Tipo B puede defender, asi que durante las etapas contra el Tipo A y contra
## el Tipo C el sensor `escudo_objetivo` vale 0 en todos los ticks de todos los
## episodios. Optimizar sus pesos ahi es ajustar ruido, y ademas ese ajuste
## luego estorba en la etapa contra el Tipo B, donde el sensor si importa.
##
##   data                 nivel de la etapa
##   opponent_can_defend  si algun oponente de la etapa puede levantar guardia
static func irrelevant_for_stage(data: LevelData, opponent_can_defend: bool) -> Array:
	var frozen: Array = []
	if data.potions.is_empty():
		frozen.append(DIST_TO_POTION)
	if not opponent_can_defend:
		frozen.append(TARGET_SHIELD)
	return frozen


## Lee el estado del mundo y devuelve el vector de entrada de la red.
static func read(agent: Actor, target: Actor, potions: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(COUNT)

	var has_target: bool = target != null and is_instance_valid(target) and target.alive

	if has_target:
		var to_target: Vector2 = target.global_position - agent.global_position
		var dist: float = to_target.length()
		out[DIST_TO_TARGET] = clampf(dist / MAX_SENSE_RANGE, 0.0, 1.0)
		out[ANGLE_TO_TARGET] = clampf(agent.facing.angle_to(to_target) / PI, -1.0, 1.0)
		out[LINE_OF_SIGHT] = 1.0 if VisionSensor.has_line_of_sight(agent, target.global_position) else 0.0
		out[TARGET_SHIELD] = target.shield_fraction()
	else:
		out[DIST_TO_TARGET] = 1.0
		out[ANGLE_TO_TARGET] = 0.0
		out[LINE_OF_SIGHT] = 0.0
		out[TARGET_SHIELD] = 0.0

	out[OWN_HEALTH] = agent.health_fraction()

	var nearest := INF
	for p in potions:
		var potion := p as Potion
		if potion == null or not potion.available:
			continue
		nearest = minf(nearest, agent.global_position.distance_to(potion.global_position))
	out[DIST_TO_POTION] = 1.0 if is_inf(nearest) else clampf(nearest / MAX_SENSE_RANGE, 0.0, 1.0)

	# El mayor de los dos cooldowns: le dice a la red si tiene ALGO listo.
	var worst_cd: int = maxi(agent.melee_cd, agent.ranged_cd)
	var cd_ref := float(maxi(GameConfig.MELEE_COOLDOWN_TICKS, GameConfig.RANGED_COOLDOWN_TICKS))
	out[OWN_ATTACK_COOLDOWN] = clampf(float(worst_cd) / cd_ref, 0.0, 1.0)

	return out
