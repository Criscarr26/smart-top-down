extends Node
## Reproduccion de efectos de sonido. Autoload: Audio.
##
## Queda DESACTIVADO por defecto y solo el nivel jugable lo enciende. El
## benchmark corre decenas de miles de episodios en headless, donde cada
## disparo intentaria instanciar un reproductor: apagarlo de raiz evita ese
## coste y evita que un barrido de 11 horas intente sonar.
##
## Usa un pool fijo de reproductores. Sin el, una refriega con seis enemigos
## disparando crea y destruye nodos cada pocos frames.

const POOL_SIZE := 16
## Sonidos identicos disparados dentro de esta ventana se descartan. Sin esto,
## tres enemigos disparando en el mismo tick suenan como un chasquido saturado
## en vez de como tres disparos.
const DEDUP_MS := 35

var enabled: bool = false
var volume_db: float = -6.0

var _pool: Array[AudioStreamPlayer2D] = []
var _next: int = 0
var _last_played: Dictionary = {}


func _ready() -> void:
	# El pool se crea perezosamente en el primer play(); si el juego nunca
	# suena (benchmark), no se instancia ni un solo reproductor.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ensure_pool() -> void:
	if not _pool.is_empty():
		return
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = "Master"
		p.max_distance = 900.0
		add_child(p)
		_pool.append(p)


## Reproduce un efecto en una posicion del mundo.
func play(sound_name: String, position: Vector2 = Vector2.ZERO,
		pitch_variation: float = 0.08) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec()
	var last: int = int(_last_played.get(sound_name, -10000))
	if now - last < DEDUP_MS:
		return
	var stream := AssetLibrary.sound(sound_name)
	if stream == null:
		return
	_last_played[sound_name] = now

	_ensure_pool()
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	# Variacion de tono: el mismo WAV repetido cien veces cansa el oido.
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func stop_all() -> void:
	for p in _pool:
		p.stop()
