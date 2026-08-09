class_name Spike
extends Node2D
## Obstaculo tipo "pua": mata instantaneamente al jugador o al enemigo que la
## toque (requisito 5 del PDF).
##
## No es un cuerpo solido. Es solida solo en el grid de A* (ver
## LevelData.blocked_cells), de modo que quien planifica ruta la esquiva y
## quien se mueve en linea recta puede morir en ella. El Arena comprueba la
## distancia cada tick.

const KILL_RADIUS: float = GameConfig.CELL_SIZE * 0.42


var _sprite: Sprite2D = null


func enable_visuals() -> void:
	var tex := AssetLibrary.texture("spike")
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	add_child(_sprite)


func kills(actor_position: Vector2) -> bool:
	return global_position.distance_to(actor_position) <= KILL_RADIUS + GameConfig.ACTOR_RADIUS * 0.5


func _draw() -> void:
	if _sprite != null:
		return   # ya lo dibuja el sprite
	var r := GameConfig.CELL_SIZE * 0.5
	draw_rect(Rect2(-Vector2(r, r), Vector2(r, r) * 2.0), Color(0.16, 0.09, 0.11))
	# Cuatro puntas
	for i in 4:
		var a := TAU * (float(i) / 4.0) + PI * 0.25
		var tip := Vector2.RIGHT.rotated(a) * r * 0.8
		var l := Vector2.RIGHT.rotated(a + PI * 0.5) * r * 0.28
		draw_colored_polygon(PackedVector2Array([tip, l, -l]), Color(0.85, 0.85, 0.9))
