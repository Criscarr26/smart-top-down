class_name Effects
extends Node2D
## Capa de efectos de la partida: numeros de dano, chispas de impacto y
## estallido de muerte.
##
## SOLO PRESENTACION. No forma parte de la simulacion y no existe durante el
## barrido: el Arena no la crea, la crea quien dibuja la partida. Por eso puede
## usar el `delta` real del motor y randf() global sin romper la reproducibilidad
## de nada -- ninguna de las dos cosas alimenta jamas un resultado.
##
## Todo se dibuja desde un unico _draw en vez de crear un nodo por particula. Un
## combate con seis enemigos genera cientos de chispas por segundo, y otros
## tantos nodos serian mas coste de arbol que de dibujado.

const DURACION_NUMERO := 0.85
const DURACION_CHISPA := 0.45
const MAX_ELEMENTOS := 400

var _numeros: Array = []     # {pos, texto, color, t}
var _particulas: Array = []  # {pos, vel, color, radio, t, vida}


func _ready() -> void:
	# Por encima de los actores, para que un numero no quede tapado por el
	# cuerpo del enemigo al que se le acaba de pegar.
	z_index = 100


func _process(delta: float) -> void:
	if _numeros.is_empty() and _particulas.is_empty():
		return

	for i in range(_numeros.size() - 1, -1, -1):
		var n: Dictionary = _numeros[i]
		n["t"] += delta
		# Sube y frena: el movimiento constante se lee como un sprite, el
		# desacelerado se lee como un impacto.
		n["pos"] += Vector2(0.0, -46.0 * delta * (1.0 - n["t"] / DURACION_NUMERO))
		if n["t"] >= DURACION_NUMERO:
			_numeros.remove_at(i)

	for i in range(_particulas.size() - 1, -1, -1):
		var p: Dictionary = _particulas[i]
		p["t"] += delta
		p["pos"] += p["vel"] * delta
		p["vel"] *= 1.0 - minf(1.0, 6.0 * delta)   # rozamiento
		if p["t"] >= p["vida"]:
			_particulas.remove_at(i)

	queue_redraw()


func _draw() -> void:
	var fuente := ThemeDB.fallback_font
	for p in _particulas:
		var t: float = clampf(p["t"] / p["vida"], 0.0, 1.0)
		var c: Color = p["color"]
		c.a = 1.0 - t
		draw_circle(p["pos"], float(p["radio"]) * (1.0 - t * 0.6), c)
	for n in _numeros:
		var t: float = clampf(n["t"] / DURACION_NUMERO, 0.0, 1.0)
		var c: Color = n["color"]
		c.a = 1.0 - t * t          # opaco al principio, se apaga al final
		var tam := int(round(15.0 - 3.0 * t))
		# Sombra primero: sobre suelo claro un numero blanco se pierde.
		draw_string(fuente, n["pos"] + Vector2(1, 1), str(n["texto"]),
				HORIZONTAL_ALIGNMENT_CENTER, -1, tam, Color(0, 0, 0, c.a * 0.7))
		draw_string(fuente, n["pos"], str(n["texto"]),
				HORIZONTAL_ALIGNMENT_CENTER, -1, tam, c)


func numero(pos: Vector2, texto: String, color: Color) -> void:
	if _numeros.size() >= MAX_ELEMENTOS:
		return
	_numeros.append({
		"pos": pos + Vector2(randf_range(-7.0, 7.0), -GameConfig.ACTOR_RADIUS - 6.0),
		"texto": texto, "color": color, "t": 0.0,
	})
	queue_redraw()


## Chispas de un golpe. `bloqueado` cambia el color para que se distinga de un
## vistazo lo que entro de lo que paro el escudo.
func impacto(pos: Vector2, cantidad: int, color: Color) -> void:
	for _i in cantidad:
		if _particulas.size() >= MAX_ELEMENTOS:
			return
		var ang := randf() * TAU
		_particulas.append({
			"pos": pos,
			"vel": Vector2.RIGHT.rotated(ang) * randf_range(60.0, 210.0),
			"color": color,
			"radio": randf_range(1.6, 3.4),
			"t": 0.0,
			"vida": DURACION_CHISPA * randf_range(0.6, 1.3),
		})
	queue_redraw()


func muerte(pos: Vector2, color: Color) -> void:
	impacto(pos, 26, color)
	for _i in 10:
		if _particulas.size() >= MAX_ELEMENTOS:
			return
		_particulas.append({
			"pos": pos,
			"vel": Vector2.RIGHT.rotated(randf() * TAU) * randf_range(20.0, 90.0),
			"color": Color(0.85, 0.85, 0.9),
			"radio": randf_range(2.5, 5.0),
			"t": 0.0,
			"vida": 0.9,
		})
	queue_redraw()


func limpiar() -> void:
	_numeros.clear()
	_particulas.clear()
	queue_redraw()
