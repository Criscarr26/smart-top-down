class_name Projectile
extends Node2D
## Proyectil del ataque a distancia.
##
## Avanza por barrido de raycast (posicion previa -> posicion nueva) en vez de
## teletransportarse y comprobar solapamiento con un Area2D. Dos razones:
##  1. A 420 px/s y 60 ticks/s el proyectil recorre 7 px por tick; con un
##     Area2D pequeno eso ya empieza a atravesar paredes finas (tunneling).
##  2. El barrido resuelve el impacto en el mismo tick del disparo, sin la
##     latencia de un tick que introduce Area2D al registrar solapamientos.

var shooter: Actor = null
var direction: Vector2 = Vector2.RIGHT
var speed: float = GameConfig.PROJECTILE_SPEED
var damage: float = 14.0
var ticks_left: int = GameConfig.PROJECTILE_LIFETIME_TICKS
var target_layer: int = 0
var finished: bool = false


func setup(p_shooter: Actor, from: Vector2, dir: Vector2, p_damage: float) -> void:
	shooter = p_shooter
	global_position = from
	direction = dir.normalized()
	damage = p_damage
	target_layer = p_shooter.enemy_layer()
	ticks_left = GameConfig.PROJECTILE_LIFETIME_TICKS


## Devuelve false cuando el proyectil debe eliminarse.
func sim_tick() -> bool:
	if finished:
		return false
	ticks_left -= 1
	if ticks_left <= 0:
		finished = true
		return false

	var from := global_position
	var to := from + direction * speed * GameConfig.SIM_DT

	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
			from, to, GameConfig.LAYER_WORLD | target_layer)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if shooter != null and is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		queue_redraw()
		return true

	# Impacto: si es un actor del bando contrario, aplica dano.
	var victim := hit.get("collider") as Actor
	if victim != null and victim.alive and victim != shooter:
		victim.take_damage(damage, shooter)
	global_position = hit.get("position", to)
	finished = true
	return false


var _sprite: Sprite2D = null


func enable_visuals() -> void:
	var kind := "player" if shooter != null and shooter.team == Actor.Team.PLAYER else "enemy"
	var tex := AssetLibrary.texture("bullet_%s" % kind)
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	# La estela del sprite apunta a -X, asi que rotarlo al angulo de avance la
	# deja siempre detras del proyectil.
	_sprite.rotation = direction.angle()
	add_child(_sprite)


func _draw() -> void:
	if _sprite != null:
		return
	var col := Color(1.0, 0.85, 0.3) if shooter != null and shooter.team == Actor.Team.PLAYER \
			else Color(1.0, 0.45, 0.35)
	draw_circle(Vector2.ZERO, 3.5, col)
