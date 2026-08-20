class_name Potion
extends Node2D
## Pocion de curacion. Utilizable por CUALQUIER actor:
## el jugador la guarda en inventario y la usa cuando quiere, los enemigos la
## consumen al recogerla.
##
## La recogida la resuelve el Arena por distancia, no un Area2D, para que sea
## determinista dentro del mismo tick.

var available: bool = true
## Ticks para reaparecer. -1 = no reaparece.
var respawn_ticks: int = -1
var _respawn_left: int = 0
var _sprite: Sprite2D = null
var _bob: float = 0.0


func enable_visuals() -> void:
	var tex := AssetLibrary.texture("potion")
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	add_child(_sprite)
	set_process(true)


func _process(delta: float) -> void:
	if _sprite == null:
		return
	# Flotacion suave: llama la atencion sobre un objeto recogible sin
	# necesitar particulas ni animacion.
	_bob += delta * 3.0
	_sprite.position.y = sin(_bob) * 2.5
	_sprite.visible = available


func take() -> bool:
	if not available:
		return false
	available = false
	_respawn_left = respawn_ticks
	visible = false
	return true


func sim_tick() -> void:
	if available or respawn_ticks < 0:
		return
	_respawn_left -= 1
	if _respawn_left <= 0:
		available = true
		visible = true
		queue_redraw()


func reset() -> void:
	available = true
	visible = true
	_respawn_left = 0
	queue_redraw()


func _draw() -> void:
	if not available or _sprite != null:
		return
	draw_circle(Vector2.ZERO, 7.0, Color(0.25, 0.9, 0.45))
	draw_circle(Vector2.ZERO, 3.0, Color(0.85, 1.0, 0.9))
