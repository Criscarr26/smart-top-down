class_name Crossover
extends RefCounted
## Tecnicas de cruce. El PDF exige al menos una (seccion 3.2); es la variable
## (vii) del benchmark. Se implementan dos para poder comparar.

enum Mode { UNIFORM, ONE_POINT }

const MODE_NAMES := {
	Mode.UNIFORM: "uniforme",
	Mode.ONE_POINT: "un_punto",
}


static func mode_name(mode: int) -> String:
	return MODE_NAMES.get(mode, "desconocido")


static func mode_from_name(text: String) -> int:
	for k in MODE_NAMES:
		if MODE_NAMES[k] == text:
			return k
	return Mode.UNIFORM


## `frozen` son indices de parametros que NO se recombinan: el hijo los hereda
## siempre del primer padre. Implementa la recomendacion IV.2 del PDF (congelar
## los sensores irrelevantes para el nivel).
static func combine(a: Genome, b: Genome, mode: int, frozen: Dictionary = {}) -> Genome:
	match mode:
		Mode.ONE_POINT:
			return _one_point(a, b, frozen)
		_:
			return _uniform(a, b, frozen)


## Cruce uniforme: para cada peso se elige al azar de que padre viene. Mezcla
## mas agresivamente que el de un punto, lo que va bien aqui porque los pesos de
## una red densa no tienen la contiguedad que si asume el cruce por bloques.
static func _uniform(a: Genome, b: Genome, frozen: Dictionary) -> Genome:
	var child := Genome.new()
	var n := a.size()
	child.params.resize(n)
	for i in n:
		if frozen.has(i):
			child.params[i] = a.params[i]
		else:
			child.params[i] = a.params[i] if Rng.randbool() else b.params[i]
	return child


## Cruce de un punto: corta el vector en una posicion y pega las dos mitades.
static func _one_point(a: Genome, b: Genome, frozen: Dictionary) -> Genome:
	var child := Genome.new()
	var n := a.size()
	child.params.resize(n)
	var cut := Rng.randi_range(1, maxi(1, n - 1))
	for i in n:
		if frozen.has(i):
			child.params[i] = a.params[i]
		else:
			child.params[i] = a.params[i] if i < cut else b.params[i]
	return child
