class_name WorldBuilder
extends RefCounted
## Construye la representacion FISICA del nivel (paredes colisionables) a partir
## del mismo LevelData que alimenta el grid de A*. Que ambas salgan de la misma
## fuente es lo que garantiza que la ruta calculada exista en el mundo real.


## Crea un unico StaticBody2D con un CollisionShape2D por tramo horizontal de
## pared. Agrupar en tramos en vez de una forma por celda reduce mucho el coste
## de broadphase cuando corren decenas de arenas simultaneas en el benchmark.
static func build_walls(data: LevelData) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	var cs := GameConfig.CELL_SIZE
	for r in data.wall_runs():
		var run: Rect2i = r
		var shape := RectangleShape2D.new()
		shape.size = Vector2(run.size.x * cs, run.size.y * cs)
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = Vector2(run.position.x * cs, run.position.y * cs) + shape.size * 0.5
		body.add_child(col)
	return body


static func build_nav_grid(data: LevelData) -> NavGrid:
	var nav := NavGrid.new()
	nav.build(data.region(), data.blocked_cells())
	return nav


static func build_spikes(data: LevelData) -> Array[Spike]:
	var out: Array[Spike] = []
	for cell in data.spikes:
		var s := Spike.new()
		s.position = data.cell_center(cell)
		out.append(s)
	return out


static func build_potions(data: LevelData, respawn_ticks: int = -1) -> Array[Potion]:
	var out: Array[Potion] = []
	for cell in data.potions:
		var p := Potion.new()
		p.position = data.cell_center(cell)
		p.respawn_ticks = respawn_ticks
		out.append(p)
	return out


## Dibuja suelo y paredes. Lo llama el Arena desde su _draw en vez de crear un
## nodo por celda: un nivel de 32x18 son 576 celdas, y con sprites individuales
## serian 576 nodos por arena para algo que nunca se mueve.
##
## Usa las texturas generadas si estan; si no, cae a rectangulos de color, de
## forma que el juego sigue siendo jugable sin haber corrido los generadores.
static func draw_level(canvas: CanvasItem, data: LevelData) -> void:
	var cs := GameConfig.CELL_SIZE
	var full := Rect2(Vector2.ZERO, Vector2(data.width, data.height) * cs)
	var floor_tex := AssetLibrary.texture("floor")
	var wall_tex := AssetLibrary.texture("wall")

	if floor_tex != null:
		# tile=true repite la textura por toda la superficie en una sola llamada.
		canvas.draw_texture_rect(floor_tex, full, true)
	else:
		canvas.draw_rect(full, Color(0.13, 0.12, 0.16))

	# Retícula tenue del grid de A*. Ademas de dar textura al suelo, hace visible
	# la malla sobre la que planifica el pathfinding, que es justo lo que hay que
	# poder ensenar al explicar el proyecto.
	var lineas := Color(1, 1, 1, 0.030)
	for x in range(1, data.width):
		canvas.draw_line(Vector2(x * cs, 0.0), Vector2(x * cs, full.size.y), lineas, 1.0)
	for y in range(1, data.height):
		canvas.draw_line(Vector2(0.0, y * cs), Vector2(full.size.x, y * cs), lineas, 1.0)

	# Las paredes se dibujan en tres pasadas para que tengan volumen: sombra
	# proyectada, cuerpo y borde iluminado arriba. Es lo que separa un mapa de
	# rectangulos planos de algo que parece un escenario.
	for r in data.wall_runs():
		var run: Rect2i = r
		var rect := Rect2(Vector2(run.position) * cs, Vector2(run.size) * cs)
		canvas.draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size),
				Color(0, 0, 0, 0.34))
	for r in data.wall_runs():
		var run: Rect2i = r
		var rect := Rect2(Vector2(run.position) * cs, Vector2(run.size) * cs)
		if wall_tex != null:
			canvas.draw_texture_rect(wall_tex, rect, true)
		else:
			canvas.draw_rect(rect, Color(0.33, 0.30, 0.40))
		canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)),
				Color(1, 1, 1, 0.13))
		canvas.draw_rect(rect, Color(0.05, 0.05, 0.08, 0.55), false, 1.0)
