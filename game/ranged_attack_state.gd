class_name RangedAttackState
extends EnemyState
## AtacarADistancia - Tipo B y Tipo C.
##
## El Tipo B dispara sin moverse (move_speed = 0 y patrols = false).
## El Tipo C reposiciona para mantener su distancia preferida y transiciona a
## Huir si el objetivo entra en su radio de fuga.


func enter() -> void:
	enemy.pathing.clear_goal()


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

	# Tipo B: el objetivo se acerca demasiado -> guardia.
	if enemy.profile.can_defend and dist <= enemy.profile.defend_radius \
			and not enemy.is_shield_broken():
		machine.change_to(StateMachine.DEFEND)
		return

	# Tipo C: el objetivo se acerca demasiado -> huir.
	if enemy.profile.can_flee and dist <= enemy.profile.flee_radius:
		machine.change_to(StateMachine.FLEE)
		return

	enemy.face_towards(tgt.global_position)

	# Solo dispara con linea de tiro limpia: si no, se reposiciona. Sin esto el
	# Tipo B vacia el cargador contra una columna.
	if enemy.vision.visible_now:
		enemy.try_ranged(tgt.global_position - enemy.global_position)
		if enemy.profile.patrols and enemy.move_speed > 0.0:
			# Mantiene la distancia preferida: si esta muy lejos se acerca un poco.
			if dist > enemy.profile.preferred_range * 1.25:
				enemy.pathing.set_goal(tgt.global_position)
				enemy.move_in_direction(enemy.pathing.steer(), 0.7)
			else:
				enemy.stop()
		else:
			enemy.stop()
	else:
		if enemy.move_speed > 0.0:
			enemy.pathing.set_goal(enemy.vision.last_known_position)
			enemy.move_in_direction(enemy.pathing.steer(), 0.8)
		else:
			enemy.stop()
