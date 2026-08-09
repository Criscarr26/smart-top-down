class_name Genome
extends RefCounted
## Un individuo: el vector plano de pesos y sesgos de la red, mas su fitness.

## Estrategias de inicializacion de pesos. Es la variable (iii) del benchmark
## cuantitativo del PDF: "configuracion de peso inicial (aleatorio, pesos
## iguales, pesos nulos)".
enum Init { RANDOM, EQUAL, ZERO }

const INIT_NAMES := {
	Init.RANDOM: "aleatorio",
	Init.EQUAL: "iguales",
	Init.ZERO: "nulos",
}

var params := PackedFloat32Array()
var fitness: float = 0.0
## Metricas crudas del ultimo episodio evaluado; alimentan el informe.
var stats: Dictionary = {}


static func init_name(mode: int) -> String:
	return INIT_NAMES.get(mode, "desconocido")


static func init_from_name(text: String) -> int:
	for k in INIT_NAMES:
		if INIT_NAMES[k] == text:
			return k
	return Init.RANDOM


static func create(size: int, mode: int, scale: float = 1.0) -> Genome:
	var g := Genome.new()
	g.params.resize(size)
	match mode:
		Init.ZERO:
			# Con todos los pesos a cero la red devuelve la misma salida para
			# cualquier entrada, asi que la primera generacion es ciega y todo
			# el progreso depende de la mutacion. Se incluye porque el PDF lo
			# pide como configuracion a comparar, y sirve justo para mostrar eso.
			for i in size:
				g.params[i] = 0.0
		Init.EQUAL:
			for i in size:
				g.params[i] = 0.5
		_:
			for i in size:
				g.params[i] = Rng.randf_range(-scale, scale)
	return g


func clone() -> Genome:
	var g := Genome.new()
	g.params = params.duplicate()
	g.fitness = fitness
	g.stats = stats.duplicate()
	return g


func size() -> int:
	return params.size()


func to_dict() -> Dictionary:
	return {
		"params": Array(params),
		"fitness": fitness,
		"stats": stats,
	}


static func from_dict(d: Dictionary) -> Genome:
	var g := Genome.new()
	var raw: Array = d.get("params", [])
	g.params.resize(raw.size())
	for i in raw.size():
		g.params[i] = float(raw[i])
	g.fitness = float(d.get("fitness", 0.0))
	g.stats = d.get("stats", {})
	return g
