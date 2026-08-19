class_name SupportState
extends EnemyState
## Apoyar - Tipo D (sanador).
##
## POR QUE EXISTE ESTE ENEMIGO. Los tipos A, B y C se resuelven todos con la
## misma decision: "acercate y pega". Ninguno cambia el ORDEN en que conviene
## matar a los demas. El sanador si: mientras siga vivo, el dano que se le hace
## al perseguidor se deshace, asi que el jugador (y el agente entrenado) tiene
## que decidir entre la amenaza inmediata y la que multiplica a las demas. Es
## profundidad tactica que no cuesta ni una mecanica nueva de combate.
##
## Se mantiene deliberadamente fragil (poca vida, sin melee) para que la decision
## correcta sea alcanzable, no un muro.

## Fraccion de salud por debajo de la cual un aliado se considera herido.
const UMBRAL_HERIDO := 0.92
## Cada cuantos ticks se vuelve a elegir a quien curar. Sin esto, el sanador
## cambia de paciente cada tick en cuanto dos aliados estan parejos y se queda
## oscilando entre los dos sin llegar a ninguno.
const REELEGIR_TICKS := 30

var _paciente: Actor = null


func enter() -> void:
	_paciente = enemy.wounded_ally(UMBRAL_HERIDO)


func update(_delta: float) -> void:
	if machine.ticks_in_state % REELEGIR_TICKS == 0:
		_paciente = enemy.wounded_ally(UMBRAL_HERIDO)

	# Amenaza encima: sobrevivir manda, ya volvera a curar.
	var dist := target_distance()
	if aware() and dist <= enemy.profile.flee_radius and machine.has(StateMachine.FLEE):
		machine.change_to(StateMachine.FLEE)
		return

	if _paciente == null or not is_instance_valid(_paciente) or not _paciente.alive:
		_paciente = enemy.wounded_ally(UMBRAL_HERIDO)
		if _paciente == null:
			# Nadie a quien curar: hostiga de lejos como una torreta movil.
			machine.change_to(StateMachine.RANGED if machine.has(StateMachine.RANGED)
					else StateMachine.IDLE)
			return

	var hacia: Vector2 = _paciente.global_position - enemy.global_position
	var d: float = hacia.length()

	if d > enemy.profile.heal_range:
		# Fuera de alcance: acercarse por ruta, no en linea recta (hay puas).
		enemy.pathing.set_goal(_paciente.global_position)
		var dir := enemy.pathing.steer()
		if dir != Vector2.ZERO:
			enemy.move_in_direction(dir)
		else:
			enemy.face_towards(_paciente.global_position)
			enemy.stop()
		return

	# En alcance: se planta y cura. Curar inmoviliza, igual que defender, para
	# que tenga un coste y se le pueda castigar.
	enemy.face_towards(_paciente.global_position)
	enemy.stop()
	var antes: float = _paciente.health
	_paciente.heal(enemy.profile.heal_per_tick)
	enemy.healing_done += _paciente.health - antes
	enemy.healing_target = _paciente


func exit() -> void:
	enemy.healing_target = null
