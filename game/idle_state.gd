class_name IdleState
extends EnemyState
## Estado sin objetivo a la vista.
##
## Si el perfil patrulla (Tipo A y C) se desplaza a puntos transitables al azar.
## Si no (Tipo B) se queda fijo barriendo el cono de vision, que es lo que hace
## que una torreta siga siendo una amenaza sin moverse.

const REPICK_TICKS := 150      # 2.5 s antes de elegir otro punto de patrulla
const SCAN_SPEED := 0.9        # rad/s del barrido de vigilancia

var _patrol_point: Vector2 = Vector2.ZERO
var _has_point: bool = false


func enter() -> void:
	enemy.stop()
	_has_point = false


func update(delta: float) -> void:
	# Deteccion: prioridad maxima.
	if aware():
		# Aviso sonoro al ser detectado. En un top-down rapido es informacion
		# de juego, no adorno: te enteras de que te vieron sin tener que mirar
		# a ese lado de la pantalla.
		Audio.play("alert", enemy.global_position)
		machine.change_to(enemy.profile.detect_state)
		return
	if try_transition_to_potion():
		return

	if not enemy.profile.patrols or enemy.move_speed <= 0.0:
		# Vigilancia estatica: gira el cono lentamente.
		enemy.facing = enemy.facing.rotated(SCAN_SPEED * delta)
		enemy.stop()
		return

	if not _has_point or machine.ticks_in_state % REPICK_TICKS == 0:
		_patrol_point = enemy.pick_patrol_point()
		_has_point = true
	enemy.pathing.set_goal(_patrol_point)
	var dir := enemy.pathing.steer()
	if dir == Vector2.ZERO:
		_has_point = false
		enemy.stop()
	else:
		# A media velocidad: patrullar no es perseguir.
		enemy.move_in_direction(dir, 0.55)
