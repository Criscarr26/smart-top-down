class_name PathfindingComponent
extends RefCounted
## Capa de movimiento de la arquitectura en dos capas.
##
##  Capa 1 (decision) : la FSM o la red neuronal deciden UNA posicion objetivo.
##  Capa 2 (movimiento): esta clase convierte esa posicion en una ruta A* y
##                       devuelve, tick a tick, la direccion al siguiente
##                       waypoint. El actor se mueve de forma continua
##                       (velocity * SIM_DT), no saltando de celda en celda.
##
## Es compartida por los tres tipos de enemigo FSM y por el agente entrenado.

var nav: NavGrid
var actor: Actor

var _path: PackedVector2Array = PackedVector2Array()
var _index: int = 0
var _goal: Vector2 = Vector2.ZERO
var _has_goal: bool = false
var _ticks_since_repath: int = 999

## Cada cuantos ticks se acepta recalcular la ruta. A* sobre un grid pequeno es
## barato, pero con 50 arenas en paralelo x N agentes deja de serlo.
var repath_interval_ticks: int = 12
## Si el objetivo se movio menos que esto, se reutiliza la ruta actual.
var goal_tolerance: float = GameConfig.CELL_SIZE * 0.9
## Distancia a la que se considera alcanzado un waypoint.
var waypoint_tolerance: float = 7.0
## Cada cuantos ticks se re-lanza el raycast de linea de vista al objetivo.
var los_refresh_ticks: int = 6

var _los_cached: bool = false
var _los_age: int = 999


func _init(owner_actor: Actor, grid: NavGrid) -> void:
	actor = owner_actor
	nav = grid


func set_goal(world_pos: Vector2) -> void:
	var goal_changed := not _has_goal or _goal.distance_to(world_pos) > goal_tolerance
	_goal = world_pos
	_has_goal = true
	if goal_changed and _ticks_since_repath >= repath_interval_ticks:
		_recalculate()


func clear_goal() -> void:
	_has_goal = false
	_path = PackedVector2Array()
	_index = 0
	_los_age = 999   # fuerza recalculo al fijar el proximo objetivo


func has_path() -> bool:
	return _index < _path.size()


## Direccion normalizada hacia el siguiente waypoint. Vector2.ZERO si llego o
## si no hay ruta posible. Llamar una vez por tick.
func steer() -> Vector2:
	_ticks_since_repath += 1
	if not _has_goal or nav == null:
		return Vector2.ZERO

	# Si el objetivo esta a la vista en linea recta, ir directo: evita el
	# zigzag de seguir waypoints de rejilla en espacios abiertos.
	#
	# El raycast se cachea unos ticks. Lanzarlo cada tick para cada actor era el
	# coste dominante del barrido headless, y a 60 Hz la vista no cambia lo
	# bastante en 6 ticks (0.1 s) como para que la diferencia sea observable.
	_los_age += 1
	if _los_age >= los_refresh_ticks:
		_los_age = 0
		_los_cached = VisionSensor.has_line_of_sight(actor, _goal)
	if _los_cached:
		var direct: Vector2 = _goal - actor.global_position
		if direct.length() <= waypoint_tolerance:
			return Vector2.ZERO
		return direct.normalized()

	if not has_path() and _ticks_since_repath >= repath_interval_ticks:
		_recalculate()
	if not has_path():
		return Vector2.ZERO

	# Consume los waypoints ya alcanzados.
	while _index < _path.size() \
			and actor.global_position.distance_to(_path[_index]) <= waypoint_tolerance:
		_index += 1
	if _index >= _path.size():
		return Vector2.ZERO
	return (_path[_index] - actor.global_position).normalized()


func _recalculate() -> void:
	_ticks_since_repath = 0
	_path = nav.find_path(actor.global_position, _goal)
	_index = 0
	# get_point_path incluye la celda de origen; saltarla evita un tiron hacia
	# atras cuando el actor ya paso del centro de su celda.
	if _path.size() > 1 and actor.global_position.distance_to(_path[0]) < waypoint_tolerance:
		_index = 1


## Ruta actual en coordenadas de mundo (para depuracion visual).
func debug_path() -> PackedVector2Array:
	return _path
