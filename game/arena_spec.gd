class_name ArenaSpec
extends RefCounted
## Descripcion declarativa de un combate. El Arena lo lee y monta el escenario.
## Es la unidad de trabajo del harness de benchmark: un ArenaSpec = un episodio.

enum Opponent { NONE, HUMAN, BOT }

var level_name: String = "level_01"
## Quien ocupa el bando "jugador": nadie, un humano al teclado, o el bot.
var opponent_kind: int = Opponent.BOT
## Enemigos FSM a instanciar, como [{"type": "A", "count": 2}, ...].
var fsm_enemies: Array = []
## Cuantos agentes entrenados participan.
var agent_count: int = 1
## Genoma que cargan los agentes. Si es null, se usan pesos aleatorios.
var agent_genome: Genome = null
var ga_config: GAConfig = null
## Pesos de la funcion de fitness de ESTE episodio. Si es null se usan los de
## Fitness. Viaja aqui y no en un global mutable porque el SimPool corre varias
## arenas a la vez: con estado compartido, cambiar los pesos para entrenar
## alteraria tambien los episodios que se estuvieran evaluando.
var fitness_weights: Fitness.Weights = null
var seed: int = 0
var max_ticks: int = GameConfig.MAX_EPISODE_TICKS

## Si el episodio termina al quedarse un bando sin nadie vivo.
##
## Es true en TODOS los escenarios del benchmark: ahi el fin de bando es
## exactamente la condicion que se mide. La partida por oleadas lo pone en false
## porque entre oleada y oleada el bando enemigo esta legitimamente vacio; ahi el
## final lo decide el director de oleadas o la muerte del jugador.
var finish_on_side_wipe: bool = true

## MODELADO IMPORTANTE:
## En el juego, los enemigos A/B/C y el agente son todos enemigos del jugador.
## Pero los escenarios del PDF ("un enemigo tipo A vs 1 agente") los enfrentan
## ENTRE SI. Cuando esto es true, los enemigos FSM se colocan en el bando
## contrario al agente para que puedan pelear. En la partida jugable es false y
## todos comparten bando contra el jugador humano.
var fsm_opposes_agent: bool = true

## Etiqueta legible del escenario, para el CSV.
var scenario_id: String = "custom"
var scenario_label: String = "Escenario personalizado"


static func create(p_scenario_id: String, p_label: String) -> ArenaSpec:
	var s := ArenaSpec.new()
	s.scenario_id = p_scenario_id
	s.scenario_label = p_label
	return s


func with_enemies(type_id: String, count: int) -> ArenaSpec:
	fsm_enemies.append({"type": type_id, "count": count})
	return self


func total_fsm_enemies() -> int:
	var n := 0
	for e in fsm_enemies:
		n += int(e.get("count", 0))
	return n


func duplicate_spec() -> ArenaSpec:
	var s := ArenaSpec.new()
	s.level_name = level_name
	s.opponent_kind = opponent_kind
	s.fsm_enemies = fsm_enemies.duplicate(true)
	s.agent_count = agent_count
	s.agent_genome = agent_genome
	s.ga_config = ga_config
	s.fitness_weights = fitness_weights
	s.seed = seed
	s.max_ticks = max_ticks
	s.finish_on_side_wipe = finish_on_side_wipe
	s.fsm_opposes_agent = fsm_opposes_agent
	s.scenario_id = scenario_id
	s.scenario_label = scenario_label
	return s
