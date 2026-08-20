class_name NavGrid
extends RefCounted
## Representacion logica del nivel para A*, construida sobre AStarGrid2D.
##
## El nivel existe dos veces, como pide la especificacion:
##  - aqui, como rejilla de celdas transitables / solidas (decision de ruta)
##  - en el arbol de escena, como StaticBody2D con colisiones (movimiento fisico)
## Ambas se generan de la misma fuente (LevelData), asi que no pueden divergir.

var astar := AStarGrid2D.new()
var region: Rect2i = Rect2i()
var cell_size: float = GameConfig.CELL_SIZE


## Construye la rejilla. `solid_cells` son coordenadas de celda no transitables.
func build(grid_region: Rect2i, solid_cells: Array) -> void:
	region = grid_region
	astar.region = grid_region
	astar.cell_size = Vector2(cell_size, cell_size)
	# Centra los puntos en la celda: world = id * cell_size + offset.
	astar.offset = Vector2(cell_size, cell_size) * 0.5

	# Heuristica euclidiana: es la unica del proyecto y esta justificada porque
	# el movimiento permite diagonales (Manhattan sobreestimaria y dejaria de
	# ser admisible). Solo se comparan multiples variantes para el
	# optimizador genetico, no para el pathfinding.
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN

	# ONLY_IF_NO_OBSTACLES en vez de ALWAYS: con ALWAYS el agente corta esquinas
	# atravesando la diagonal entre dos paredes, y luego el cuerpo fisico se
	# atasca en el vertice porque esa ruta no existe en el mundo real.
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES

	astar.update()  # debe ir ANTES de marcar celdas solidas

	for c in solid_cells:
		var cell: Vector2i = c
		if astar.is_in_boundsv(cell):
			astar.set_point_solid(cell, true)


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / cell_size), floori(world_pos.y / cell_size))


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell) * cell_size + Vector2(cell_size, cell_size) * 0.5


func is_solid(cell: Vector2i) -> bool:
	if not astar.is_in_boundsv(cell):
		return true
	return astar.is_point_solid(cell)


func is_walkable_world(world_pos: Vector2) -> bool:
	return not is_solid(world_to_cell(world_pos))


## Celda libre mas cercana en anillos crecientes. Necesario porque un actor
## puede quedar solapado con una pared (empujado, spawn ajustado) y A* fallaria
## al pedirle una ruta desde una celda solida.
func nearest_free_cell(cell: Vector2i, max_radius: int = 6) -> Vector2i:
	if not is_solid(cell):
		return cell
	for r in range(1, max_radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				# Solo el perimetro del anillo actual.
				if absi(dx) != r and absi(dy) != r:
					continue
				var probe := cell + Vector2i(dx, dy)
				if not is_solid(probe):
					return probe
	return cell


## Ruta en coordenadas de mundo. Vacia si no hay camino.
func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var from_cell := nearest_free_cell(world_to_cell(from_world))
	var to_cell := nearest_free_cell(world_to_cell(to_world))
	if not astar.is_in_boundsv(from_cell) or not astar.is_in_boundsv(to_cell):
		return PackedVector2Array()
	if from_cell == to_cell:
		return PackedVector2Array([to_world])
	return astar.get_point_path(from_cell, to_cell)


## Todas las celdas transitables del nivel (para elegir destinos de patrulla y
## puntos de huida).
func free_cells() -> Array:
	var out: Array = []
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var c := Vector2i(x, y)
			if not astar.is_point_solid(c):
				out.append(c)
	return out
