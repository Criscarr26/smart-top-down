extends SceneTree
## Diagnostico: comprueba si los nodos dentro de un SubViewport con World2D
## propio reciben _physics_process. No forma parte del juego.
## Uso: godot --headless --path . --script res://game/probe_subviewport.gd

class Ticker extends Node2D:
	var ticks := 0
	func _physics_process(_d: float) -> void:
		ticks += 1


func _initialize() -> void:
	print("--- probe: SubViewport + World2D propio ---")
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	vp.size = Vector2i(1, 1)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)

	var inside := Ticker.new()
	vp.add_child(inside)

	var outside := Ticker.new()
	root.add_child(outside)

	# Comprueba tambien que las consultas de fisica funcionan en ese mundo.
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(64, 64)
	shape.shape = rect
	body.add_child(shape)
	body.position = Vector2(100, 0)
	vp.add_child(body)

	await process_frame
	for _i in 30:
		await physics_frame

	print("ticks DENTRO del SubViewport: %d" % inside.ticks)
	print("ticks FUERA (root):           %d" % outside.ticks)

	var space := inside.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2(200, 0), 1)
	var hit := space.intersect_ray(q)
	print("raycast dentro del SubViewport golpea: %s" % (not hit.is_empty()))
	print("world_2d aislado (distinto del root): %s"
			% (inside.get_world_2d() != root.get_world_2d()))
	quit()
