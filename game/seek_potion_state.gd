class_name SeekPotionState
extends EnemyState
## BuscarPocion - Tipo A y Tipo C.
##
## Ruta A* hasta la pocion disponible mas cercana. El Arena resuelve la recogida
## por proximidad; los enemigos la consumen en el acto (a diferencia del
## jugador, que la guarda en inventario y decide cuando usarla).

const GIVE_UP_TICKS := 600     # 10 s buscando sin exito -> abandona


func enter() -> void:
	enemy.pathing.clear_goal()


func update(_delta: float) -> void:
	# Ya se curo (recogio la pocion): vuelve al combate.
	if not enemy.is_low_health():
		_return_to_combat()
		return

	var potion := enemy.nearest_potion()
	if potion == null or machine.ticks_in_state > GIVE_UP_TICKS:
		# No queda ninguna: seguir peleando herido es mejor que quedarse quieto.
		_return_to_combat()
		return

	enemy.pathing.set_goal(potion.global_position)
	var dir := enemy.pathing.steer()
	if dir == Vector2.ZERO:
		_return_to_combat()
		return
	enemy.move_in_direction(dir)

	# Si el objetivo lo alcanza mientras huye a curarse, el Tipo A se defiende
	# de la unica forma que sabe: pegando.
	if enemy.profile.can_melee and target_distance() <= enemy.profile.melee_range:
		var tgt := target()
		if tgt != null and tgt.alive:
			enemy.try_melee(tgt.global_position - enemy.global_position)


func _return_to_combat() -> void:
	if aware():
		machine.change_to(enemy.profile.detect_state)
	else:
		machine.change_to(StateMachine.IDLE)
