class_name DefendState
extends EnemyState
## Defender - Tipo B.
##
## Guardia arriba mientras el objetivo este cerca. Defender inmoviliza y consume
## escudo; si el escudo se rompe el enemigo queda expuesto y no puede volver a
## defender hasta que se recupere, asi que sale del estado.

const EXIT_HYSTERESIS := 1.30


func enter() -> void:
	enemy.stop()
	enemy.pathing.clear_goal()


func update(_delta: float) -> void:
	var tgt := target()
	if not aware() or tgt == null or not tgt.alive:
		machine.change_to(StateMachine.IDLE)
		return

	# Escudo roto: defender ya no protege, mejor volver a disparar.
	if enemy.is_shield_broken():
		machine.change_to(StateMachine.RANGED if machine.has(StateMachine.RANGED) else StateMachine.IDLE)
		return

	var dist := target_distance()
	if dist > enemy.profile.defend_radius * EXIT_HYSTERESIS:
		machine.change_to(StateMachine.RANGED if machine.has(StateMachine.RANGED) else StateMachine.IDLE)
		return

	enemy.face_towards(tgt.global_position)
	enemy.set_defending(true)   # hay que re-afirmarlo cada tick (ver Actor.sim_tick)
