class_name EnemyState
extends RefCounted
## Clase base de la maquina de estados finita.
##
## La firma update(delta) se conserva por legibilidad y porque es la convencion
## de FSM, pero el valor que llega SIEMPRE es GameConfig.SIM_DT, nunca el delta
## del motor. Los estados que necesiten medir tiempo deben usar
## machine.ticks_in_state, no acumular delta.

var enemy: Enemy
var machine: StateMachine
var state_name: String = "state"


func setup(p_enemy: Enemy, p_machine: StateMachine) -> void:
	enemy = p_enemy
	machine = p_machine


## Se ejecuta una vez al entrar al estado.
func enter() -> void:
	pass


## Se ejecuta una vez por tick de simulacion mientras el estado esta activo.
func update(_delta: float) -> void:
	pass


## Se ejecuta una vez al salir del estado.
func exit() -> void:
	pass


# --- Ayudas comunes a varios estados -----------------------------------------

func target() -> Actor:
	return enemy.target


func target_distance() -> float:
	return enemy.vision.distance_to_target()


func aware() -> bool:
	return enemy.vision.is_aware()


## Transicion compartida por todos los tipos que pueden curarse: si la salud
## esta baja y hay una pocion alcanzable, ir por ella tiene prioridad sobre
## seguir peleando.
func try_transition_to_potion() -> bool:
	if not enemy.profile.can_seek_potion:
		return false
	if not enemy.is_low_health():
		return false
	if enemy.nearest_potion() == null:
		return false
	machine.change_to(StateMachine.SEEK_POTION)
	return true
