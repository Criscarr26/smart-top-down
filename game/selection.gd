class_name Selection
extends RefCounted
## Tecnicas de seleccion. El PDF exige probar al menos dos (seccion 3.2), y son
## la variable (vi) del benchmark cuantitativo.

enum Mode { TOURNAMENT, ROULETTE }

const MODE_NAMES := {
	Mode.TOURNAMENT: "torneo",
	Mode.ROULETTE: "ruleta",
}


static func mode_name(mode: int) -> String:
	return MODE_NAMES.get(mode, "desconocido")


static func mode_from_name(text: String) -> int:
	for k in MODE_NAMES:
		if MODE_NAMES[k] == text:
			return k
	return Mode.TOURNAMENT


static func pick(population: Array, mode: int, tournament_size: int = 3) -> Genome:
	if population.is_empty():
		return null
	match mode:
		Mode.ROULETTE:
			return _roulette(population)
		_:
			return _tournament(population, tournament_size)


## Torneo: coge k individuos al azar y devuelve el mejor. Presion selectiva
## regulable con k, e inmune a la escala del fitness (solo compara).
static func _tournament(population: Array, k: int) -> Genome:
	var size := population.size()
	var best: Genome = population[Rng.randi_range(0, size - 1)]
	for _i in range(1, maxi(1, k)):
		var challenger: Genome = population[Rng.randi_range(0, size - 1)]
		if challenger.fitness > best.fitness:
			best = challenger
	return best


## Ruleta: probabilidad proporcional al fitness.
##
## El fitness de este proyecto puede ser NEGATIVO (un agente que solo recibe
## dano puntua por debajo de cero), y una ruleta con pesos negativos no tiene
## sentido. Por eso se desplaza toda la poblacion para que el peor valga 0 y se
## suma un epsilon, de forma que hasta el peor individuo conserve una
## probabilidad minima de reproducirse y no se pierda diversidad de golpe.
static func _roulette(population: Array) -> Genome:
	var min_fitness := INF
	for g in population:
		min_fitness = minf(min_fitness, (g as Genome).fitness)
	var epsilon := 0.001
	var total := 0.0
	for g in population:
		total += ((g as Genome).fitness - min_fitness) + epsilon
	if total <= 0.0:
		return population[Rng.randi_range(0, population.size() - 1)]

	var r := Rng.randf() * total
	var acc := 0.0
	for g in population:
		acc += ((g as Genome).fitness - min_fitness) + epsilon
		if r <= acc:
			return g
	return population[population.size() - 1]


## Ordena de mejor a peor (no destructivo).
static func sorted_by_fitness(population: Array) -> Array:
	var copy := population.duplicate()
	copy.sort_custom(func(a: Genome, b: Genome) -> bool: return a.fitness > b.fitness)
	return copy
