class_name ArenaView
extends Control
## Muestra la arena que se esta simulando, con su rotulo y su leyenda.
##
## La imagen es la textura del SubViewport del SimPool, asi que el mismo render
## alimenta el panel del laboratorio y la ventana aparte sin costar un segundo
## dibujado. Los sensores y las decisiones del agente los pinta AgentOverlay,
## que vive DENTRO del viewport porque va en coordenadas de mundo.
##
## ESTRUCTURA, Y POR QUE ES ASI:
##   hijo 1  TextureRect con la imagen de la arena
##   hijo 2  Overlay, un Control que dibuja el rotulo y la leyenda encima
##
## La primera version tenia un solo hijo (el TextureRect) con `z_index = -1`,
## para que el _draw de este Control quedara por encima -- un Control dibuja lo
## suyo antes que sus hijos. Parecia funcionar y no funcionaba: z_index no es
## relativo al padre sino al canvas entero, asi que el -1 mandaba la imagen
## DETRAS del ColorRect de fondo de la pantalla y la arena salia en negro. El
## rotulo si se veia, que es lo que disimulaba el fallo.
##
## Con dos hijos en orden el resultado es el mismo sin tocar z_index: los hijos
## se dibujan en orden de arbol, asi que el segundo queda encima del primero.

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
var _overlay: Overlay


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tex = TextureRect.new()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)

	_overlay = Overlay.new()
	_overlay.vista = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func soltar() -> void:
	if _tex != null and is_instance_valid(_tex):
		_tex.texture = null


func tiene_imagen() -> bool:
	return _tex != null and is_instance_valid(_tex) and _tex.texture != null


func _process(_delta: float) -> void:
	# La textura no existe hasta que el pool crea sus ranuras, y eso ocurre
	# dentro del primer lote. Por eso se engancha aqui y no al construir.
	if pool != null and is_instance_valid(pool) and _tex != null and _tex.texture == null:
		_tex.texture = pool.showcase_texture()
	if _overlay != null:
		_overlay.queue_redraw()


## Rotulo y leyenda. Va en un hijo aparte para quedar POR ENCIMA de la imagen.
class Overlay extends Control:
	var vista: ArenaView

	func _draw() -> void:
		if vista == null:
			return
		if not vista.tiene_imagen():
			UI.caja_dibujada(self, Rect2(Vector2.ZERO, size), UI.PANEL, UI.BORDE)
			UI.texto_dibujado(self, Vector2(size.x * 0.5, size.y * 0.5),
					"la arena aparece aqui al empezar", UI.T_CUERPO, UI.APAGADO,
					HORIZONTAL_ALIGNMENT_CENTER)
			return

		var arena: Arena = null
		if vista.pool != null and is_instance_valid(vista.pool):
			arena = vista.pool.showcase_arena
		var rotulo := "esperando episodio..."
		if arena != null and is_instance_valid(arena) and arena.spec != null:
			rotulo = "%s    %s    tick %d" % [arena.spec.scenario_id,
					arena.spec.level_name, arena.tick]
		if vista.subtitulo != "":
			rotulo += "    " + vista.subtitulo

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
