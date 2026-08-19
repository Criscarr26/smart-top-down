class_name GAConfig
extends RefCounted
## Todos los hiperparametros del optimizador en un solo objeto.
##
## Cada campo de aqui es una columna del CSV del benchmark y una de las
## "variables para comparar" de la seccion 3.3.4.c del PDF. Tenerlos juntos y
## serializables es lo que permite que el harness barra la matriz de
## experimentos sin tocar codigo.

# --- Poblacion (variable i) ---------------------------------------------------
var population_size: int = 24
var generations: int = 40
## Individuos que pasan intactos a la siguiente generacion.
var elite_count: int = 2
## Episodios que juega cada individuo por generacion. Mas episodios = fitness
## menos ruidoso pero evaluacion mas cara.
var episodes_per_individual: int = 2

# --- Mutacion (variables ii y v) ---------------------------------------------
var mutation_rate: float = 0.15
var mutation_strength: float = 0.4
var mutation_mode: int = Mutation.Mode.GAUSSIAN

# --- Seleccion (variables iv y vi) -------------------------------------------
var selection_mode: int = Selection.Mode.TOURNAMENT
## Fraccion superior de la poblacion elegible para reproducirse.
var selection_rate: float = 0.5
var tournament_size: int = 3

# --- Cruce (variable vii) ----------------------------------------------------
var crossover_mode: int = Crossover.Mode.UNIFORM

# --- Pesos iniciales (variable iii) ------------------------------------------
var init_mode: int = Genome.Init.RANDOM
var init_scale: float = 1.0

# --- Thresholding (variable viii) --------------------------------------------
var thresholding_mode: int = Thresholding.Mode.SOFTMAX_ARGMAX
var threshold_value: float = 0.25

# --- Topologia ---------------------------------------------------------------
## Capas ocultas. [] = red shallow (solo entrada y salida), que el PDF
## recomienda probar explicitamente en IV.3.
var hidden_layers: Array = [10, 6]


## Topologia completa: sensores -> ocultas -> actuadores.
func topology() -> Array:
	var t: Array = [AgentSensors.COUNT]
	t.append_array(hidden_layers)
	t.append(AgentActions.COUNT)
	return t


func is_shallow() -> bool:
	return hidden_layers.is_empty()


func duplicate_config() -> GAConfig:
	var c := GAConfig.new()
	c.population_size = population_size
	c.generations = generations
	c.elite_count = elite_count
	c.episodes_per_individual = episodes_per_individual
	c.mutation_rate = mutation_rate
	c.mutation_strength = mutation_strength
	c.mutation_mode = mutation_mode
	c.selection_mode = selection_mode
	c.selection_rate = selection_rate
	c.tournament_size = tournament_size
	c.crossover_mode = crossover_mode
	c.init_mode = init_mode
	c.init_scale = init_scale
	c.thresholding_mode = thresholding_mode
	c.threshold_value = threshold_value
	c.hidden_layers = hidden_layers.duplicate()
	return c


## Representacion plana para las columnas del CSV.
func to_dict() -> Dictionary:
	return {
		"num_pobladores": population_size,
		"generaciones": generations,
		"elite": elite_count,
		"episodios_por_individuo": episodes_per_individual,
		"tasa_mutacion": mutation_rate,
		"fuerza_mutacion": mutation_strength,
		"tecnica_mutacion": Mutation.mode_name(mutation_mode),
		"tecnica_seleccion": Selection.mode_name(selection_mode),
		"tasa_seleccion": selection_rate,
		"tam_torneo": tournament_size,
		"tecnica_cruce": Crossover.mode_name(crossover_mode),
		"pesos_iniciales": Genome.init_name(init_mode),
		"thresholding": Thresholding.mode_name(thresholding_mode),
		"valor_umbral": threshold_value,
		"topologia": "-".join(topology().map(func(v: int) -> String: return str(v))),
	}


static func from_dict(d: Dictionary) -> GAConfig:
	var c := GAConfig.new()
	c.population_size = int(d.get("num_pobladores", c.population_size))
	c.generations = int(d.get("generaciones", c.generations))
	c.elite_count = int(d.get("elite", c.elite_count))
	c.episodes_per_individual = int(d.get("episodios_por_individuo", c.episodes_per_individual))
	c.mutation_rate = float(d.get("tasa_mutacion", c.mutation_rate))
	c.mutation_strength = float(d.get("fuerza_mutacion", c.mutation_strength))
	c.mutation_mode = Mutation.mode_from_name(str(d.get("tecnica_mutacion", "gaussiana")))
	c.selection_mode = Selection.mode_from_name(str(d.get("tecnica_seleccion", "torneo")))
	c.selection_rate = float(d.get("tasa_seleccion", c.selection_rate))
	c.tournament_size = int(d.get("tam_torneo", c.tournament_size))
	c.crossover_mode = Crossover.mode_from_name(str(d.get("tecnica_cruce", "uniforme")))
	c.init_mode = Genome.init_from_name(str(d.get("pesos_iniciales", "aleatorio")))
	c.thresholding_mode = Thresholding.mode_from_name(str(d.get("thresholding", "softmax_argmax")))
	c.threshold_value = float(d.get("valor_umbral", c.threshold_value))
	if d.has("capas_ocultas"):
		# JSON devuelve TODO numero como float, asi que [10, 6] vuelve como
		# [10.0, 6.0] y la topologia acabaria llevando floats donde
		# NeuralNetwork espera enteros. Se convierte aqui, que es por donde
		# entran las configuraciones guardadas en disco.
		var capas: Array = []
		for v in d["capas_ocultas"]:
			var n := int(v)
			if n > 0:
				capas.append(n)
		c.hidden_layers = capas
	return c


## Etiqueta corta para nombres de archivo y logs.
func label() -> String:
	return "p%d_m%.2f_%s_%s_%s_%s_%s" % [
		population_size, mutation_rate,
		Mutation.mode_name(mutation_mode),
		Selection.mode_name(selection_mode),
		Crossover.mode_name(crossover_mode),
		Genome.init_name(init_mode),
		"shallow" if is_shallow() else "deep",
	]
