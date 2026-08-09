class_name Player
extends Actor
## Jugador controlado por teclado + raton (twin-stick, como Hotline Miami):
## WASD mueve, el raton apunta.
##
## Controles:
##   WASD          mover (4 direcciones cardinales, combinables en diagonal)
##   Click izq.    ataque melee en la direccion del raton
##   Click der.    ataque a distancia en la direccion del raton
##   Shift         defender (inmoviliza, gasta escudo)
##   Q             usar pocion del inventario

var aim_direction: Vector2 = Vector2.RIGHT


func configure() -> void:
	display_name = "Jugador"
	sprite_kind = "player"
	body_color = Color(0.35, 0.85, 0.95)
	max_health = GameConfig.PLAYER_MAX_HEALTH
	health = max_health
	move_speed = GameConfig.PLAYER_SPEED
	melee_damage = GameConfig.PLAYER_MELEE_DAMAGE
	ranged_damage = GameConfig.PLAYER_RANGED_DAMAGE
	can_defend = true
	max_shield = GameConfig.MAX_SHIELD
	shield = max_shield
	auto_use_potions = false   # el jugador decide cuando usarlas
	setup_team(Team.PLAYER)


## Capa de decision. La llama el Arena una vez por tick.
func think(_delta: float) -> void:
	if not alive:
		return

	_update_aim()

	# Defender tiene prioridad: inmoviliza, asi que se evalua primero.
	if Input.is_action_pressed("defend") and not is_shield_broken():
		set_defending(true)
		facing = aim_direction
		return

	var move := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if move.length_squared() > 0.0001:
		# Se mueve segun WASD pero encara hacia el raton: el cuerpo va a un lado
		# y el arma apunta a otro, que es lo que hace bueno el control twin-stick.
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
