class_name Arena
extends Node2D
## Una instancia de combate: monta el nivel, corre la simulacion tick a tick y
## produce el resultado del episodio.
##
## Es la misma clase para jugar y para entrenar. Que la partida jugable y las
## miles de partidas del benchmark corran exactamente el mismo codigo es lo que
## hace que el agente entrenado se comporte igual en ambas; si el entrenamiento
## usara un simulador aparte, lo aprendido no transferiria.
##
## ORDEN DE TICK (fijo, y de ahi la reproducibilidad):
##   1. mantenimiento de actores (cooldowns, escudo)
##   2. reasignacion de objetivos (cada TARGET_REFRESH_TICKS)
##   3. decision + accion de cada actor, en orden estable de creacion
##   4. proyectiles
##   5. recogida de pociones
##   6. puas
##   7. condicion de fin

signal episode_finished(result: Dictionary)

const TARGET_REFRESH_TICKS := 15

var spec: ArenaSpec
var data: LevelData
var nav: NavGrid

var actors: Array = []        # orden de creacion; NO reordenar
var projectiles: Array = []
var potions: Array = []
var spikes: Array = []
var agents: Array = []        # solo AgentEnemy
var opponents: Array = []     # todo lo que pelea contra los agentes

var tick: int = 0
var running: bool = false
var interactive: bool = false
var finished_reason: String = ""

## Generador propio de esta arena. Es lo que permite correr episodios en
## paralelo sin que se pisen la aleatoriedad (ver la nota en Actor.rng).
var rng := RandomNumberGenerator.new()

var _walls: StaticBody2D
var _actor_container: Node2D
var _projectile_container: Node2D


func setup(p_spec: ArenaSpec, p_interactive: bool = false) -> void:
	spec = p_spec
	interactive = p_interactive
	rng.seed = p_spec.seed
	rng.state = 0

	data = LevelMaps.by_name(spec.level_name)
	nav = WorldBuilder.build_nav_grid(data)

	_walls = WorldBuilder.build_walls(data)
	add_child(_walls)

	_actor_container = Node2D.new()
	_actor_container.name = "Actors"
	add_child(_actor_container)
	_projectile_container = Node2D.new()
	_projectile_container.name = "Projectiles"
	add_child(_projectile_container)

	for s in WorldBuilder.build_spikes(data):
		spikes.append(s)
		add_child(s)
		if interactive:
			s.enable_visuals()
	for p in WorldBuilder.build_potions(data):
		potions.append(p)
		add_child(p)
		if interactive:
			p.enable_visuals()

	_spawn_all()
	_assign_targets()
	tick = 0
	running = true
	queue_redraw()


func _physics_process(_delta: float) -> void:
	# El delta del motor se ignora deliberadamente: la simulacion avanza con
	# GameConfig.SIM_DT para que acelerar con Engine.time_scale no cambie el
	# resultado. Ver la nota en GameConfig.
	if running:
		step()


## Un tick completo de simulacion.
func step() -> void:
	tick += 1

	for a in actors:
		(a as Actor).sim_tick()

	if tick % TARGET_REFRESH_TICKS == 0:
		_assign_targets()

	for a in actors:
		var actor := a as Actor
		if not actor.alive:
			continue
		if actor is Enemy:
			(actor as Enemy).think(GameConfig.SIM_DT)
		elif actor is AgentEnemy:
			(actor as AgentEnemy).think(GameConfig.SIM_DT)
		elif actor is ScriptedBot:
			(actor as ScriptedBot).think(GameConfig.SIM_DT)
		elif actor is Player:
			(actor as Player).think(GameConfig.SIM_DT)

	_tick_projectiles()
	_tick_potions()
	_tick_spikes()
	_tick_engagement()
	_check_end_conditions()


# =============================================================================
# Construccion del escenario
# =============================================================================

func _spawn_all() -> void:
	# Los agentes ocupan las posiciones de aparicion de enemigo, y sus
	# oponentes las del jugador: quedan separados por el ancho del nivel, que
	# es lo que hace que el episodio empiece con una fase de aproximacion en
	# lugar de con todos amontonados.
	var agent_points := _spawn_points(spec.agent_count, data.enemy_spawns)
	for i in spec.agent_count:
		_spawn_agent(agent_points[i])

	var opponent_count := spec.total_fsm_enemies()
	if spec.opponent_kind != ArenaSpec.Opponent.NONE:
		opponent_count += 1
	var opponent_points := _spawn_points(opponent_count, data.player_spawns)
	var idx := 0

	if spec.opponent_kind == ArenaSpec.Opponent.HUMAN:
		_spawn_player(opponent_points[idx]); idx += 1
	elif spec.opponent_kind == ArenaSpec.Opponent.BOT:
		_spawn_bot(opponent_points[idx]); idx += 1

	for entry in spec.fsm_enemies:
		var type_id := str(entry.get("type", "A"))
		for _i in int(entry.get("count", 1)):
			_spawn_fsm_enemy(type_id, opponent_points[idx])
			idx += 1


## Devuelve `count` posiciones de aparicion. Usa las del mapa mientras haya, y
## luego celdas libres al azar; nunca falla por falta de puntos definidos.
func _spawn_points(count: int, preferred: Array) -> Array:
	var out: Array = []
	for cell in preferred:
		if out.size() >= count:
			break
		out.append(data.cell_center(cell))
	if out.size() < count:
		var pool := _shuffled(nav.free_cells())
		for c in pool:
			if out.size() >= count:
				break
			var world: Vector2 = nav.cell_to_world(c)
			var too_close := false
			for existing in out:
				if (existing as Vector2).distance_to(world) < GameConfig.CELL_SIZE * 2.0:
					too_close = true
					break
			if not too_close:
				out.append(world)
	# Ultimo recurso: repite el centro del nivel.
	while out.size() < count:
		out.append(data.cell_center(Vector2i(data.width / 2, data.height / 2)))
	return out


func _spawn_agent(at: Vector2) -> void:
	var config: GAConfig = spec.ga_config if spec.ga_config != null else GAConfig.new()
	var net := NeuralNetwork.new(config.topology())
	if spec.agent_genome != null and spec.agent_genome.size() == net.param_count():
		net.set_params(spec.agent_genome.params)
	else:
		net.set_params(Genome.create(net.param_count(), config.init_mode, config.init_scale).params)

	var agent := AgentEnemy.new()
	agent.position = at
	_register(agent)
	agent.configure(EnemyProfile.agent(), nav, potions, net, config)
	agent.setup_team(Actor.Team.ENEMY)
	_enable_visuals(agent)
	agents.append(agent)


func _spawn_fsm_enemy(type_id: String, at: Vector2) -> void:
	var enemy := Enemy.new()
	enemy.position = at
	_register(enemy)
	enemy.configure(EnemyProfile.by_type(type_id), nav, potions)
	# En los escenarios del benchmark los enemigos FSM son los RIVALES del
	# agente, asi que van al bando contrario. En la partida jugable comparten
	# bando con el agente contra el jugador humano.
	enemy.setup_team(Actor.Team.PLAYER if spec.fsm_opposes_agent else Actor.Team.ENEMY)
	_enable_visuals(enemy)
	if spec.fsm_opposes_agent:
		opponents.append(enemy)


func _spawn_bot(at: Vector2) -> void:
	var bot := ScriptedBot.new()
	bot.position = at
	_register(bot)
	bot.configure(nav, potions)
	_enable_visuals(bot)
	opponents.append(bot)


func _spawn_player(at: Vector2) -> void:
	var player := Player.new()
	player.position = at
	_register(player)
	player.configure()
	_enable_visuals(player)
	opponents.append(player)


## Crea el sprite del actor, ya con su `sprite_kind` definitivo. Solo en modo
## interactivo.
func _enable_visuals(actor: Actor) -> void:
	if interactive:
		actor.enable_visuals()


## Fisher-Yates con el generador de la arena.
func _shuffled(arr: Array) -> Array:
	var out := arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


func _register(actor: Actor) -> void:
	actor.rng = rng
	actor.projectile_requested.connect(_on_projectile_requested)
	_actor_container.add_child(actor)
	actors.append(actor)
	# En el benchmark no hay nada que dibujar: apagar _process de cada actor
	# ahorra un queue_redraw por actor y por frame en decenas de arenas.
	actor.set_process(interactive)
	# OJO: enable_visuals() NO se llama aqui. `sprite_kind` lo fija configure(),
	# que corre despues de _register(), asi que hacerlo aqui daria a todos los
	# actores el sprite por defecto (el del jugador). Cada _spawn_* lo llama al
	# terminar de configurar.


# =============================================================================
# Sub-sistemas del tick
# =============================================================================

## Cada actor apunta al rival vivo mas cercano del bando contrario.
func _assign_targets() -> void:
	for a in actors:
		var actor := a as Actor
		if not actor.alive:
			continue
		var best: Actor = null
		var best_d := INF
		for b in actors:
			var other := b as Actor
			if other == actor or not other.alive or other.team == actor.team:
				continue
			var d := actor.global_position.distance_squared_to(other.global_position)
			if d < best_d:
				best_d = d
				best = other
		if actor is Enemy:
			(actor as Enemy).target = best
		elif actor is AgentEnemy:
			(actor as AgentEnemy).target = best
		elif actor is ScriptedBot:
			(actor as ScriptedBot).target = best


func _on_projectile_requested(shooter: Actor, from: Vector2, dir: Vector2, damage: float) -> void:
	var p := Projectile.new()
	_projectile_container.add_child(p)
	p.setup(shooter, from, dir, damage)
	p.set_process(interactive)
	if interactive:
		p.enable_visuals()
	projectiles.append(p)


func _tick_projectiles() -> void:
	# Se recorre al reves para poder borrar sin invalidar los indices.
	for i in range(projectiles.size() - 1, -1, -1):
		var p := projectiles[i] as Projectile
		if p == null or not is_instance_valid(p):
			projectiles.remove_at(i)
			continue
		if not p.sim_tick():
			projectiles.remove_at(i)
			p.queue_free()


func _tick_potions() -> void:
	for p in potions:
		(p as Potion).sim_tick()
	for a in actors:
		var actor := a as Actor
		if not actor.alive:
			continue
		for p in potions:
			var potion := p as Potion
			if not potion.available:
				continue
			if actor.global_position.distance_to(potion.global_position) \
					<= GameConfig.POTION_PICKUP_RADIUS + GameConfig.ACTOR_RADIUS:
				if potion.take():
					actor.potions += 1
					# Los enemigos la beben en el acto; el jugador y el bot la
					# guardan y deciden cuando usarla (requisito 2.d del PDF).
					if actor.auto_use_potions:
						actor.try_use_potion()
				break


func _tick_spikes() -> void:
	for a in actors:
		var actor := a as Actor
		if not actor.alive:
			continue
		for s in spikes:
			if (s as Spike).kills(actor.global_position):
				Audio.play("spike", actor.global_position)
				actor.die(null)   # sin atacante: la pua no acredita kill a nadie
				break


## El episodio acaba cuando un BANDO entero cae, no cuando caen los actores de
## una lista concreta. Se cuenta por equipo porque en la partida jugable los
## enemigos FSM comparten bando con el agente contra el jugador humano, y
## mirando solo `agents` y `opponents` esos enemigos no contarian para nada.
## Cuenta los ticks que cada actor pasa en rango de combate con un rival vivo.
## Es el termino de shaping de la funcion de fitness: sin el, el algoritmo
## genetico no distingue entre un agente que busca pelea y uno que se esconde
## hasta que alguno aprende por azar a hacer dano.
func _tick_engagement() -> void:
	for a in actors:
		var actor := a as Actor
		if not actor.alive:
			continue
		for b in actors:
			var other := b as Actor
			if other == actor or not other.alive or other.team == actor.team:
				continue
			if actor.global_position.distance_to(other.global_position) <= Fitness.ENGAGE_RANGE:
				actor.ticks_engaged += 1
				break


func _check_end_conditions() -> void:
	var player_alive := 0
	var player_total := 0
	var enemy_alive := 0
	var enemy_total := 0
	for a in actors:
		var actor := a as Actor
		if actor.team == Actor.Team.PLAYER:
			player_total += 1
			if actor.alive:
				player_alive += 1
		else:
			enemy_total += 1
			if actor.alive:
				enemy_alive += 1

	if enemy_total > 0 and enemy_alive == 0:
		_finish("bando_enemigo_eliminado")
	elif player_total > 0 and player_alive == 0:
		_finish("bando_jugador_eliminado")
	elif tick >= spec.max_ticks:
		_finish("tiempo_agotado")


func _finish(reason: String) -> void:
	if not running:
		return
	running = false
	finished_reason = reason
	episode_finished.emit(build_result())


# =============================================================================
# Resultado del episodio (las 4 metricas de la seccion 3.3.3 del PDF)
# =============================================================================

func build_result() -> Dictionary:
	var seconds := float(tick) / float(GameConfig.TICKS_PER_SECOND)

	var agent_damage := 0.0
	var agent_kills := 0
	var agent_ticks := 0
	var agent_taken := 0.0
	var agent_potions := 0
	var agents_alive := 0
	var idle_ticks := 0
	var action_mix := {}
	for a in agents:
		var ag := a as AgentEnemy
		agent_damage += ag.damage_dealt
		agent_kills += ag.kills
		agent_ticks += ag.ticks_alive
		agent_taken += ag.damage_taken
		agent_potions += ag.potions_used
		idle_ticks += ag.idle_ticks
		if ag.alive:
			agents_alive += 1
		var dist := ag.action_distribution()
		for k in dist:
			action_mix[k] = float(action_mix.get(k, 0.0)) + float(dist[k])
	var n_agents: int = maxi(1, agents.size())
	for k in action_mix:
		action_mix[k] = float(action_mix[k]) / float(n_agents)

	var opp_damage := 0.0
	var opp_ticks := 0
	var opponents_alive := 0
	for o in opponents:
		var op := o as Actor
		opp_damage += op.damage_dealt
		opp_ticks += op.ticks_alive
		if op.alive:
			opponents_alive += 1

	var winner := "empate"
	if agents_alive > 0 and opponents_alive == 0:
		winner = "agente"
	elif agents_alive == 0 and opponents_alive > 0:
		winner = "oponente"

	# Tiempo de vida medio por bando, en segundos.
	var agent_life := float(agent_ticks) / float(n_agents) / float(GameConfig.TICKS_PER_SECOND)
	var opp_life := 0.0
	if not opponents.is_empty():
		opp_life = float(opp_ticks) / float(opponents.size()) / float(GameConfig.TICKS_PER_SECOND)

	# DPS: dano infligido dividido entre el tiempo que el bando estuvo vivo.
	var agent_dps := 0.0 if agent_life <= 0.0 else agent_damage / agent_life
	var opp_dps := 0.0 if opp_life <= 0.0 else opp_damage / opp_life

	# Tasa de exito: cuantos oponentes mato el agente sobre el total que habia.
	var success_rate := 0.0
	if not opponents.is_empty():
		success_rate = clampf(float(agent_kills) / float(opponents.size()), 0.0, 1.0)

	var victory := winner == "agente"
	var draw := winner == "empate"
	var fitness_total := 0.0
	var engaged_ticks := 0
	for a in agents:
		fitness_total += Fitness.evaluate(a as Actor, victory, draw, (a as AgentEnemy).idle_ticks)
		engaged_ticks += (a as Actor).ticks_engaged

	return {
		"escenario": spec.scenario_id,
		"escenario_label": spec.scenario_label,
		"nivel": spec.level_name,
		"semilla": spec.seed,
		"motivo_fin": finished_reason,
		"duracion_s": seconds,
		"ticks": tick,
		# --- las 4 metricas que pide el PDF ---
		"ganador": winner,
		"tiempo_vida_agente_s": agent_life,
		"tiempo_vida_oponente_s": opp_life,
		"dps_agente": agent_dps,
		"dps_oponente": opp_dps,
		"tasa_exito": success_rate,
		# --- soporte para el analisis ---
		"dano_hecho_agente": agent_damage,
		"dano_recibido_agente": agent_taken,
		"kills_agente": agent_kills,
		"pociones_agente": agent_potions,
		"agentes_vivos": agents_alive,
		"oponentes_vivos": opponents_alive,
		"oponentes_total": opponents.size(),
		"ticks_inactivo": idle_ticks,
		"ticks_en_combate": engaged_ticks,
		"fitness": fitness_total,
		"mezcla_acciones": action_mix,
	}


## Suma de fitness de los agentes. Lo usa el entrenador.
func agent_fitness() -> float:
	var victory := true
	for o in opponents:
		if (o as Actor).alive:
			victory = false
			break
	var draw := finished_reason == "tiempo_agotado"
	var total := 0.0
	for a in agents:
		total += Fitness.evaluate(a as Actor, victory, draw, (a as AgentEnemy).idle_ticks)
	return total


# =============================================================================
# Presentacion
# =============================================================================

func _draw() -> void:
	if not interactive or data == null:
		return
	WorldBuilder.draw_level(self, data)


func world_size() -> Vector2:
	if data == null:
		return Vector2.ZERO
	return Vector2(data.width, data.height) * GameConfig.CELL_SIZE


## Libera las referencias ciclicas de todos los actores antes de destruir la
## arena. Sin esto, el barrido del benchmark deja atras cada enemigo que ha
## creado y la memoria del proceso crece durante horas (ver Actor.dispose).
func dispose() -> void:
	running = false
	for a in actors:
		var actor := a as Actor
		if actor != null and is_instance_valid(actor):
			actor.dispose()
	actors.clear()
	agents.clear()
	opponents.clear()
	projectiles.clear()
	potions.clear()
	spikes.clear()
	nav = null
	data = null
