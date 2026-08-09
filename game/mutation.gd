class_name Mutation
extends RefCounted
## Tecnicas de mutacion. El PDF exige al menos dos (seccion 3.2); son la
## variable (v) del benchmark cuantitativo.

enum Mode { GAUSSIAN, RANDOM_RESET }

const MODE_NAMES := {
	Mode.GAUSSIAN: "gaussiana",
	Mode.RANDOM_RESET: "reemplazo_aleatorio",
}


static func mode_name(mode: int) -> String:
	return MODE_NAMES.get(mode, "desconocido")


static func mode_from_name(text: String) -> int:
	for k in MODE_NAMES:
		if MODE_NAMES[k] == text:
			return k
	return Mode.GAUSSIAN


## Muta el genoma EN SITIO.
##   rate     probabilidad por peso de ser mutado
##   strength desviacion tipica (GAUSSIAN) o amplitud del nuevo valor (RESET)
##   frozen   indices excluidos de la mutacion (recomendacion IV.2 del PDF)
static func apply(genome: Genome, mode: int, rate: float, strength: float,
		frozen: Dictionary = {}) -> void:
	match mode:
		Mode.RANDOM_RESET:
			_random_reset(genome, rate, strength, frozen)
		_:
			_gaussian(genome, rate, strength, frozen)


## Gaussiana: suma ruido normal al peso existente. Exploracion local -- afina
## una politica que ya funciona sin destruirla.
static func _gaussian(genome: Genome, rate: float, strength: float, frozen: Dictionary) -> void:
	for i in genome.size():
		if frozen.has(i):
			continue
		if Rng.randf() < rate:
			genome.params[i] = clampf(
					genome.params[i] + Rng.randfn(0.0, strength), -8.0, 8.0)


## Reemplazo aleatorio: descarta el peso y pone uno nuevo al azar. Exploracion
## global -- es lo que permite salir de un optimo local en el que la mutacion
## gaussiana se quedaria dando vueltas.
static func _random_reset(genome: Genome, rate: float, strength: float, frozen: Dictionary) -> void:
	for i in genome.size():
		if frozen.has(i):
			continue
		if Rng.randf() < rate:
			genome.params[i] = Rng.randf_range(-strength, strength)


## Construye el conjunto de indices congelados a partir de los sensores
## irrelevantes de un nivel. Devuelve un Dictionary usado como set (la busqueda
## por clave es O(1); con un Array seria O(n) por cada peso de cada individuo de
## cada generacion).
static func frozen_set(net: NeuralNetwork, frozen_sensors: Array) -> Dictionary:
	var out := {}
	for s in frozen_sensors:
		for idx in net.input_weight_indices(int(s)):
			out[idx] = true
	return out
