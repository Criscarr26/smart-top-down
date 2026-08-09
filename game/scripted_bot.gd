class_name ScriptedBot
extends Actor
## Sustituto automatizado del jugador humano en el benchmark.
##
## LIMITACION CONOCIDA, declarada explicitamente (seccion 6 del prompt de
## benchmark): los escenarios 4 y 10 del PDF piden "jugador humano vs agente".
## Un humano no se puede meter en un barrido de miles de partidas headless, asi
## que se sustituye por este bot de reglas fijas con ruido acotado. Los
## resultados de esos dos escenarios miden al agente contra un oponente
## HUMANO-SIMULADO, no contra una persona. En el informe deben reportarse como
## tales, y complementarse con las partidas contra humano real que si se juegan
## a mano en el benchmark cualitativo.
##
## El bot mezcla las tres tacticas que usa un jugador promedio: mantener
## distancia y disparar, entrar a melee cuando el rival esta debil, y bloquear
## cuando le llueve encima. El ruido viene de Rng (con semilla), no de randf(),
## para que las corridas sean reproducibles.

var nav: NavGrid
var pathing: PathfindingComponent
var vision: VisionSensor
var target: Actor = null
var level_potions: Array = []

## Distancia a la que intenta pelear.
var preferred_range: float = 170.0
## Probabilidad por tick de cambiar el sentido del "strafe".
var strafe_flip_chance: float = 0.02

var _strafe_sign: float = 1.0
var _reaction_ticks: int = 0
## Retardo de reaccion humano simulado, en ticks (~130 ms).
const REACTION_DELAY := 8


func configure(p_nav: NavGrid, p_potions: Array) -> void:
	display_name = "Bot (humano simulado)"
	sprite_kind = "player"
	body_color = Color(0.35, 0.85, 0.95)
	max_health = GameConfig.PLAYER_MAX_HEALTH
	health = max_health
	move_speed = GameConfig.PLAYER_SPEED
	melee_damage = GameConfig.PLAYER_MELEE_DAMAGE
	ranged_damage = GameConfig.PLAYER_RANGED_DAMAGE
	can_defend = true
	max_shield = GameConfig.MAX_SHIELD
	shield = max_shield
	auto_use_potions = false   # decide por si mismo, como un jugador
	setup_team(Team.PLAYER)
	nav = p_nav
	level_potions = p_potions
	pathing = PathfindingComponent.new(self, p_nav)
	vision = VisionSensor.new(self)
	# El bot tiene vision omnidireccional: un humano mueve la camara, y el cono
	# frontal lo dejaria en desventaja artificial frente al agente.
	vision.half_angle = PI


func think(_delta: float) -> void:
	if not alive:
		return
	vision.update(target)

	# Curarse es lo primero que hace un jugador con poca vida.
	if is_low_health() and potions > 0:
		if try_use_potion():
			return

	if not vision.is_aware() or target == null or not target.alive:
		_wander()
		return

	# Retardo de reaccion: no responde en el mismo tick en que aparece la amenaza.
	if _reaction_ticks < REACTION_DELAY:
		_reaction_ticks += 1
		_retreat_slightly()
		return

	var dist := vision.distance_to_target()
	var to_target: Vector2 = target.global_position - global_position
	face_towards(target.global_position)

	# Bajo presion y sin poder curarse: bloquea.
	if health_fraction() < 0.3 and dist < 70.0 and not is_shield_broken():
		set_defending(true)
		return

	# Rival debilitado y cerca: entra a rematar cuerpo a cuerpo.
	if dist <= GameConfig.MELEE_RANGE * 0.9 and target.health_fraction() < 0.5:
		stop()
		try_melee(to_target)
		return

	# Se le echaron encima: se quita de en medio pegando.
	if dist <= GameConfig.MELEE_RANGE * 0.9:
		try_melee(to_target)

	if vision.visible_now:
		try_ranged(to_target)

	_maintain_range(dist, to_target)


## Se acerca o se aleja para quedarse en su distancia preferida, con strafe
## lateral encima para no ser un blanco fijo.
func _maintain_range(dist: float, to_target: Vector2) -> void:
	if _rand() < strafe_flip_chance:
		_strafe_sign = -_strafe_sign
	var dir := to_target.normalized()
	var radial := 0.0
	if dist > preferred_range * 1.15:
		radial = 1.0
	elif dist < preferred_range * 0.7:
		radial = -1.0
	var strafe := dir.orthogonal() * _strafe_sign
	var desired := (dir * radial + strafe * 0.85)
	if desired.length_squared() < 0.0001:
		stop()
		return
	# Solo se mueve si el destino inmediato es transitable: evita frotarse
	# contra las paredes y contra las puas.
	var probe := global_position + desired.normalized() * GameConfig.CELL_SIZE
	if not nav.is_walkable_world(probe):
		_strafe_sign = -_strafe_sign
		desired = dir * radial - strafe * 0.85
		if desired.length_squared() < 0.0001:
			stop()
			return
	var keep := facing
	move_in_direction(desired)
	facing = keep


func _retreat_slightly() -> void:
	if target == null:
		return
	var away := (global_position - target.global_position)
	if away.length_squared() < 0.0001:
		return
	var probe := global_position + away.normalized() * GameConfig.CELL_SIZE
	if nav.is_walkable_world(probe):
		move_in_direction(away)


## Sin amenaza a la vista: recoge pociones si las hay, si no deambula.
func _wander() -> void:
	_reaction_ticks = 0
	var potion := _nearest_potion()
	if potion != null and potions == 0:
		pathing.set_goal(potion.global_position)
		var d := pathing.steer()
		if d != Vector2.ZERO:
			move_in_direction(d, 0.8)
			return
	if not pathing.has_path():
		var cells := nav.free_cells()
		if not cells.is_empty():
			var i: int = int(_rand() * cells.size()) % cells.size()
			pathing.set_goal(nav.cell_to_world(cells[i]))
	move_in_direction(pathing.steer(), 0.6)


func _nearest_potion() -> Potion:
	return Steering.nearest_potion(global_position, level_potions)


## Aleatoriedad del generador de la arena (ver la nota en Actor.rng).
func _rand() -> float:
	return rng.randf() if rng != null else Rng.randf()


## Rompe las referencias ciclicas (ver Actor.dispose).
func dispose() -> void:
	if pathing != null:
		pathing.actor = null
		pathing.nav = null
		pathing = null
	if vision != null:
		vision.actor = null
		vision.target = null
		vision = null
	target = null
	nav = null
	level_potions = []
	super.dispose()
