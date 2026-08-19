class_name AgentEnemy
extends Actor
## El enemigo entrenado: mismas acciones que los tipos A, B y C juntos
## (requisito 3.d del PDF), pero sin FSM. Quien decide es la red neuronal.
##
## Cadencia de decision: la red se consulta cada DECISION_INTERVAL ticks, no
## cada tick. Dos motivos:
##  1. Coherencia. A 60 Hz el agente cambiaria de accion 60 veces por segundo y
##     produciria el temblor tipico de las politicas sin memoria: avanza-huye-
##     avanza-huye sin desplazarse. A 10 Hz las acciones duran lo bastante para
##     que se note su efecto, que es justo lo que el fitness necesita medir.
##  2. Coste. El forward pass es la parte cara del entrenamiento; a 1/6 de la
##     frecuencia el barrido completo baja de horas a minutos.
## Entre decisiones el agente REPITE la ultima accion, no se queda parado.

const DECISION_INTERVAL := 6

var net: NeuralNetwork
var config: GAConfig
var nav: NavGrid
var pathing: PathfindingComponent
var target: Actor = null
var level_potions: Array = []

var current_action: int = Thresholding.NO_ACTION
var idle_ticks: int = 0
## Cuantas veces se eligio cada accion; alimenta el benchmark cualitativo.
var action_counts: Array = []

# --- Introspeccion ------------------------------------------------------------
## Ultima lectura de sensores y ultima salida cruda de la red.
##
## Se guardan siempre porque ya estaban calculadas: es una referencia, no
## trabajo extra. Son lo que permite ENSENAR que percibe y que decide el agente
## en vez de tener que creerselo, que es la diferencia entre una demo de IA y una
## caja negra que se mueve sola.
var last_inputs := PackedFloat32Array()
var last_outputs := PackedFloat32Array()
## Probabilidades softmax de la ultima decision, para dibujar las barras.
var last_probs := PackedFloat32Array()
## Ticks desde la ultima decision; con DECISION_INTERVAL da el ritmo del pulso
## que dibuja el overlay.
var ticks_since_decision: int = 0

var _ticks_to_decision: int = 0


func configure(p_profile: EnemyProfile, p_nav: NavGrid, p_potions: Array,
		p_net: NeuralNetwork, p_config: GAConfig) -> void:
	display_name = p_profile.display_name
	sprite_kind = "agent"
	body_color = p_profile.body_color
	max_health = p_profile.max_health
	health = max_health
	move_speed = p_profile.move_speed
	accel = p_profile.accel
	friction = p_profile.friction
	melee_damage = p_profile.melee_damage
	ranged_damage = p_profile.ranged_damage
	can_defend = true
	max_shield = GameConfig.MAX_SHIELD
	shield = max_shield
	setup_team(Team.ENEMY)

	nav = p_nav
	level_potions = p_potions
	net = p_net
	config = p_config
	pathing = PathfindingComponent.new(self, p_nav)

	action_counts.resize(AgentActions.COUNT)
	action_counts.fill(0)
	idle_ticks = 0
	current_action = Thresholding.NO_ACTION
	_ticks_to_decision = 0


## Capa de decision. La llama el Arena una vez por tick.
func think(_delta: float) -> void:
	if not alive:
		return
	if _ticks_to_decision <= 0:
		_decide()
		_ticks_to_decision = DECISION_INTERVAL
		ticks_since_decision = 0
	else:
		ticks_since_decision += 1
	_ticks_to_decision -= 1
	_execute(current_action)


func _decide() -> void:
	var inputs := AgentSensors.read(self, target, level_potions)
	var outputs := net.forward(inputs)
	last_inputs = inputs
	last_outputs = outputs
	last_probs = Thresholding.softmax(outputs)
	current_action = Thresholding.select(
			outputs, config.thresholding_mode, config.threshold_value, rng)
	if current_action == Thresholding.NO_ACTION:
		idle_ticks += DECISION_INTERVAL
	else:
		action_counts[current_action] += 1


func _execute(action: int) -> void:
	var has_target: bool = target != null and is_instance_valid(target) and target.alive

	match action:
		AgentActions.CHASE:
			if not has_target:
				stop()
				return
			pathing.set_goal(target.global_position)
			var dir := pathing.steer()
			if dir == Vector2.ZERO:
				face_towards(target.global_position)
				stop()
			else:
				move_in_direction(dir)

		AgentActions.MELEE:
			if not has_target:
				stop()
				return
			face_towards(target.global_position)
			stop()
			try_melee(target.global_position - global_position)

		AgentActions.RANGED:
			if not has_target:
				stop()
				return
			face_towards(target.global_position)
			stop()
			try_ranged(target.global_position - global_position)

		AgentActions.FLEE:
			if not has_target:
				stop()
				return
			var point := Steering.flee_point(global_position, target.global_position, nav, rng)
			pathing.set_goal(point)
			move_in_direction(pathing.steer())
			ticks_fleeing += 1

		AgentActions.SEEK_POTION:
			var potion := Steering.nearest_potion(global_position, level_potions)
			if potion == null:
				stop()
				return
			pathing.set_goal(potion.global_position)
			move_in_direction(pathing.steer())

		AgentActions.DEFEND:
			set_defending(true)

		_:
			# NO_ACTION del thresholding por umbral: la red no estaba segura.
			stop()


## Rompe el ciclo AgentEnemy -> PathfindingComponent -> AgentEnemy
## (ver Actor.dispose).
func dispose() -> void:
	if pathing != null:
		pathing.actor = null
		pathing.nav = null
		pathing = null
	net = null
	config = null
	target = null
	nav = null
	level_potions = []
	super.dispose()


## Reparto de acciones normalizado. Base del resumen cualitativo ("el agente
## paso el 40% de sus decisiones huyendo").
func action_distribution() -> Dictionary:
	var total := 0
	for c in action_counts:
		total += int(c)
	var out := {}
	for i in AgentActions.COUNT:
		out[AgentActions.NAMES[i]] = 0.0 if total == 0 else float(action_counts[i]) / float(total)
	return out
