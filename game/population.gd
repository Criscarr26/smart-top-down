class_name Population
extends RefCounted
## Poblacion del algoritmo genetico y su bucle generacional:
##   inicializacion -> simulacion -> evaluacion -> reproduccion -> repeticion
## (el bucle generacional). La simulacion y la evaluacion las hace el Trainer;
## esta clase se ocupa de la reproduccion.

var config: GAConfig
var genomes: Array = []
var generation: int = 0
## Indices de parametros excluidos de cruce y mutacion (sensores congelados).
var frozen: Dictionary = {}

var _param_count: int = 0
## Una entrada por generacion: mejor / medio / peor fitness. Para graficar la
## curva de convergencia.
var history: Array = []


func _init(p_config: GAConfig, param_count: int, frozen_set: Dictionary = {}) -> void:
	config = p_config
	_param_count = param_count
	frozen = frozen_set


func initialize() -> void:
	genomes.clear()
	generation = 0
	history.clear()
	for _i in config.population_size:
		genomes.append(Genome.create(_param_count, config.init_mode, config.init_scale))


## Siembra la poblacion a partir de un individuo ya entrenado.
##
## Implementa la siembra entre etapas: "al iniciar el entrenamiento de un
## escenario tomar el mejor agente del anterior". El elite entra intacto y el
## resto son copias mutadas suyas, de forma que la nueva poblacion arranca
## alrededor de una solucion que ya funciona en vez de desde cero.
func seed_from(seed_genome: Genome) -> void:
	genomes.clear()
	generation = 0
	history.clear()
	genomes.append(seed_genome.clone())
	while genomes.size() < config.population_size:
		var child := seed_genome.clone()
		child.fitness = 0.0
		# Mutacion mas fuerte que la de rutina: hace falta diversidad para
		# adaptarse al escenario nuevo, no solo afinar el anterior.
		Mutation.apply(child, config.mutation_mode,
				minf(1.0, config.mutation_rate * 2.0),
				config.mutation_strength, frozen)
		genomes.append(child)


func best() -> Genome:
	if genomes.is_empty():
		return null
	var top: Genome = genomes[0]
	for g in genomes:
		if (g as Genome).fitness > top.fitness:
			top = g
	return top


func average_fitness() -> float:
	if genomes.is_empty():
		return 0.0
	var total := 0.0
	for g in genomes:
		total += (g as Genome).fitness
	return total / float(genomes.size())


## Reproduccion: elitismo + seleccion + cruce + mutacion. Llamar DESPUES de
## haber asignado fitness a todos los individuos.
func evolve() -> void:
	var ranked := Selection.sorted_by_fitness(genomes)
	_record_history(ranked)

	# Elitismo: los mejores pasan sin tocar. Sin esto, un cruce desafortunado
	# puede perder el mejor genoma de la generacion y el fitness maximo baja
	# entre generaciones, cosa que no deberia pasar nunca.
	var next_gen: Array = []
	for i in mini(config.elite_count, ranked.size()):
		next_gen.append((ranked[i] as Genome).clone())

	# Piscina reproductora: la fraccion superior segun la tasa de seleccion.
	var pool_size: int = maxi(2, int(round(ranked.size() * config.selection_rate)))
	var pool: Array = ranked.slice(0, mini(pool_size, ranked.size()))

	while next_gen.size() < config.population_size:
		var parent_a := Selection.pick(pool, config.selection_mode, config.tournament_size)
		var parent_b := Selection.pick(pool, config.selection_mode, config.tournament_size)
		if parent_a == null or parent_b == null:
			break
		var child := Crossover.combine(parent_a, parent_b, config.crossover_mode, frozen)
		Mutation.apply(child, config.mutation_mode, config.mutation_rate,
				config.mutation_strength, frozen)
		child.fitness = 0.0
		next_gen.append(child)

	genomes = next_gen
	generation += 1


func _record_history(ranked: Array) -> void:
	if ranked.is_empty():
		return
	history.append({
		"generacion": generation,
		"mejor": (ranked[0] as Genome).fitness,
		"medio": average_fitness(),
		"peor": (ranked[ranked.size() - 1] as Genome).fitness,
	})


func history_rows() -> Array:
	return history
