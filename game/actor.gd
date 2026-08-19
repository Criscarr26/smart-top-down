class_name Actor
extends CharacterBody2D
## Base comun de jugador, enemigos FSM y agente neuroevolutivo.
##
## Los actores NO tienen _physics_process propio: el Arena los recorre en orden
## estable y llama sim_tick() sobre cada uno. Esto elimina la dependencia del
## orden del arbol de escena, que no esta garantizado al instanciar actores en
## caliente y romperia la reproducibilidad del benchmark.

enum Team { PLAYER, ENEMY }

signal died(actor: Actor, killer: Actor)
## El Arena escucha esta senal y crea el proyectil; el actor no conoce la escena.
signal projectile_requested(shooter: Actor, from: Vector2, dir: Vector2, damage: float)
## Golpe recibido, para los numeros flotantes y las particulas.
##
## SOLO se emite en modo interactivo (ver `visuals_enabled`). En el barrido hay
## decenas de millones de golpes y ninguno tiene a nadie escuchando: emitir la
## senal de todas formas seria trabajo puro de descarte.
signal damaged(actor: Actor, applied: float, blocked: float)

@export var team: Team = Team.ENEMY
@export var display_name: String = "Actor"
@export var body_color: Color = Color(0.8, 0.3, 0.3)

# --- Atributos ---------------------------------------------------------------
var max_health: float = 100.0
var health: float = 100.0
var max_shield: float = GameConfig.MAX_SHIELD
var shield: float = GameConfig.MAX_SHIELD
var move_speed: float = 140.0
## Aceleracion y frenado, en px/s^2. Los perfiles los ajustan: un perseguidor
## pesado se pasa de frenada, un kiter cambia de sentido en seco.
var accel: float = GameConfig.ACCEL_DEFAULT
var friction: float = GameConfig.FRICTION_DEFAULT
var melee_damage: float = 22.0
var ranged_damage: float = 14.0
var can_defend: bool = true

# --- Estado ------------------------------------------------------------------
var alive: bool = true
var facing: Vector2 = Vector2.RIGHT
var potions: int = 0
var is_defending: bool = false
## El jugador guarda las pociones en inventario y las usa con una tecla; el
## resto de actores las consumen al recogerlas. El Arena consulta este flag.
var auto_use_potions: bool = true

# --- Cooldowns, en ticks (nunca en segundos: ver GameConfig) ------------------
var melee_cd: int = 0
var ranged_cd: int = 0
var shield_break_cd: int = 0
var ticks_since_defend: int = 999

# --- Metricas para el benchmark ----------------------------------------------
var damage_dealt: float = 0.0
var damage_taken: float = 0.0
## Dano absorbido por el escudo. Alimenta el termino "esquivar/evitar dano" de
## la funcion de fitness.
var damage_blocked: float = 0.0
var kills: int = 0
var deaths: int = 0
var ticks_alive: int = 0
var potions_used: int = 0
var melee_swings: int = 0
var melee_hits: int = 0
var shots_fired: int = 0
var ticks_defending: int = 0
var ticks_fleeing: int = 0
## Ticks con un rival dentro del rango de combate. Es el termino de shaping que
## le da gradiente al fitness antes de que ningun individuo sepa hacer dano.
var ticks_engaged: int = 0

## Generador PROPIO DE LA ARENA, inyectado al registrarse.
##
## No se usa el autoload Rng dentro de los episodios: el benchmark corre varias
## arenas en paralelo y todas consumirian del mismo flujo de forma intercalada,
## asi que dos corridas con la misma semilla darian resultados distintos segun
## como se solaparan. Con un generador por arena, cada episodio es reproducible
## por si mismo. El autoload Rng se reserva para el algoritmo genetico, que
## corre en el hilo principal entre lotes y no sufre ese solapamiento.
var rng: RandomNumberGenerator = null

var _collision_shape: CollisionShape2D
## Objetos de consulta del melee, reutilizados (ver try_melee).
var _melee_query: PhysicsShapeQueryParameters2D

# --- Presentacion (solo se crea en modo interactivo) -------------------------
var _sprite: Sprite2D = null
var _muzzle: Sprite2D = null
var _muzzle_ticks: int = 0
## Ticks restantes del destello blanco al recibir dano.
var _hit_flash: int = 0
## Clave del sprite ("player", "a", "b", "c", "agent"). La fija cada subclase.
var sprite_kind: String = "player"
## True cuando el actor forma parte de una partida que se dibuja. Es la puerta
## de todo lo que solo tiene sentido con alguien mirando.
var visuals_enabled: bool = false


func _ready() -> void:
	_ensure_collision()
	_build_melee_query()
	# Los actores se dibujan con formas primitivas para que el proyecto corra
	# sin depender de assets externos. Sustituir por Sprite2D/AnimatedSprite2D
	# al integrar el arte definitivo (requisito 10 del PDF).
	queue_redraw()


## Crea el CollisionShape2D si el actor fue instanciado por codigo (caso del
## benchmark, que arma las arenas sin .tscn) en vez de venir de una escena.
func _ensure_collision() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			_collision_shape = child
			return
	var shape := CircleShape2D.new()
	shape.radius = GameConfig.ACTOR_RADIUS
	_collision_shape = CollisionShape2D.new()
	_collision_shape.shape = shape
	add_child(_collision_shape)


func _build_melee_query() -> void:
	var shape := CircleShape2D.new()
	shape.radius = GameConfig.MELEE_RANGE
	_melee_query = PhysicsShapeQueryParameters2D.new()
	_melee_query.shape = shape
	_melee_query.collide_with_bodies = true
	_melee_query.collide_with_areas = false


## Configura capas de fisica segun el bando. La mascara solo incluye el mundo:
## los actores se atraviesan entre si para que el pathfinding no se atasque en
## cuellos de botella, y el combate se resuelve por consultas explicitas.
func setup_team(new_team: Team) -> void:
	team = new_team
	collision_layer = GameConfig.LAYER_PLAYER if team == Team.PLAYER else GameConfig.LAYER_ENEMY
	collision_mask = GameConfig.LAYER_WORLD


## Capa de fisica del bando contrario; usada para buscar objetivos.
func enemy_layer() -> int:
	return GameConfig.LAYER_ENEMY if team == Team.PLAYER else GameConfig.LAYER_PLAYER


func reset_stats() -> void:
	damage_dealt = 0.0
	damage_taken = 0.0
	damage_blocked = 0.0
	kills = 0
	deaths = 0
	ticks_alive = 0
	potions_used = 0
	melee_swings = 0
	melee_hits = 0
	shots_fired = 0
	ticks_defending = 0
	ticks_fleeing = 0
	ticks_engaged = 0


# =============================================================================
# Ciclo de simulacion
# =============================================================================

## Mantenimiento por tick: cooldowns, escudo y contadores. El Arena lo llama
## ANTES de pedirle su decision al cerebro (FSM o red neuronal).
func sim_tick() -> void:
	if not alive:
		return
	ticks_alive += 1
	melee_cd = maxi(0, melee_cd - 1)
	ranged_cd = maxi(0, ranged_cd - 1)
	shield_break_cd = maxi(0, shield_break_cd - 1)

	if is_defending:
		ticks_defending += 1
		ticks_since_defend = 0
		shield = maxf(0.0, shield - GameConfig.SHIELD_DRAIN_PER_TICK)
		if shield <= 0.0:
			_break_shield()
	else:
		ticks_since_defend += 1
		if ticks_since_defend > GameConfig.SHIELD_REGEN_DELAY_TICKS and shield_break_cd == 0:
			shield = minf(max_shield, shield + GameConfig.SHIELD_REGEN_PER_TICK)

	# La guardia cae sola cada tick; quien quiera defender debe re-afirmarlo.
	# Asi el estado "defender" siempre refleja la decision del tick actual.
	is_defending = false


func is_shield_broken() -> bool:
	return shield_break_cd > 0


func _break_shield() -> void:
	shield = 0.0
	is_defending = false
	shield_break_cd = GameConfig.SHIELD_BREAK_TICKS
	Audio.play("shield_break", global_position)


func health_fraction() -> float:
	return 0.0 if max_health <= 0.0 else clampf(health / max_health, 0.0, 1.0)


func shield_fraction() -> float:
	return 0.0 if max_shield <= 0.0 else clampf(shield / max_shield, 0.0, 1.0)


func is_low_health() -> bool:
	return health_fraction() < GameConfig.LOW_HEALTH_FRACTION


# =============================================================================
# Movimiento
# =============================================================================

## Acelera hacia la direccion dada y aplica el desplazamiento del tick.
##
## No usa move_and_slide() a proposito: ese metodo lee el delta escalado del
## motor, que cambia con Engine.time_scale y romperia el determinismo del
## benchmark (ver GameConfig). Todo avanza con SIM_DT fijo.
##
## POR QUE HAY INERCIA. La primera version asignaba `velocity = dir * speed`,
## asi que un actor pasaba de 0 a velocidad maxima y de vuelta a 0 en un solo
## tick. Se movia con precision perfecta y por eso mismo no habia nada que
## dominar: esquivar era apretar la tecla contraria. Con aceleracion y frenado
## el posicionamiento pasa a ser una habilidad, el impulso tiene sentido (te
## saca de una inercia que no puedes cancelar) y los enemigos se pasan de frenada
## al perseguir, que es lo que abre huecos para contraatacar.
func move_in_direction(dir: Vector2, speed_scale: float = 1.0) -> void:
	if not alive:
		return
	var objetivo := Vector2.ZERO
	if dir.length_squared() > 0.0001:
		var dir_n := dir.normalized()
		facing = dir_n
		objetivo = dir_n * move_speed * speed_scale
	var tasa: float = accel if objetivo != Vector2.ZERO else friction
	velocity = velocity.move_toward(objetivo, tasa * GameConfig.SIM_DT)
	_apply_motion()


## Frenada progresiva. Para el corte seco (defender inmoviliza) esta halt().
func stop() -> void:
	if not alive:
		return
	velocity = velocity.move_toward(Vector2.ZERO, friction * GameConfig.SIM_DT)
	if velocity.length_squared() > 1.0:
		_apply_motion()
	else:
		velocity = Vector2.ZERO


## Corta la velocidad en el acto, sin frenada. Lo usa la guardia, que segun el
## requisito 2.e del PDF inmoviliza.
func halt() -> void:
	velocity = Vector2.ZERO


## Empuje instantaneo, saltandose la aceleracion. Es lo que hace que el impulso
## del jugador se sienta como un impulso y no como "correr un poco mas".
func impulse(dir: Vector2, speed: float) -> void:
	if not alive or dir.length_squared() <= 0.0001:
		return
	velocity = dir.normalized() * speed
	_apply_motion()


## Desplaza segun la velocidad actual, deslizando por las paredes.
##
## Al chocar, la velocidad se proyecta sobre la pared ademas del movimiento
## restante. Sin eso el actor conservaba toda su inercia contra el muro y salia
## disparado en cuanto lo esquivaba, o se quedaba pegado empujando contra el.
func _apply_motion() -> void:
	var motion := velocity * GameConfig.SIM_DT
	# Hasta 4 deslizamientos por tick: suficiente para esquinas, y acotado para
	# que el coste por tick sea constante.
	for _i in 4:
		if motion.length_squared() <= 0.000001:
			break
		var col := move_and_collide(motion)
		if col == null:
			break
		var normal := col.get_normal()
		velocity = velocity.slide(normal)
		motion = col.get_remainder().slide(normal)


## Velocidad actual como fraccion de la maxima. Para el HUD y los sensores.
func speed_fraction() -> float:
	if move_speed <= 0.0:
		return 0.0
	return clampf(velocity.length() / move_speed, 0.0, 1.0)


func face_towards(point: Vector2) -> void:
	var d := point - global_position
	if d.length_squared() > 0.0001:
		facing = d.normalized()


# =============================================================================
# Combate
# =============================================================================

## Ataque melee en arco frontal. Devuelve true si el golpe llego a lanzarse
## (no si conecto), porque el cooldown se consume igual.
func try_melee(dir: Vector2 = Vector2.ZERO) -> bool:
	if not alive or melee_cd > 0 or is_defending:
		return false
	if dir.length_squared() > 0.0001:
		facing = dir.normalized()
	melee_cd = GameConfig.MELEE_COOLDOWN_TICKS
	melee_swings += 1
	Audio.play("melee", global_position)

	# Consulta directa al espacio de fisica en lugar de un Area2D-hitbox: un
	# Area2D necesita un tick completo para registrar solapamientos, lo que
	# mete 1 tick de latencia entre la accion de la red y su consecuencia. Esa
	# desincronizacion ensucia la senal de fitness del algoritmo genetico.
	#
	# Los objetos de consulta se reutilizan entre golpes: crearlos en cada
	# ataque generaba basura constante y se notaba en el barrido del benchmark,
	# donde hay miles de ataques por segundo entre todas las arenas.
	var space := get_world_2d().direct_space_state
	_melee_query.transform = Transform2D(0.0, global_position)
	_melee_query.collision_mask = enemy_layer()

	var connected := false
	for hit in space.intersect_shape(_melee_query, 12):
		var other := hit.get("collider") as Actor
		if other == null or other == self or not other.alive:
			continue
		var to_other: Vector2 = other.global_position - global_position
		if absf(facing.angle_to(to_other)) > GameConfig.MELEE_ARC:
			continue
		other.take_damage(melee_damage, self)
		connected = true
	if connected:
		melee_hits += 1
	return true


## Dispara un proyectil. El Arena lo materializa al recibir la senal.
func try_ranged(dir: Vector2) -> bool:
	if not alive or ranged_cd > 0 or is_defending:
		return false
	if dir.length_squared() <= 0.0001:
		return false
	facing = dir.normalized()
	ranged_cd = GameConfig.RANGED_COOLDOWN_TICKS
	shots_fired += 1
	_muzzle_ticks = 4
	Audio.play("shoot_player" if team == Team.PLAYER else "shoot_enemy", global_position)
	# Nace fuera del propio cuerpo para no colisionar con el tirador.
	var origin := global_position + facing * (GameConfig.ACTOR_RADIUS + 4.0)
	projectile_requested.emit(self, origin, facing, ranged_damage)
	return true


## Levanta la guardia para ESTE tick. Debe llamarse cada tick que se quiera
## seguir defendiendo (sim_tick la baja automaticamente).
func set_defending(value: bool) -> void:
	if not can_defend or is_shield_broken() or not alive:
		is_defending = false
		return
	is_defending = value
	if value:
		halt()  # defender inmoviliza en el acto (requisito 2.e del PDF)


func try_use_potion() -> bool:
	if not alive or potions <= 0 or health >= max_health:
		return false
	potions -= 1
	potions_used += 1
	Audio.play("potion", global_position)
	heal(GameConfig.POTION_HEAL)
	return true


func take_damage(amount: float, source: Actor = null) -> float:
	if not alive or amount <= 0.0:
		return 0.0
	var applied := amount
	if is_defending and not is_shield_broken():
		applied = amount * GameConfig.SHIELD_DAMAGE_PASSTHROUGH
		var blocked := amount - applied
		damage_blocked += blocked
		shield -= blocked * GameConfig.SHIELD_COST_PER_DAMAGE
		Audio.play("shield_hit", global_position)
		if shield <= 0.0:
			_break_shield()
	else:
		Audio.play("hit", global_position)
	_hit_flash = 6
	health -= applied
	damage_taken += applied
	if source != null and is_instance_valid(source):
		source.damage_dealt += applied
	if visuals_enabled:
		damaged.emit(self, applied, amount - applied)
	if health <= 0.0:
		health = 0.0
		die(source)
	return applied


func heal(amount: float) -> void:
	if not alive:
		return
	health = minf(max_health, health + amount)


func die(killer: Actor = null) -> void:
	if not alive:
		return
	alive = false
	deaths += 1
	is_defending = false
	velocity = Vector2.ZERO
	Audio.play("death", global_position)
	if killer != null and is_instance_valid(killer) and killer != self:
		killer.kills += 1
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	visible = false
	died.emit(self, killer)


# =============================================================================
# Presentacion (arte provisional)
# =============================================================================

func _draw() -> void:
	if not alive:
		return
	# El cuerpo solo se dibuja a mano cuando NO hay sprite: asi el proyecto
	# sigue siendo jugable aunque no se hayan generado los assets.
	if _sprite == null:
		draw_circle(Vector2.ZERO, GameConfig.ACTOR_RADIUS, body_color)
		draw_line(Vector2.ZERO, facing * (GameConfig.ACTOR_RADIUS + 7.0), Color.WHITE, 2.0)
	# Barra de salud
	var w := 26.0
	var top := Vector2(-w * 0.5, -GameConfig.ACTOR_RADIUS - 10.0)
	draw_rect(Rect2(top, Vector2(w, 3.0)), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(top, Vector2(w * health_fraction(), 3.0)), Color(0.2, 0.9, 0.3))
	if max_shield > 0.0 and shield_fraction() > 0.0:
		var stop_ := top + Vector2(0.0, -4.0)
		draw_rect(Rect2(stop_, Vector2(w * shield_fraction(), 2.0)),
				Color(0.35, 0.65, 1.0) if not is_shield_broken() else Color(0.6, 0.3, 0.3))
	if is_defending:
		draw_arc(Vector2.ZERO, GameConfig.ACTOR_RADIUS + 5.0, 0.0, TAU, 20, Color(0.4, 0.7, 1.0), 2.0)


func _process(_delta: float) -> void:
	# Solo presentacion; no contiene logica de juego. El Arena apaga _process
	# en modo benchmark, asi que esto no corre durante el barrido.
	_update_visuals()
	queue_redraw()


## Crea el sprite y el destello de disparo. Solo lo llama el Arena en modo
## interactivo: en el benchmark no hay nada que dibujar.
func enable_visuals() -> void:
	# Se marca ANTES de mirar si hay textura: sin arte generado el actor sigue
	# dibujandose con primitivas, y los efectos deben salir igual.
	visuals_enabled = true
	var tex := AssetLibrary.actor_texture(sprite_kind)
	if tex == null:
		return   # sin arte generado, se cae al dibujado por primitivas
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	add_child(_sprite)

	var flash := AssetLibrary.texture("muzzle_flash")
	if flash != null:
		_muzzle = Sprite2D.new()
		_muzzle.texture = flash
		_muzzle.position = Vector2(GameConfig.ACTOR_RADIUS + 6.0, 0.0)
		_muzzle.visible = false
		add_child(_muzzle)


func _update_visuals() -> void:
	if _sprite == null:
		return
	# El sprite se dibuja mirando a +X, asi que basta rotarlo al angulo de
	# `facing` para que encare a donde apunta el actor.
	_sprite.rotation = facing.angle()
	if _hit_flash > 0:
		_hit_flash -= 1
		var t := float(_hit_flash) / 6.0
		_sprite.modulate = Color(1.0 + t * 1.6, 1.0 + t * 1.2, 1.0 + t * 1.2)
	else:
		_sprite.modulate = Color.WHITE
	if _muzzle != null:
		if _muzzle_ticks > 0:
			_muzzle_ticks -= 1
			_muzzle.visible = true
			_muzzle.rotation = facing.angle()
			_muzzle.position = facing * (GameConfig.ACTOR_RADIUS + 7.0)
		else:
			_muzzle.visible = false


## Rompe las referencias ciclicas antes de liberar el actor.
##
## GDScript cuenta referencias pero NO recoge ciclos. Un Enemy apunta a su
## StateMachine, que apunta a cada EnemyState, que apunta de vuelta al Enemy:
## ese ciclo nunca baja a cero y el objeto no se libera jamas. En una partida da
## igual, pero el benchmark crea y destruye decenas de miles de actores y la
## memoria crecia sin techo durante toda la corrida (se veia como
## "ObjectDB instances were leaked at exit").
##
## Las subclases lo sobrescriben para limpiar sus propias referencias.
func dispose() -> void:
	rng = null
