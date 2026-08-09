extends Node
## Captura una imagen del juego en marcha, para comprobar el apartado visual sin
## tener que jugarlo a mano. No forma parte del juego.
##
## Monta un Arena interactivo con el bot ocupando el bando del jugador (asi hay
## combate real sin que nadie toque el teclado), deja correr unos segundos y
## guarda un PNG.
##
## Uso:
##   godot --path . res://game/capture_preview.tscn -- [segundos] [nivel]

var seconds: float = 5.0
var level_name: String = "level_01"
var out_path: String = "res://assets/preview_game.png"

var _arena: Arena
var _camera: Camera2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# Modo "menu": captura el menu principal en vez de una partida.
	if args.size() > 0 and str(args[0]) == "menu":
		out_path = "res://assets/preview_menu.png"
		add_child(load("res://game/main_menu.tscn").instantiate())
		await get_tree().create_timer(1.5).timeout
		await _capture()
		return
	if args.size() > 0:
		seconds = maxf(0.5, float(args[0]))
	if args.size() > 1:
		level_name = str(args[1])

	Audio.enabled = false          # captura silenciosa
	Enemy.debug_draw = true        # muestra estados y radios en la imagen

	var spec := ArenaSpec.create("preview", "Captura")
	spec.level_name = level_name
	spec.opponent_kind = ArenaSpec.Opponent.BOT
	spec.ga_config = ExperimentMatrix.baseline()
	spec.agent_count = 1
	spec.fsm_opposes_agent = false   # todos los enemigos contra el bot
	spec.with_enemies("A", 2)
	spec.with_enemies("B", 1)
	spec.with_enemies("C", 1)
	spec.seed = 4242
	spec.max_ticks = 999_999

	_arena = Arena.new()
	add_child(_arena)
	_arena.setup(spec, true)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(1.35, 1.35)
	var size := _arena.world_size()
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(size.x)
	_camera.limit_bottom = int(size.y)
	add_child(_camera)
	_camera.make_current()

	await get_tree().create_timer(seconds).timeout
	await _capture()


func _process(_delta: float) -> void:
	# Encuadra al bot, que es donde ocurre la accion.
	if _arena == null or _camera == null:
		return
	for a in _arena.actors:
		if a is ScriptedBot and (a as Actor).alive:
			_camera.global_position = (a as Actor).global_position
			return


func _capture() -> void:
	# Hay que esperar a que el frame se haya dibujado del todo; si no, la
	# textura del viewport puede venir vacia.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(out_path))
	if err == OK:
		print("Captura guardada en %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	else:
		push_error("No se pudo guardar la captura (error %d)" % err)
	get_tree().quit()
