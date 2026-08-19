class_name EnemyProfile
extends Resource
## Configuracion de un tipo de enemigo.
##
## Los tres tipos del PDF no son tres clases distintas: son el mismo Enemy con
## distinto perfil. Anadir un "Tipo D" es escribir otra factoria aqui, no otro
## script.

@export var type_id: String = "A"
@export var display_name: String = "Enemigo A"
@export var body_color: Color = Color(0.85, 0.32, 0.28)

# --- Atributos ---------------------------------------------------------------
@export var max_health: float = 80.0
@export var move_speed: float = 135.0
## Inercia. Es una palanca de diseno, no un detalle: un perseguidor pesado se
## pasa de frenada y deja huecos para contraatacar; un kiter ligero cambia de
## sentido en seco y cuesta acorralarlo.
@export var accel: float = GameConfig.ACCEL_DEFAULT
@export var friction: float = GameConfig.FRICTION_DEFAULT
@export var melee_damage: float = 20.0
@export var ranged_damage: float = 12.0

# --- Capacidades (que estados se registran en la FSM) ------------------------
@export var can_melee: bool = true
@export var can_ranged: bool = false
@export var can_defend: bool = false
@export var can_flee: bool = false
@export var can_seek_potion: bool = true
## Tipo D: cura a los aliados heridos que tenga cerca.
@export var can_heal: bool = false
## Si es false el enemigo no se desplaza en Idle: vigila girando sobre si mismo.
@export var patrols: bool = true

# --- Apoyo (Tipo D) -----------------------------------------------------------
## Distancia a la que puede aplicar la curacion.
@export var heal_range: float = 150.0
## Distancia a la que busca pacientes. Mayor que heal_range: se desplaza hacia
## quien lo necesita en vez de esperar a que venga.
@export var heal_search_range: float = 460.0
## Salud devuelta por tick de simulacion (a 60 Hz, x60 para tener el ritmo por
## segundo). 0.35 son 21 de salud por segundo: suficiente para que ignorarlo
## cueste la partida, poco para que sea imbatible.
@export var heal_per_tick: float = 0.35

# --- Umbrales de transicion (en pixeles) -------------------------------------
## Estado al que salta desde Idle cuando detecta al objetivo.
@export var detect_state: String = "Perseguir"
## Distancia a la que se lanza el melee.
@export var melee_range: float = GameConfig.MELEE_RANGE * 0.85
## Tipo B: por debajo de esta distancia levanta la guardia.
@export var defend_radius: float = 90.0
## Tipo C: por debajo de esta distancia huye.
@export var flee_radius: float = 130.0
## Tipo C: si el jugador se le pega tanto, contraataca en vez de seguir huyendo.
@export var panic_melee_radius: float = 42.0
## Distancia minima que intenta mantener para disparar comodo.
@export var preferred_range: float = 190.0


# =============================================================================
# Factorias de los tres tipos del PDF (seccion 3.1.3)
# =============================================================================

## Tipo A - Persigue y golpea cuerpo a cuerpo. Busca pocion si esta herido.
static func type_a() -> EnemyProfile:
	var p := EnemyProfile.new()
	p.type_id = "A"
	p.display_name = "Enemigo A (perseguidor)"
	p.body_color = UI.COLOR_A
	p.max_health = 85.0
	p.move_speed = 142.0
	# Pesado: se pasa de frenada al perseguir, y ese sobrepaso es la ventana que
	# tiene el jugador para rodearlo y contraatacar.
	p.accel = 900.0
	p.friction = 1300.0
	p.melee_damage = 22.0
	p.can_melee = true
	p.can_ranged = false
	p.can_defend = false
	p.can_flee = false
	p.can_seek_potion = true
	p.patrols = true
	p.detect_state = StateMachine.CHASE
	return p


## Tipo B - No se mueve al detectar: dispara. Si el jugador se acerca, se
## defiende. No busca pociones (nunca abandona su puesto).
static func type_b() -> EnemyProfile:
	var p := EnemyProfile.new()
	p.type_id = "B"
	p.display_name = "Enemigo B (torreta)"
	p.body_color = UI.COLOR_B
	p.max_health = 70.0
	p.move_speed = 0.0
	p.ranged_damage = 13.0
	p.can_melee = false
	p.can_ranged = true
	p.can_defend = true
	p.can_flee = false
	p.can_seek_potion = false
	p.patrols = false
	p.detect_state = StateMachine.RANGED
	p.defend_radius = 95.0
	return p


## Tipo C - Kiter: dispara de lejos, huye si se acercan, contraataca a
## quemarropa, y busca pocion si esta herido.
static func type_c() -> EnemyProfile:
	var p := EnemyProfile.new()
	p.type_id = "C"
	p.display_name = "Enemigo C (kiter)"
	p.body_color = UI.COLOR_C
	p.max_health = 65.0
	p.move_speed = 152.0
	# Ligero: cambia de sentido casi en seco, que es lo que hace dificil
	# acorralarlo y justifica su papel de kiter.
	p.accel = 2100.0
	p.friction = 2800.0
	p.melee_damage = 16.0
	p.ranged_damage = 12.0
	p.can_melee = true
	p.can_ranged = true
	p.can_defend = false
	p.can_flee = true
	p.can_seek_potion = true
	p.patrols = true
	p.detect_state = StateMachine.RANGED
	p.flee_radius = 135.0
	p.panic_melee_radius = 42.0
	return p


## Tipo D - Sanador de apoyo. No pelea de cerca: cura a los aliados heridos y
## huye si lo presionan. Obliga a decidir a quien matar primero (ver
## SupportState). Fragil a proposito.
static func type_d() -> EnemyProfile:
	var p := EnemyProfile.new()
	p.type_id = "D"
	p.display_name = "Enemigo D (sanador)"
	p.body_color = UI.COLOR_D
	p.max_health = 55.0
	p.move_speed = 138.0
	p.accel = 1500.0
	p.friction = 2000.0
	p.melee_damage = 0.0
	p.ranged_damage = 8.0
	p.can_melee = false
	p.can_ranged = true
	p.can_defend = false
	p.can_flee = true
	p.can_seek_potion = true
	p.can_heal = true
	p.patrols = true
	p.detect_state = StateMachine.SUPPORT
	p.flee_radius = 165.0
	p.preferred_range = 240.0
	return p


## Perfil base del agente entrenado: tiene TODAS las acciones disponibles
## (requisito 3.d del PDF). No usa FSM; la red neuronal decide.
static func agent() -> EnemyProfile:
	var p := EnemyProfile.new()
	p.type_id = "AGENT"
	p.display_name = "Agente (RL)"
	p.body_color = UI.COLOR_AGENTE
	p.max_health = 85.0
	p.move_speed = 145.0
	p.melee_damage = 20.0
	p.ranged_damage = 12.0
	p.can_melee = true
	p.can_ranged = true
	p.can_defend = true
	p.can_flee = true
	p.can_seek_potion = true
	p.patrols = true
	return p


static func by_type(type_id: String) -> EnemyProfile:
	match type_id.to_upper():
		"A": return type_a()
		"B": return type_b()
		"C": return type_c()
		"D": return type_d()
		"AGENT": return agent()
	push_error("EnemyProfile: tipo desconocido '%s'" % type_id)
	return type_a()
