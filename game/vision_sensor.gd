class_name VisionSensor
extends RefCounted
## Deteccion estilo Hotline Miami: cono de vision frontal + linea de vista
## bloqueada por paredes. NO es un radio circular simple.
##
## Mantiene ademas una memoria corta: tras perder de vista al objetivo el
## enemigo sigue sabiendo su ultima posicion conocida durante unos ticks, para
## que no se "olvide" instantaneamente al cruzar una columna.

var actor: Actor
var vision_range: float = GameConfig.VISION_RANGE
var half_angle: float = GameConfig.VISION_HALF_ANGLE
var memory_ticks: int = GameConfig.VISION_MEMORY_TICKS

var target: Actor = null
var visible_now: bool = false
var last_known_position: Vector2 = Vector2.ZERO
var _memory_left: int = 0


func _init(owner_actor: Actor) -> void:
	actor = owner_actor


## Recalcula la percepcion de este tick contra el objetivo dado.
func update(candidate: Actor) -> void:
	target = candidate
	visible_now = _check_visible(candidate)
	if visible_now:
		last_known_position = candidate.global_position
		_memory_left = memory_ticks
	elif _memory_left > 0:
		_memory_left -= 1


## True si lo ve ahora mismo o si lo recuerda de hace poco.
func is_aware() -> bool:
	return visible_now or _memory_left > 0


func forget() -> void:
	_memory_left = 0
	visible_now = false


func distance_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	return actor.global_position.distance_to(target.global_position)


func _check_visible(candidate: Actor) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not candidate.alive:
		return false
	if not actor.alive:
		return false
	var to_target: Vector2 = candidate.global_position - actor.global_position
	var dist := to_target.length()
	if dist > vision_range:
		return false
	# Dentro del cono frontal. A quemarropa el cono se ignora: si lo tienes
	# encima lo notas aunque este a tu espalda.
	if dist > GameConfig.MELEE_RANGE and absf(actor.facing.angle_to(to_target)) > half_angle:
		return false
	return has_line_of_sight(actor, candidate.global_position)


## Raycast contra la capa de mundo. Estatico para que tambien lo use la red
## neuronal (sensor 4: linea de vision libre al jugador).
static func has_line_of_sight(from_actor: Actor, to_point: Vector2) -> bool:
	if from_actor == null or not is_instance_valid(from_actor):
		return false
	var space := from_actor.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
			from_actor.global_position, to_point, GameConfig.LAYER_WORLD)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()
