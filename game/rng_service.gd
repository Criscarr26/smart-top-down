extends Node
## Fuente unica de aleatoriedad del proyecto. Autoload: Rng.
##
## Nunca usar randf()/randi() globales en el codigo del juego: el benchmark debe
## ser reproducible, y para eso toda la aleatoriedad tiene que salir de un
## generador con semilla explicita que se reinicia al principio de cada episodio.

var _rng := RandomNumberGenerator.new()
var _seed: int = 0

func _ready() -> void:
	reseed(12345)

## Reinicia el generador. Llamar al inicio de cada episodio y de cada corrida de
## entrenamiento con una semilla derivada del indice, para que la corrida sea
## repetible pero los episodios no sean identicos entre si.
func reseed(new_seed: int) -> void:
	_seed = new_seed
	_rng.seed = new_seed
	_rng.state = 0

func get_seed() -> int:
	return _seed

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randfn(mean: float, deviation: float) -> float:
	return _rng.randfn(mean, deviation)

func randbool() -> bool:
	return _rng.randf() < 0.5

## Vector unitario en direccion aleatoria.
func rand_direction() -> Vector2:
	return Vector2.RIGHT.rotated(_rng.randf() * TAU)

## Elige un elemento al azar de un array (null si esta vacio).
func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]

## Devuelve una copia barajada (Fisher-Yates con el generador con semilla).
func shuffled(arr: Array) -> Array:
	var out := arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
