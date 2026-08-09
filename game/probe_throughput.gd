extends Node
## Diagnostico de rendimiento: mide ticks de simulacion por segundo real con N
## arenas en paralelo. Es la medida que decide si el barrido completo del
## benchmark es viable en este equipo o hay que mover el forward pass a C#.
##
## Se ejecuta como ESCENA, no con --script: en modo --script el cache de
## class_name del proyecto no esta poblado y las clases propias (Arena, Genome,
## Enemy...) se resuelven a GDScript pelado, con errores de "Nonexistent
## function 'new'". Es una limitacion del modo script, no del proyecto.
##
## Uso:
##   godot --headless --path . res://game/probe_throughput.tscn -- [arenas] [aceleracion]

var n_arenas: int = 4
var speed: float = 40.0
var seconds: int = 4

var _arenas: Array = []
var _start_ms: int = 0


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		n_arenas = maxi(1, int(user_args[0]))
	if user_args.size() > 1:
		speed = maxf(1.0, float(user_args[1]))

	Engine.max_fps = 0
	Engine.physics_ticks_per_second = int(GameConfig.TICKS_PER_SECOND * speed)
	Engine.max_physics_steps_per_frame = maxi(256, int(speed) * 8)

	print("--- probe throughput ---")
	print("arenas en paralelo:          %d" % n_arenas)
	print("aceleracion pedida:          x%.0f" % speed)
	print("physics_ticks_per_second:    %d" % Engine.physics_ticks_per_second)
	print("max_physics_steps_per_frame: %d" % Engine.max_physics_steps_per_frame)

	for i in n_arenas:
		var vp := SubViewport.new()
		vp.world_2d = World2D.new()
		vp.size = Vector2i(1, 1)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)

		var spec := ArenaSpec.create("probe", "probe")
		spec.level_name = "validation"
		spec.ga_config = ExperimentMatrix.baseline()
		spec.agent_count = 1
		spec.opponent_kind = ArenaSpec.Opponent.NONE
		spec.with_enemies("A", 1)
		spec.with_enemies("C", 1)
		spec.seed = 1000 + i
		spec.max_ticks = 1_000_000_000   # que no acabe: aqui medimos velocidad

		var arena := Arena.new()
		vp.add_child(arena)
		arena.setup(spec, false)
		_arenas.append(arena)

	_start_ms = Time.get_ticks_msec()
	await get_tree().create_timer(float(seconds)).timeout
	_report()


func _report() -> void:
	var elapsed := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	var total_ticks := 0
	for a in _arenas:
		total_ticks += (a as Arena).tick
	var per_arena: float = float(total_ticks) / float(n_arenas) / maxf(0.001, elapsed)
	var aggregate: float = float(total_ticks) / maxf(0.001, elapsed)

	print("")
	print("tiempo real:           %.2f s" % elapsed)
	print("ticks/s por arena:     %.0f   (x1 seria 60)" % per_arena)
	print("ticks/s agregados:     %.0f" % aggregate)
	print("aceleracion efectiva:  x%.1f  (se pidio x%.0f)" % [per_arena / 60.0, speed])
	print("")
	print("Un episodio de 60 s de juego (3600 ticks) tarda %.1f s reales."
			% (3600.0 / maxf(1.0, per_arena)))
	print("Los 10 escenarios x 1 repeticion tardan ~%.0f s."
			% (10.0 * 3600.0 / maxf(1.0, aggregate)))
	get_tree().quit()
