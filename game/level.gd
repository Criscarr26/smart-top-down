extends Node2D
## Partida jugable. Monta un Arena en modo interactivo con el jugador humano
## contra los tres tipos de enemigo FSM y el agente entrenado.
##
## Usa EXACTAMENTE el mismo Arena que el benchmark; la unica diferencia es
## `interactive = true` (que enciende el dibujado) y que el bando "jugador" lo
## ocupa una persona en vez del bot.

## Cambiar en el inspector para jugar los niveles 2 y 3, o el de validacion.
@export_enum("level_01", "level_02", "level_03", "validation")
var level_name: String = "level_01"

@export var enemies_type_a: int = 2
@export var enemies_type_b: int = 1
@export var enemies_type_c: int = 1
## Agentes entrenados que acompanan a los enemigos. Cargan el genoma de
## `res://results/genomas/` si existe; si no, salen con pesos aleatorios.
@export var trained_agents: int = 1

const GENOME_PATH := "res://results/genoma_base_base.json"

var arena: Arena
var _camera: Camera2D
var _hud: Label
var _banner: Label


func _ready() -> void:
	Audio.enabled = true
	_build_arena()
	_build_camera()
	_build_hud()
	if not AssetLibrary.has_art():
		print("[Level] No hay arte generado. Corre:")
		print("        python tools/generate_sprites.py")
		print("        python tools/generate_sfx.py")


func _build_arena() -> void:
	var spec := ArenaSpec.create("jugable", "Partida jugable")
	spec.level_name = level_name
	spec.opponent_kind = ArenaSpec.Opponent.HUMAN
	spec.agent_count = trained_agents
	spec.ga_config = ExperimentMatrix.baseline()
	spec.agent_genome = _load_genome()
	# En la partida jugable TODOS los enemigos van contra el jugador: el agente
	# entrenado es un enemigo mas, no el rival de los enemigos FSM.
	spec.fsm_opposes_agent = false
	if enemies_type_a > 0:
		spec.with_enemies("A", enemies_type_a)
	if enemies_type_b > 0:
		spec.with_enemies("B", enemies_type_b)
	if enemies_type_c > 0:
		spec.with_enemies("C", enemies_type_c)
	spec.seed = int(Time.get_unix_time_from_system())
	spec.max_ticks = 999_999   # sin limite de tiempo cuando juega una persona

	arena = Arena.new()
	add_child(arena)
	arena.episode_finished.connect(_on_episode_finished)
	arena.setup(spec, true)


## Carga el mejor genoma entrenado si el benchmark ya corrio alguna vez.
func _load_genome() -> Genome:
	if not FileAccess.file_exists(GENOME_PATH):
		print("[Level] Sin genoma entrenado en %s; el agente saldra con pesos "
				% GENOME_PATH + "aleatorios. Corre el benchmark para generarlo.")
		return null
	var f := FileAccess.open(GENOME_PATH, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("[Level] Genoma ilegible en %s" % GENOME_PATH)
		return null
	print("[Level] Genoma entrenado cargado desde %s" % GENOME_PATH)
	return Genome.from_dict(parsed)


func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.zoom = Vector2(1.6, 1.6)
	# Amortiguacion: el seguimiento duro marea en top-down rapido.
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	# Limites al borde del nivel: sin esto, al pegarse a una esquina la camara
	# encuadra medio nivel y medio vacio gris.
	var size := arena.world_size()
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(size.x)
	_camera.limit_bottom = int(size.y)
	add_child(_camera)
	_camera.make_current()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	layer.add_child(_hud)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.visible = false
	layer.add_child(_banner)


func _process(_delta: float) -> void:
	var player := _find_player()
	if player != null and _camera != null:
		_camera.global_position = player.global_position
	_update_hud(player)

	if Input.is_action_just_pressed("restart_level"):
		get_tree().reload_current_scene()
	if Input.is_action_just_pressed("toggle_debug"):
		Enemy.debug_draw = not Enemy.debug_draw
	if Input.is_action_just_pressed("open_menu"):
		get_tree().change_scene_to_file("res://game/main_menu.tscn")


func _find_player() -> Player:
	if arena == null:
		return null
	for a in arena.actors:
		if a is Player:
			return a as Player
	return null


func _update_hud(player: Player) -> void:
	if _hud == null:
		return
	if player == null:
		_hud.text = "—"
		return
	var enemies_alive := 0
	for a in arena.actors:
		var actor := a as Actor
		if actor.alive and actor.team == Actor.Team.ENEMY:
			enemies_alive += 1
	var shield_text := "ROTO" if player.is_shield_broken() else "%3.0f" % player.shield
	_hud.text = "Salud %3.0f/%3.0f   Escudo %s   Pociones %d   Enemigos vivos %d\n%s" % [
		player.health, player.max_health, shield_text, player.potions, enemies_alive,
		"WASD mover · click izq melee · click der disparo · Shift defender · Q pocion · R reiniciar · F1 depuracion FSM · Esc menu",
	]


func _on_episode_finished(result: Dictionary) -> void:
	if _banner == null:
		return
	_banner.visible = true
	var reason := str(result.get("motivo_fin", ""))
	if reason == "bando_enemigo_eliminado":
		_banner.text = "NIVEL SUPERADO\nR reiniciar  ·  Esc menu"
		_banner.modulate = Color(0.5, 1.0, 0.6)
	else:
		_banner.text = "HAS MUERTO\nR reiniciar  ·  Esc menu"
		_banner.modulate = Color(1.0, 0.45, 0.45)
