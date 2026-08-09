class_name ExperimentMatrix
extends RefCounted
## Matriz de configuraciones a comparar (seccion 3.3.4.c del PDF).
##
## Se barre UNA VARIABLE A LA VEZ (OFAT) partiendo de una configuracion base, no
## el producto cartesiano completo. El motivo es de coste: con 3 tamanos de
## poblacion x 3 tasas de mutacion x 3 inicializaciones x 2 tasas de seleccion x
## 2 mutaciones x 2 selecciones x 2 cruces x 3 thresholdings x 2 topologias, el
## factorial completo son 2592 entrenamientos. OFAT son 19 y responde la
## pregunta que pide el PDF ("comparar el efecto de cada variable"), que es
## marginal, no de interacciones.
##
## Las tablas de ejemplo del propio PDF confirman esta lectura: sus filas son
## valores sueltos de una variable, no combinaciones.


static func baseline() -> GAConfig:
	var c := GAConfig.new()
	c.population_size = 20
	c.generations = 25
	c.elite_count = 2
	c.episodes_per_individual = 2
	c.mutation_rate = 0.15
	c.mutation_strength = 0.4
	c.mutation_mode = Mutation.Mode.GAUSSIAN
	c.selection_mode = Selection.Mode.TOURNAMENT
	c.selection_rate = 0.5
	c.tournament_size = 3
	c.crossover_mode = Crossover.Mode.UNIFORM
	c.init_mode = Genome.Init.RANDOM
	c.thresholding_mode = Thresholding.Mode.SOFTMAX_ARGMAX
	c.hidden_layers = [10, 6]
	return c


## Devuelve [{ "config": GAConfig, "variable": String, "valor": String }, ...].
## La primera entrada es siempre la base.
static func ofat(base: GAConfig = null) -> Array:
	if base == null:
		base = baseline()
	var out: Array = []
	out.append({"config": base.duplicate_config(), "variable": "base", "valor": "base"})

	# (i) Numero de pobladores
	for n in [10, 50]:
		var c := base.duplicate_config()
		c.population_size = n
		out.append({"config": c, "variable": "num_pobladores", "valor": str(n)})

	# (ii) Tasa de mutacion
	for r in [0.05, 0.30]:
		var c := base.duplicate_config()
		c.mutation_rate = r
		out.append({"config": c, "variable": "tasa_mutacion", "valor": "%.2f" % r})

	# (iii) Configuracion de peso inicial
	for m in [Genome.Init.EQUAL, Genome.Init.ZERO]:
		var c := base.duplicate_config()
		c.init_mode = m
		out.append({"config": c, "variable": "pesos_iniciales", "valor": Genome.init_name(m)})

	# (iv) Tasa de seleccion
	for r in [0.25, 0.80]:
		var c := base.duplicate_config()
		c.selection_rate = r
		out.append({"config": c, "variable": "tasa_seleccion", "valor": "%.2f" % r})

	# (v) Tecnicas de mutacion
	var c_mut := base.duplicate_config()
	c_mut.mutation_mode = Mutation.Mode.RANDOM_RESET
	out.append({"config": c_mut, "variable": "tecnica_mutacion",
			"valor": Mutation.mode_name(Mutation.Mode.RANDOM_RESET)})

	# (vi) Tecnicas de seleccion
	var c_sel := base.duplicate_config()
	c_sel.selection_mode = Selection.Mode.ROULETTE
	out.append({"config": c_sel, "variable": "tecnica_seleccion",
			"valor": Selection.mode_name(Selection.Mode.ROULETTE)})

	# (vii) Tecnicas de cruce
	var c_cross := base.duplicate_config()
	c_cross.crossover_mode = Crossover.Mode.ONE_POINT
	out.append({"config": c_cross, "variable": "tecnica_cruce",
			"valor": Crossover.mode_name(Crossover.Mode.ONE_POINT)})

	# (viii) Tecnica de thresholding
	for t in [Thresholding.Mode.FIXED_THRESHOLD, Thresholding.Mode.STOCHASTIC]:
		var c := base.duplicate_config()
		c.thresholding_mode = t
		out.append({"config": c, "variable": "thresholding", "valor": Thresholding.mode_name(t)})

	# Extra: red shallow (recomendacion IV.3 del PDF, "sumamente recomendable")
	var c_shallow := base.duplicate_config()
	c_shallow.hidden_layers = []
	out.append({"config": c_shallow, "variable": "topologia", "valor": "shallow"})

	var c_deep := base.duplicate_config()
	c_deep.hidden_layers = [16, 12, 8]
	out.append({"config": c_deep, "variable": "topologia", "valor": "profunda_16-12-8"})

	return out


## Version reducida para pruebas de humo: solo la base y dos variantes.
static func quick() -> Array:
	var base := baseline()
	base.population_size = 6
	base.generations = 2
	base.episodes_per_individual = 1
	var out: Array = []
	out.append({"config": base.duplicate_config(), "variable": "base", "valor": "base"})
	var c_shallow := base.duplicate_config()
	c_shallow.hidden_layers = []
	out.append({"config": c_shallow, "variable": "topologia", "valor": "shallow"})
	return out
