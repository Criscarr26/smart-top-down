class_name ChaseState
extends EnemyState
## Perseguir - Tipo A.
##
## Va hacia la ultima posicion conocida del objetivo usando A*. Si lo alcanza
## en rango de melee pasa a Atacar; si lo pierde y agota la memoria, vuelve a
## Idle.


func enter() -> void:
	enemy.pathing.clear_goal()


func update(_delta: float) -> void:
	if not aware():
		machine.change_to(StateMachine.IDLE)
		return
	if try_transition_to_potion():
		return

	var dist := target_distance()
	if enemy.profile.can_melee and dist <= enemy.profile.melee_range:
		machine.change_to(StateMachine.MELEE)
		return

	# Persigue la ultima posicion conocida, no la actual: si el objetivo se
	# escondio tras una pared, el enemigo va a donde lo vio por ultima vez en
	# lugar de atravesar la geometria magicamente.
	enemy.pathing.set_goal(enemy.vision.last_known_position)
	var dir := enemy.pathing.steer()
	if dir == Vector2.ZERO:
		# Llego a la ultima posicion conocida y no hay nadie: olvida y patrulla.
		enemy.vision.forget()
		machine.change_to(StateMachine.IDLE)
		return
	enemy.move_in_direction(dir)
