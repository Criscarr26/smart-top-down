class_name ArenaView
extends Control
## Muestra la arena que se esta simulando, con su rotulo y su leyenda.
##
## La imagen es la textura del SubViewport del SimPool, asi que el mismo render
## alimenta el panel del laboratorio y la ventana aparte sin costar un segundo
## dibujado. Los sensores y las decisiones del agente los pinta AgentOverlay,
## que vive DENTRO del viewport porque va en coordenadas de mundo.
##
## La textura se cuelga de un hijo con z_index -1 para que el _draw de este
## Control quede por encima: un Control dibuja lo suyo antes que sus hijos.

const LEYENDA := [
	[UI.COLOR_AGENTE, "Agente"],
	[UI.COLOR_A, "A"],
	[UI.COLOR_B, "B"],
	[UI.COLOR_C, "C"],
	[UI.COLOR_D, "D"],
	[UI.COLOR_JUGADOR, "Bot"],
]

var pool: SimPool
## Texto extra que el laboratorio pone en la esquina (etapa, generacion...).
var subtitulo: String = ""

var _tex: TextureRect


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = TextureRect.new()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.z_index = -1
	add_child(_tex)


func soltar() -> void:
	if _tex != null and is_instance_valid(_tex):
		_tex.texture = null
	queue_redraw()


func _process(_delta: float) -> void:
	# La textura no existe hasta que el pool crea sus ranuras, y eso ocurre
	# dentro del primer lote. Por eso se engancha aqui y no al construir.
	if pool != null and is_instance_valid(pool) and _tex != null and _tex.texture == null:
		_tex.texture = pool.showcase_texture()
	queue_redraw()


func _draw() -> void:
	if _tex == null or _tex.texture == null:
		UI.caja_dibujada(self, Rect2(Vector2.ZERO, size), UI.PANEL, UI.BORDE)
		UI.texto_dibujado(self, Vector2(size.x * 0.5, size.y * 0.5),
				"la arena aparece aqui al empezar", UI.T_CUERPO, UI.APAGADO,
				HORIZONTAL_ALIGNMENT_CENTER)
		return

	var arena: Arena = null
	if pool != null and is_instance_valid(pool):
		arena = pool.showcase_arena
	var rotulo := "esperando episodio..."
	if arena != null and is_instance_valid(arena) and arena.spec != null:
		rotulo = "%s    %s    tick %d" % [arena.spec.scenario_id,
				arena.spec.level_name, arena.tick]
	if subtitulo != "":
		rotulo += "    " + subtitulo

	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 20.0)), Color(0.04, 0.04, 0.06, 0.85))
	UI.texto_dibujado(self, Vector2(8, 14), rotulo, UI.T_PEQUENO, UI.ACENTO)

	if size.x < 300.0:
		return
	draw_rect(Rect2(Vector2(0.0, size.y - 20.0), Vector2(size.x, 20.0)),
			Color(0.04, 0.04, 0.06, 0.82))
	var x := 8.0
	for e in LEYENDA:
		draw_rect(Rect2(Vector2(x, size.y - 14.0), Vector2(9, 9)), e[0])
		UI.texto_dibujado(self, Vector2(x + 13.0, size.y - 6.0), str(e[1]),
				UI.T_MICRO, UI.TENUE)
		x += 22.0 + ThemeDB.fallback_font.get_string_size(
				str(e[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.T_MICRO).x
