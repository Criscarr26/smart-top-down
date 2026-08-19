class_name Player
extends Actor
## Jugador controlado por teclado + raton (twin-stick, como Hotline Miami):
## las flechas mueven, el raton apunta.
##
## Controles:
##   Flechas       mover (4 direcciones cardinales, combinables en diagonal)
##   Espacio       impulso rapido en la direccion del movimiento
##   Click izq.    ataque melee en la direccion del raton
##   Click der.    ataque a distancia en la direccion del raton
##   Shift         defender (inmoviliza, gasta escudo)
##   Q             usar pocion del inventario
##
## NOTA DE ALCANCE: todo lo que se anada aqui es seguro para el benchmark. El
## barrido nunca instancia un Player -- sus escenarios usan ScriptedBot como
## sustituto del humano (ArenaSpec.Opponent.BOT) o ningun oponente humano en
## absoluto. Por eso el impulso puede existir sin invalidar las 800 filas del
## Excel ya entregado: no aparece en ninguna de ellas.

## Duracion del impulso, en ticks. Corto a proposito: es para esquivar un
## proyectil o cruzar un pasillo batido, no para viajar.
const DASH_TICKS := 10                 # ~0.17 s
const DASH_SPEED_SCALE := 3.2
const DASH_COOLDOWN_TICKS := 72        # 1.2 s

var aim_direction: Vector2 = Vector2.RIGHT

## Ticks que le quedan al impulso en curso (0 = no esta impulsandose).
var dash_ticks: int = 0
var dash_cd: int = 0
var _dash_dir: Vector2 = Vector2.RIGHT
## Posiciones recientes para la estela. Solo presentacion.
var _rastro: Array = []


func configure() -> void:
	display_name = "Jugador"
	sprite_kind = "player"
	body_color = Color(0.35, 0.85, 0.95)
	max_health = GameConfig.PLAYER_MAX_HEALTH
	health = max_health
	move_speed = GameConfig.PLAYER_SPEED
	# Mas agil que cualquier enemigo: la ventaja del jugador es el control, no
	# las estadisticas. Alcanza el maximo en ~0.10 s y frena en ~0.06 s.
	accel = 1650.0
	friction = 2600.0
	melee_damage = GameConfig.PLAYER_MELEE_DAMAGE
	ranged_damage = GameConfig.PLAYER_RANGED_DAMAGE
	can_defend = true
	max_shield = GameConfig.MAX_SHIELD
	shield = max_shield
	auto_use_potions = false   # el jugador decide cuando usarlas
	setup_team(Team.PLAYER)


## Fraccion de recarga del impulso, para la barra del HUD. 1.0 = listo.
func dash_ready_fraction() -> float:
	if dash_cd <= 0:
		return 1.0
	return 1.0 - float(dash_cd) / float(DASH_COOLDOWN_TICKS)


## Capa de decision. La llama el Arena una vez por tick.
func think(_delta: float) -> void:
	if not alive:
		return

	# Los contadores bajan aqui y no en _process: think() corre exactamente una
	# vez por tick de simulacion, asi que el impulso dura lo mismo a cualquier
	# velocidad del motor. En _process dependeria de los fotogramas por segundo.
	dash_cd = maxi(0, dash_cd - 1)

	_update_aim()
	_actualizar_rastro()

	# El impulso manda mientras dura: ni ataca ni defiende, solo se desplaza.
	# Es lo que le da su coste y lo convierte en una decision.
	#
	# Usa impulse() y no move_in_direction(): con aceleracion normal el arranque
	# se comeria la mitad de los 10 ticks y el impulso se sentiria como "correr
	# un poco mas". Saltandose la rampa, sale disparado desde el primer tick, que
	# es justo lo que permite salir de una inercia que no se puede cancelar.
	if dash_ticks > 0:
		dash_ticks -= 1
		impulse(_dash_dir, move_speed * DASH_SPEED_SCALE)
		facing = aim_direction
		return

	var move := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)

	if Input.is_action_just_pressed("dash") and dash_cd == 0:
		# Sin teclas de movimiento, el impulso sale hacia donde apunta el raton:
		# asi nunca se queda "sin direccion" y falla en seco.
		_dash_dir = move.normalized() if move.length_squared() > 0.0001 else aim_direction
		dash_ticks = DASH_TICKS
		dash_cd = DASH_COOLDOWN_TICKS
		Audio.play("dash", global_position)
		return

	# Defender inmoviliza, asi que se evalua antes que el movimiento.
	if Input.is_action_pressed("defend") and not is_shield_broken():
		set_defending(true)
		facing = aim_direction
		return

	if move.length_squared() > 0.0001:
		# Se mueve con las flechas pero encara hacia el raton: el cuerpo va a un
		# lado y el arma apunta a otro, que es lo que hace bueno el twin-stick.
		var previous_facing := aim_direction
		move_in_direction(move)
		facing = previous_facing
	else:
		stop()

	if Input.is_action_just_pressed("use_potion"):
		try_use_potion()
	if Input.is_action_pressed("attack_melee"):
		try_melee(aim_direction)
	if Input.is_action_pressed("attack_ranged"):
		try_ranged(aim_direction)


func _update_aim() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var mouse := get_global_mouse_position()
	var d := mouse - global_position
	if d.length_squared() > 1.0:
		aim_direction = d.normalized()
		facing = aim_direction


func _actualizar_rastro() -> void:
	if dash_ticks > 0:
		_rastro.push_front(global_position)
		while _rastro.size() > 6:
			_rastro.pop_back()
	elif not _rastro.is_empty():
		_rastro.pop_back()


func _draw() -> void:
	super._draw()
	if not alive:
		return
	# Estela del impulso: copias desvanecidas de las posiciones recientes.
	for i in _rastro.size():
		var alpha := 0.30 * (1.0 - float(i) / float(maxi(1, _rastro.size())))
		var local: Vector2 = (_rastro[i] as Vector2) - global_position
		draw_circle(local, GameConfig.ACTOR_RADIUS * 0.85, Color(0.45, 0.9, 1.0, alpha))
	if dash_ticks > 0:
		draw_arc(Vector2.ZERO, GameConfig.ACTOR_RADIUS + 3.0, 0.0, TAU, 18,
				Color(0.6, 0.95, 1.0, 0.8), 2.0)
