class_name Enemy
extends Actor
## Enemigo gobernado por FSM. Un unico script para los tipos A, B y C: lo que
## cambia entre ellos es el EnemyProfile, que decide que estados se registran y
## con que umbrales se transiciona.

var profile: EnemyProfile
var vision: VisionSensor
var pathing: PathfindingComponent
var machine: StateMachine

var nav: NavGrid
var target: Actor = null
## Referencia viva a las pociones del nivel; la inyecta el Arena.
var level_potions: Array = []
## Todos los actores de la arena, inyectados tras el spawn. Solo lo usa el
## sanador (Tipo D) para encontrar aliados heridos. Es una referencia a la lista
## viva del Arena, no una copia: los estados la consultan cada pocos ticks y
## copiarla seria basura por tick.
var squad: Array = []

## Salud devuelta a aliados. Metrica del Tipo D, analoga a damage_dealt.
var healing_done: float = 0.0
## A quien esta curando ahora mismo, para dibujar el haz. null si a nadie.
var healing_target: Actor = null

var _free_cells_cache: Array = []


func configure(p_profile: EnemyProfile, p_nav: NavGrid, p_potions: Array) -> void:
	profile = p_profile
	nav = p_nav
	level_potions = p_potions

	display_name = profile.display_name
	sprite_kind = profile.type_id.to_lower()
	body_color = profile.body_color
	max_health = profile.max_health
	health = profile.max_health
	move_speed = profile.move_speed
	accel = profile.accel
	friction = profile.friction
	melee_damage = profile.melee_damage
	ranged_damage = profile.ranged_damage
	can_defend = profile.can_defend
	max_shield = GameConfig.MAX_SHIELD if profile.can_defend else 0.0
	shield = max_shield

	setup_team(Team.ENEMY)
	vision = VisionSensor.new(self)
	pathing = PathfindingComponent.new(self, p_nav)
	_build_state_machine()


## Registra solo los estados que el perfil habilita. El Tipo B, por ejemplo,
## nunca tendra "Huir", asi que una peticion de huida se ignora sin romper nada
## (ver StateMachine.change_to).
func _build_state_machine() -> void:
	machine = StateMachine.new()
	machine.add_state(StateMachine.IDLE, IdleState.new(), self)
	if profile.can_melee:
		machine.add_state(StateMachine.CHASE, ChaseState.new(), self)
		machine.add_state(StateMachine.MELEE, MeleeAttackState.new(), self)
	if profile.can_ranged:
		machine.add_state(StateMachine.RANGED, RangedAttackState.new(), self)
	if profile.can_defend:
		machine.add_state(StateMachine.DEFEND, DefendState.new(), self)
	if profile.can_flee:
		machine.add_state(StateMachine.FLEE, FleeState.new(), self)
	if profile.can_seek_potion:
		machine.add_state(StateMachine.SEEK_POTION, SeekPotionState.new(), self)
	if profile.can_heal:
		machine.add_state(StateMachine.SUPPORT, SupportState.new(), self)
	machine.start(StateMachine.IDLE)


## Capa de decision. La llama el Arena una vez por tick, despues de sim_tick().
func think(delta: float) -> void:
	if not alive:
		return
	vision.update(target)
	machine.tick(delta)


# =============================================================================
# Consultas del entorno usadas por los estados
# =============================================================================

## Pocion disponible mas cercana, o null. Se mide en distancia recta (no de
## ruta) porque hacerlo por A* costaria un pathfind por pocion y por tick.
func nearest_potion() -> Potion:
	return Steering.nearest_potion(global_position, level_potions)


## El aliado vivo mas herido dentro del radio de busqueda, o null.
##
## Vive aqui y no en SupportState por la misma razon que nearest_potion(): los
## estados toman decisiones, el enemigo responde preguntas sobre su entorno. Asi
## IdleState puede consultar si hay trabajo que hacer sin duplicar la busqueda.
##
## Prioriza por FRACCION de salud, no por salud absoluta: curar al que le faltan
## 40 de 70 rinde mas que al que le faltan 40 de 200.
func wounded_ally(umbral: float = 0.92) -> Actor:
	if not profile.can_heal:
		return null
	var mejor: Actor = null
	var peor := umbral
	for a in squad:
		var otro := a as Actor
		if otro == null or otro == self or not is_instance_valid(otro):
			continue
		if not otro.alive or otro.team != team:
			continue
		if otro.global_position.distance_to(global_position) > profile.heal_search_range:
			continue
		var f := otro.health_fraction()
		if f < peor:
			peor = f
			mejor = otro
	return mejor


func pick_patrol_point() -> Vector2:
	if _free_cells_cache.is_empty():
		_free_cells_cache = nav.free_cells()
	if _free_cells_cache.is_empty():
		return global_position
	var i: int = rng.randi_range(0, _free_cells_cache.size() - 1) if rng != null \
			else Rng.randi_range(0, _free_cells_cache.size() - 1)
	return nav.cell_to_world(_free_cells_cache[i])


## Delega en Steering para que el Tipo C y el agente entrenado huyan con
## exactamente la misma logica: si divergieran, una comparacion entre ambos en
## el benchmark estaria midiendo la diferencia de implementacion, no de politica.
func flee_point_from(threat: Vector2) -> Vector2:
	return Steering.flee_point(global_position, threat, nav, rng)


func state_name() -> String:
	return machine.current_name if machine != null else ""


# =============================================================================
# Overlay de depuracion
# =============================================================================
## Replica el Draw_0 del ejemplo del profesor: estado actual, vida, radios de
## transicion y linea de vision al objetivo (verde si lo ve, roja si no).
##
## Se activa con la tecla F1 en la partida jugable. Sirve para dos cosas:
## depurar transiciones que "no se disparan", y poder ENSENAR la FSM
## funcionando durante la defensa del proyecto en vez de describirla.
static var debug_draw: bool = false


func _draw() -> void:
	super._draw()
	if not alive:
		return

	# Haz de curacion del Tipo D. Se dibuja siempre (no solo en depuracion)
	# porque es informacion de juego: sin verlo, que un enemigo recupere salud
	# parece un fallo en vez de algo que hay que ir a cortar.
	if healing_target != null and is_instance_valid(healing_target) and healing_target.alive:
		var hacia: Vector2 = healing_target.global_position - global_position
		draw_line(Vector2.ZERO, hacia, Color(0.55, 1.0, 0.65, 0.55), 2.5)
		draw_arc(hacia, GameConfig.ACTOR_RADIUS + 4.0, 0.0, TAU, 16,
				Color(0.55, 1.0, 0.65, 0.75), 1.5)

	if not debug_draw:
		return

	# Cono de vision (el ejemplo del profesor usa un circulo; aqui la deteccion
	# es un cono, asi que se dibuja lo que de verdad se comprueba).
	var half := GameConfig.VISION_HALF_ANGLE
	var base := facing.angle()
	draw_arc(Vector2.ZERO, GameConfig.VISION_RANGE, base - half, base + half,
			24, Color(1, 1, 1, 0.18), 1.0)
	draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(base - half) * GameConfig.VISION_RANGE,
			Color(1, 1, 1, 0.12), 1.0)
	draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(base + half) * GameConfig.VISION_RANGE,
			Color(1, 1, 1, 0.12), 1.0)

	# Radios de transicion propios del perfil.
	if profile.can_melee:
		draw_arc(Vector2.ZERO, profile.melee_range, 0, TAU, 20, Color(1, 0.3, 0.3, 0.45), 1.0)
	if profile.can_defend:
		draw_arc(Vector2.ZERO, profile.defend_radius, 0, TAU, 24, Color(0.4, 0.7, 1, 0.4), 1.0)
	if profile.can_flee:
		draw_arc(Vector2.ZERO, profile.flee_radius, 0, TAU, 24, Color(1, 0.8, 0.2, 0.4), 1.0)

	# Linea al objetivo: verde si hay vision directa, roja si esta bloqueada.
	if target != null and is_instance_valid(target) and target.alive:
		var local: Vector2 = target.global_position - global_position
		var col := Color(0.3, 1.0, 0.4, 0.7) if vision.visible_now else Color(1.0, 0.3, 0.3, 0.5)
		draw_line(Vector2.ZERO, local, col, 1.5)

	# Estado y vida encima de la cabeza.
	var font := ThemeDB.fallback_font
	var label := "%s  %d" % [state_name(), int(health)]
	draw_string(font, Vector2(-26, -GameConfig.ACTOR_RADIUS - 18), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.9))


## Rompe el ciclo Enemy -> StateMachine -> EnemyState -> Enemy (ver Actor.dispose).
func dispose() -> void:
	if machine != null:
		for key in machine.states:
			var state := machine.states[key] as EnemyState
			if state != null:
				state.enemy = null
				state.machine = null
		machine.states.clear()
		machine.current = null
		machine = null
	if vision != null:
		vision.actor = null
		vision.target = null
		vision = null
	if pathing != null:
		pathing.actor = null
		pathing.nav = null
		pathing = null
	target = null
	healing_target = null
	squad = []
	level_potions = []
	_free_cells_cache = []
	nav = null
	super.dispose()
