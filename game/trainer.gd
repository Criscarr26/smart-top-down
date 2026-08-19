class_name Trainer
extends Node
## Bucle de entrenamiento neuroevolutivo con curriculum incremental.
##
## Implementa la seccion 2.2 del PDF (inicializacion -> simulacion -> evaluacion
## -> reproduccion -> repeticion -> validacion) y su recomendacion IV.1: el
## entrenamiento avanza escenario por escenario y cada etapa ARRANCA CON EL
## MEJOR AGENTE DE LA ANTERIOR, en vez de empezar de cero cada vez.
##
## Etapas del curriculum, en el orden que exige la seccion 3.3.1:
##   1. contra enemigo Tipo A
##   2. contra enemigo Tipo B
##   3. contra enemigo Tipo C
##   4. contra "jugador humano" (bot sustituto, ver ScriptedBot)

signal stage_started(stage_index: int, stage_name: String)
signal generation_completed(stage_index: int, generation: int, stats: Dictionary)
signal training_finished(best: Genome)

var config: GAConfig
var pool: SimPool
var population: Population

## Nivel usado en cada etapa. Se rotan los tres de entrenamiento para que el
## agente no memorice la geometria de uno solo; el nivel de validacion queda
## fuera a proposito.
var training_levels: Array = []
var log_enabled: bool = true

## Pesos del fitness con los que se entrena. null = los documentados en Fitness.
## La pantalla "Entrenar agente" pone aqui los que edite el usuario.
var fitness_weights: Fitness.Weights = null
## Duracion de cada episodio de entrenamiento, en ticks.
var episode_ticks: int = GameConfig.TRAINING_EPISODE_TICKS

## Peticion de parada. Se comprueba ENTRE generaciones, no dentro del lote: el
## SimPool no sabe cancelar arenas a medias y cortarlo dejaria ranuras ocupadas y
## un `await` sin resolver. El lote en curso termina (segundos) y ahi se sale,
## devolviendo el mejor genoma que hubiera hasta ese momento.
var abort: bool = false
## Pausa cooperativa. Se comprueba entre generaciones, en el mismo punto que
## `abort`: dejar un lote a medias obligaria a cancelar arenas, y el SimPool no
## sabe hacerlo sin quedarse con ranuras ocupadas.
var paused: bool = false

## Resultados crudos del ultimo lote, para poder resumir la generacion con datos
## reales (victorias, ticks, acciones) en vez de solo con el fitness.
var _last_results: Array = []

var _net_template: NeuralNetwork
var _frozen: Dictionary = {}
var _stage_bests: Array = []
var _curve: Array = []


func _init(p_config: GAConfig, p_pool: SimPool) -> void:
	config = p_config
	pool = p_pool
	name = "Trainer"
	training_levels = LevelMaps.training_levels()


## Etapas por defecto: los 4 oponentes de la seccion 3.3.1.
static func default_curriculum() -> Array:
	return [
		{"name": "vs_tipo_A", "type": "A", "count": 1, "opponent": ArenaSpec.Opponent.NONE},
		{"name": "vs_tipo_B", "type": "B", "count": 1, "opponent": ArenaSpec.Opponent.NONE},
		{"name": "vs_tipo_C", "type": "C", "count": 1, "opponent": ArenaSpec.Opponent.NONE},
		{"name": "vs_humano_bot", "type": "", "count": 0, "opponent": ArenaSpec.Opponent.BOT},
		# Quinta etapa, anadida con el Tipo D. Va la ultima porque es la unica
		# que exige priorizar entre dos objetivos, y sembrarla con un agente que
		# ya sabe pelear es lo que le da alguna posibilidad de descubrirlo.
		{"name": "vs_escolta_D", "type": "", "count": 0, "opponent": ArenaSpec.Opponent.NONE,
			"squad": [{"type": "A", "count": 1}, {"type": "D", "count": 1}]},
	]


## Entrena el curriculum completo y devuelve el mejor genoma final.
func train(curriculum: Array = []) -> Genome:
	if curriculum.is_empty():
		curriculum = default_curriculum()

	_net_template = NeuralNetwork.new(config.topology())
	population = Population.new(config, _net_template.param_count(), {})
	_stage_bests.clear()
	_curve.clear()

	var carried: Genome = null
	for stage_index in curriculum.size():
		if abort:
			break
		var stage: Dictionary = curriculum[stage_index]
		stage_started.emit(stage_index, str(stage.get("name", "etapa")))

		# La mascara de congelacion se recalcula en cada etapa: que sensores son
		# irrelevantes depende del oponente de la etapa, no del run entero.
		_frozen = _build_frozen_set(stage)
		population.frozen = _frozen

		if carried == null:
			population.initialize()
		else:
			# Recomendacion IV.1 del PDF: sembrar con el mejor de la etapa previa.
			population.seed_from(carried)

		for gen in config.generations:
			var specs := _build_generation_specs(stage, stage_index, gen)
			var results: Array = await pool.run_batch(specs)
			_assign_fitness(results)
			var stats := _generation_stats(stage_index, gen, str(stage.get("name", "")))
			_curve.append(stats)
			generation_completed.emit(stage_index, gen, stats)
			if log_enabled:
				print("  [%s] gen %2d/%d  mejor=%8.2f  medio=%8.2f"
						% [stage.get("name", ""), gen + 1, config.generations,
						stats["mejor"], stats["medio"]])
			if abort:
				break
			while paused and not abort:
				await get_tree().process_frame
			if abort:
				break
			# En la ultima generacion no hace falta reproducir.
			if gen < config.generations - 1:
				population.evolve()

		var stage_best := population.best()
		if stage_best != null:
			carried = stage_best.clone()
			_stage_bests.append({"etapa": stage.get("name", ""), "fitness": carried.fitness})

	training_finished.emit(carried)
	return carried


## Un spec por individuo y por episodio. El indice del individuo viaja en la
## semilla para que dos individuos de la misma generacion no jueguen partidas
## identicas, pero la generacion entera sea reproducible.
func _build_generation_specs(stage: Dictionary, stage_index: int, generation: int) -> Array:
	var specs: Array = []
	for i in population.genomes.size():
		for e in config.episodes_per_individual:
			var spec := ArenaSpec.create("train_%s" % stage.get("name", ""), "Entrenamiento")
			# Rota los tres niveles de entrenamiento entre episodios.
			spec.level_name = training_levels[(generation + e) % training_levels.size()]
			spec.opponent_kind = int(stage.get("opponent", ArenaSpec.Opponent.NONE))
			var type_id := str(stage.get("type", ""))
			if type_id != "" and int(stage.get("count", 0)) > 0:
				spec.with_enemies(type_id, int(stage.get("count", 1)))
			# Una etapa puede enfrentar a VARIOS tipos a la vez (la escolta del
			# sanador). El campo "type" cubre el caso de un solo tipo, que son
			# las cuatro etapas del PDF; "squad" cubre el resto.
			if stage.get("squad") is Array:
				for entrada in (stage["squad"] as Array):
					spec.with_enemies(str((entrada as Dictionary).get("type", "A")),
							int((entrada as Dictionary).get("count", 1)))
			spec.agent_count = 1
			spec.agent_genome = population.genomes[i]
			spec.ga_config = config
			spec.fsm_opposes_agent = true
			spec.fitness_weights = fitness_weights
			spec.seed = _episode_seed(stage_index, generation, i, e)
			spec.max_ticks = episode_ticks
			specs.append(spec)
	return specs


func _episode_seed(stage_index: int, generation: int, individual: int, episode: int) -> int:
	# Mezcla simple pero suficiente para descorrelacionar las cuatro dimensiones.
	return int(Rng.get_seed()) \
			+ stage_index * 1_000_003 \
			+ generation * 10_007 \
			+ individual * 101 \
			+ episode * 7


## El fitness de un individuo es la MEDIA de sus episodios. Usar el maximo
## premiaria al que tuvo suerte con una semilla facil, y el GA acabaria
## seleccionando por suerte en vez de por politica.
func _assign_fitness(results: Array) -> void:
	_last_results = results
	var per_individual: int = maxi(1, config.episodes_per_individual)
	for i in population.genomes.size():
		var genome: Genome = population.genomes[i]
		var total := 0.0
		var counted := 0
		for e in per_individual:
			var idx: int = i * per_individual + e
			if idx >= results.size():
				continue
			var r = results[idx]
			if r == null or not (r is Dictionary):
				continue
			total += float(r.get("fitness", 0.0))
			counted += 1
			if e == 0:
				genome.stats = r
		genome.fitness = 0.0 if counted == 0 else total / float(counted)


## Resumen de la generacion. Ademas del fitness incluye lo que de verdad paso en
## los episodios: cuantos se ganaron, cuantos ticks se simularon y en que se
## gasto la decision. Sin esto, un panel de metricas solo podria ensenar el
## fitness, que es un numero sin unidades; con esto puede ensenar "gana el 40%".
func _generation_stats(stage_index: int, generation: int, stage_name: String) -> Dictionary:
	var ranked := Selection.sorted_by_fitness(population.genomes)
	var victorias := 0
	var episodios := 0
	var ticks := 0
	var kills := 0
	var acciones: Dictionary = {}
	for r in _last_results:
		if not (r is Dictionary):
			continue
		var d := r as Dictionary
		episodios += 1
		ticks += int(d.get("ticks", 0))
		kills += int(d.get("kills_agente", 0))
		if str(d.get("ganador", "")) == "agente":
			victorias += 1
		var mezcla = d.get("mezcla_acciones", null)
		if mezcla is Dictionary:
			for k in (mezcla as Dictionary):
				acciones[k] = float(acciones.get(k, 0.0)) + float((mezcla as Dictionary)[k])
	for k in acciones:
		acciones[k] = float(acciones[k]) / float(maxi(1, episodios))

	return {
		"etapa_idx": stage_index,
		"etapa": stage_name,
		"generacion": generation,
		"mejor": (ranked[0] as Genome).fitness if not ranked.is_empty() else 0.0,
		"medio": population.average_fitness(),
		"peor": (ranked[ranked.size() - 1] as Genome).fitness if not ranked.is_empty() else 0.0,
		"episodios": episodios,
		"victorias": victorias,
		"tasa_victoria": 0.0 if episodios == 0 else float(victorias) / float(episodios),
		"ticks": ticks,
		"kills": kills,
		"acciones": acciones,
	}


## Congela los pesos de los sensores irrelevantes para ESTA etapa
## (recomendacion IV.2 del PDF). Solo congela un sensor si es irrelevante en
## TODOS los niveles que rota la etapa: si en alguno importa, hay que seguir
## optimizandolo.
func _build_frozen_set(stage: Dictionary) -> Dictionary:
	# El unico oponente que puede defender es el Tipo B; el bot sustituto del
	# humano tambien bloquea cuando esta bajo presion.
	var opponent_type := str(stage.get("type", ""))
	var opponent_can_defend: bool = opponent_type == "B" \
			or int(stage.get("opponent", ArenaSpec.Opponent.NONE)) == ArenaSpec.Opponent.BOT
	if stage.get("squad") is Array:
		for entrada in (stage["squad"] as Array):
			if str((entrada as Dictionary).get("type", "")) == "B":
				opponent_can_defend = true

	var common: Array = []
	var first := true
	for level_name in training_levels:
		var data := LevelMaps.by_name(level_name)
		var irrelevant := AgentSensors.irrelevant_for_stage(data, opponent_can_defend)
		if first:
			common = irrelevant.duplicate()
			first = false
		else:
			common = common.filter(func(s): return irrelevant.has(s))

	if log_enabled:
		if common.is_empty():
			print("  [%s] sin sensores congelados" % stage.get("name", ""))
		else:
			var names: Array = common.map(func(s: int) -> String: return AgentSensors.NAMES[s])
			print("  [%s] sensores congelados (IV.2 del PDF): %s"
					% [stage.get("name", ""), ", ".join(names)])
	return Mutation.frozen_set(_net_template, common)


## Curva de convergencia completa, para graficar.
func convergence_curve() -> Array:
	return _curve


func stage_summary() -> Array:
	return _stage_bests
