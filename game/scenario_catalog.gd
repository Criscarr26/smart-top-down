class_name ScenarioCatalog
extends RefCounted
## Los 10 escenarios de validacion de la seccion 3.3.4.a del PDF, tal cual y en
## el mismo orden.

## Cuantos enemigos son "varios".
const MANY_ENEMIES := 3
## Cuantos agentes son "varios agentes".
const MANY_AGENTS := 3

## Nivel por defecto de la evaluacion. Es el de VALIDACION, no uno de los tres
## de entrenamiento: el PDF pide medir el desempeno "en niveles nunca vistos por
## el agente" (seccion 2.2.6), y evaluar en un nivel entrenado mediria memoria
## del mapa en vez de politica.
const DEFAULT_EVAL_LEVEL := "validation"


static func all(ga_config: GAConfig, genome: Genome,
		level_name: String = DEFAULT_EVAL_LEVEL) -> Array:
	var specs: Array = []

	specs.append(_make("s01_A_1v1", "Un enemigo tipo A vs 1 agente",
			ga_config, genome, level_name, [{"type": "A", "count": 1}], 1))
	specs.append(_make("s02_B_1v1", "Un enemigo tipo B vs 1 agente",
			ga_config, genome, level_name, [{"type": "B", "count": 1}], 1))
	specs.append(_make("s03_C_1v1", "Un enemigo tipo C vs 1 agente",
			ga_config, genome, level_name, [{"type": "C", "count": 1}], 1))
	specs.append(_make("s04_humano_1v1", "Un jugador humano (bot) vs 1 agente",
			ga_config, genome, level_name, [], 1, ArenaSpec.Opponent.BOT))
	specs.append(_make("s05_A_varios", "Varios enemigos tipo A vs 1 agente",
			ga_config, genome, level_name, [{"type": "A", "count": MANY_ENEMIES}], 1))
	specs.append(_make("s06_B_varios", "Varios enemigos tipo B vs 1 agente",
			ga_config, genome, level_name, [{"type": "B", "count": MANY_ENEMIES}], 1))
	specs.append(_make("s07_C_varios", "Varios enemigos tipo C vs 1 agente",
			ga_config, genome, level_name, [{"type": "C", "count": MANY_ENEMIES}], 1))
	specs.append(_make("s08_mixto_1agente", "Varios de todos los enemigos vs 1 agente",
			ga_config, genome, level_name,
			[{"type": "A", "count": 2}, {"type": "B", "count": 2}, {"type": "C", "count": 2}], 1))
	specs.append(_make("s09_mixto_varios", "Varios de todos los enemigos vs varios agentes",
			ga_config, genome, level_name,
			[{"type": "A", "count": 2}, {"type": "B", "count": 2}, {"type": "C", "count": 2}],
			MANY_AGENTS))
	specs.append(_make("s10_humano_varios", "Un jugador humano (bot) vs varios agentes",
			ga_config, genome, level_name, [], MANY_AGENTS, ArenaSpec.Opponent.BOT))

	# --- Escenarios con el Tipo D (sanador) ---------------------------------
	# Van DESPUES de los diez del PDF y no los sustituyen: s01-s10 son los que
	# exige la seccion 3.3.2 y renumerarlos romperia la correspondencia con el
	# enunciado. Estos tres miden algo que los otros no pueden: si el agente
	# aprende a PRIORIZAR. Mientras el sanador viva, el dano hecho al
	# perseguidor se deshace, asi que matar en el orden equivocado se parece
	# mucho a no hacer nada.
	specs.append(_make("s11_D_1v1", "Un enemigo tipo D (sanador) vs 1 agente",
			ga_config, genome, level_name, [{"type": "D", "count": 1}], 1))
	specs.append(_make("s12_escolta", "Dos tipo A escoltados por un sanador vs 1 agente",
			ga_config, genome, level_name,
			[{"type": "A", "count": 2}, {"type": "D", "count": 1}], 1))
	specs.append(_make("s13_mixto_sanador", "Uno de cada tipo, sanador incluido, vs 1 agente",
			ga_config, genome, level_name,
			[{"type": "A", "count": 2}, {"type": "B", "count": 1},
			{"type": "C", "count": 1}, {"type": "D", "count": 1}], 1))

	return specs


static func _make(id: String, label: String, ga_config: GAConfig, genome: Genome,
		level_name: String, enemies: Array, agent_count: int,
		opponent: int = ArenaSpec.Opponent.NONE) -> ArenaSpec:
	var s := ArenaSpec.create(id, label)
	s.level_name = level_name
	s.ga_config = ga_config
	s.agent_genome = genome
	s.agent_count = agent_count
	s.opponent_kind = opponent
	s.fsm_enemies = enemies.duplicate(true)
	s.fsm_opposes_agent = true
	s.max_ticks = GameConfig.MAX_EPISODE_TICKS
	return s


## Escenarios que usan el bot sustituto del humano. Se listan aparte para poder
## marcarlos en el informe como "oponente humano SIMULADO".
static func bot_substituted_ids() -> Array:
	return ["s04_humano_1v1", "s10_humano_varios"]
