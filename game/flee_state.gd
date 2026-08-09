class_name FleeState
extends EnemyState
## Huir - Tipo C.
##
## Se aleja del objetivo, pero sigue disparando mientras retrocede (eso es lo
## que hace de este enemigo un "kiter" y no simplemente un cobarde). Si el
## objetivo se le pega encima, contraataca cuerpo a cuerpo.

const EXIT_HYSTERESIS := 1.40
const REPICK_TICKS := 20

var _flee_point: Vector2 = Vector2.ZERO


func enter() -> void:
	_pick_point()


func update(_delta: float) -> void:
	var tgt := target()
	if not aware() or tgt == null or not tgt.alive:
		machine.change_to(StateMachine.IDLE)
		return

	var dist := target_distance()

	# Lo tiene encima: contraataque forzado.
	if enemy.profile.can_melee and dist <= enemy.profile.panic_melee_radius:
		machine.change_to(StateMachine.MELEE)
		return

	# Ya tomo distancia suficiente: vuelve a hostigar de lejos.
	if dist > enemy.profile.flee_radius * EXIT_HYSTERESIS:
		machine.change_to(StateMachine.RANGED if machine.has(StateMachine.RANGED) else StateMachine.IDLE)
		return

	if try_transition_to_potion():
		return

	if machine.ticks_in_state % REPICK_TICKS == 0:
		_pick_point()

	enemy.pathing.set_goal(_flee_point)
	var dir := enemy.pathing.steer()
	if dir == Vector2.ZERO:
		# Acorralado: si no hay a donde huir, pelea.
		machine.change_to(StateMachine.MELEE if enemy.profile.can_melee else StateMachine.RANGED)
		return
	enemy.move_in_direction(dir)
	enemy.ticks_fleeing += 1

	# Dispara por encima del hombro mientras retrocede.
	if enemy.profile.can_ranged and enemy.vision.visible_now:
		enemy.try_ranged(tgt.global_position - enemy.global_position)


func _pick_point() -> void:
	var tgt := target()
	var threat := tgt.global_position if tgt != null else enemy.global_position
	_flee_point = enemy.flee_point_from(threat)
