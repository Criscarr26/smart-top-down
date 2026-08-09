class_name MeleeAttackState
extends EnemyState
## Atacar - cuerpo a cuerpo. Usado por el Tipo A y, como contraataque forzado a
## quemarropa, por el Tipo C.
##
## Se sale con histeresis (1.35x el rango de entrada) para evitar el parpadeo
## Atacar <-> Perseguir cuando el objetivo oscila justo en el borde del rango.

const EXIT_HYSTERESIS := 1.35


func update(_delta: float) -> void:
	if not aware():
		machine.change_to(StateMachine.IDLE)
		return
	if try_transition_to_potion():
		return

	var tgt := target()
	if tgt == null or not tgt.alive:
		machine.change_to(StateMachine.IDLE)
		return

	var dist := target_distance()
	if dist > enemy.profile.melee_range * EXIT_HYSTERESIS:
		# El Tipo C vuelve a su juego a distancia; el Tipo A reanuda la caza.
		machine.change_to(StateMachine.FLEE if enemy.profile.can_flee else StateMachine.CHASE)
		return

	enemy.face_towards(tgt.global_position)
	enemy.stop()
	enemy.try_melee(tgt.global_position - enemy.global_position)
