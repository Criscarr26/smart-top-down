class_name LevelData
extends RefCounted
## Definicion de un nivel a partir de un mapa ASCII.
##
## Se eligio ASCII en vez de TileMap por una razon concreta del proyecto: el
## benchmark construye y destruye decenas de arenas por segundo en headless, y
## un mapa ASCII se parsea sin tocar disco ni instanciar recursos. Ademas es la
## misma fuente de verdad para las dos representaciones que exige la spec (grid
## logico para A* y colisiones fisicas para el movimiento), asi que no pueden
## desincronizarse.
##
## Leyenda:
##   #  pared solida          ^  pua (mata al contacto)
##   .  suelo transitable     +  pocion de curacion
##   P  aparicion del jugador  E  aparicion de enemigo

var width: int = 0
var height: int = 0
var walls: Array[Vector2i] = []
var spikes: Array[Vector2i] = []
var potions: Array[Vector2i] = []
var player_spawns: Array[Vector2i] = []
var enemy_spawns: Array[Vector2i] = []
var name: String = "level"


static func from_ascii(map_name: String, rows: Array) -> LevelData:
	var data := LevelData.new()
	data.name = map_name
	data.height = rows.size()
	if data.height == 0:
		push_error("LevelData '%s': mapa vacio" % map_name)
		return data
	data.width = String(rows[0]).length()

	for y in rows.size():
		var line := String(rows[y])
		# Falla ruidosamente: una fila corta desalinea todo el nivel y produce
		# bugs de pathfinding dificiles de rastrear.
		if line.length() != data.width:
			push_error("LevelData '%s': fila %d mide %d, se esperaba %d"
					% [map_name, y, line.length(), data.width])
		for x in line.length():
			var cell := Vector2i(x, y)
			match line[x]:
				"#": data.walls.append(cell)
				"^": data.spikes.append(cell)
				"+": data.potions.append(cell)
				"P": data.player_spawns.append(cell)
				"E": data.enemy_spawns.append(cell)
				_: pass
	return data


func region() -> Rect2i:
	return Rect2i(0, 0, width, height)


## Celdas no transitables para A*.
##
## Las puas SI entran aqui aunque no sean solidas fisicamente. Es deliberado:
## un actor que planifica su ruta las esquiva, pero uno que se mueve en linea recta -- huyendo,
## persiguiendo a la vista, o siguiendo la salida cruda de la red neuronal --
## puede pisarlas y morir. Esa asimetria es justo lo que hace que las puas sean
## una presion de seleccion real para el algoritmo genetico.
func blocked_cells() -> Array:
	var out: Array = []
	out.append_array(walls)
	out.append_array(spikes)
	return out


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * GameConfig.CELL_SIZE + Vector2.ONE * (GameConfig.CELL_SIZE * 0.5)


## Runs horizontales de pared, para generar un CollisionShape2D por tramo en vez
## de uno por celda. Con 50 arenas en paralelo la diferencia en coste de
## broadphase es notable.
func wall_runs() -> Array:
	var wall_set := {}
	for w in walls:
		wall_set[w] = true
	var runs: Array = []
	for y in height:
		var x := 0
		while x < width:
			if not wall_set.has(Vector2i(x, y)):
				x += 1
				continue
			var start := x
			while x < width and wall_set.has(Vector2i(x, y)):
				x += 1
			runs.append(Rect2i(start, y, x - start, 1))
	return runs
