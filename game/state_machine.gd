class_name StateMachine
extends RefCounted
## Maquina de estados finita de los enemigos.
##
## Los tres tipos (A, B, C) comparten esta infraestructura y el mismo script de
## Enemy; lo unico que cambia es QUE estados se registran y con que umbrales,
## definido en EnemyProfile. Es la misma idea que mostro el profesor en clase al
## cambiar el estado de un enemigo en vivo sin tocar su codigo.

const IDLE := "Idle"
const CHASE := "Perseguir"
const MELEE := "Atacar"
const RANGED := "AtacarADistancia"
const DEFEND := "Defender"
const FLEE := "Huir"
const SEEK_POTION := "BuscarPocion"

var states: Dictionary = {}
var current: EnemyState = null
var current_name: String = ""
var previous_name: String = ""
var ticks_in_state: int = 0

## Historial de estados visitados, para el benchmark cualitativo (permite decir
## "contra el Tipo C el agente paso 40% del tiempo huyendo").
var visit_counts: Dictionary = {}


func add_state(state_name: String, state: EnemyState, enemy: Enemy) -> void:
	state.state_name = state_name
	state.setup(enemy, self)
	states[state_name] = state


func has(state_name: String) -> bool:
	return states.has(state_name)


func start(state_name: String) -> void:
	current = null
	current_name = ""
	change_to(state_name)


func change_to(state_name: String) -> void:
	if not states.has(state_name):
		# Un perfil que no registra el estado destino simplemente no transiciona.
		# Ej: el Tipo B no tiene Huir, asi que una peticion de huida se ignora.
		return
	if state_name == current_name:
		return
	if current != null:
		current.exit()
	previous_name = current_name
	current = states[state_name]
	current_name = state_name
	ticks_in_state = 0
	visit_counts[state_name] = int(visit_counts.get(state_name, 0)) + 1
	current.enter()


func tick(delta: float) -> void:
	if current == null:
		return
	ticks_in_state += 1
	current.update(delta)


## Reparto de tiempo por estado, normalizado. Alimenta el resumen cualitativo.
func state_distribution() -> Dictionary:
	var total := 0
	for k in visit_counts:
		total += int(visit_counts[k])
	if total == 0:
		return {}
	var out := {}
	for k in visit_counts:
		out[k] = float(visit_counts[k]) / float(total)
	return out
