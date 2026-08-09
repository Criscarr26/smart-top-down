extends Control
## Menu principal: muestra los controles y deja elegir nivel.
##
## Es la escena de arranque del juego. La interfaz se construye por codigo, igual
## que el HUD de Level: asi no hay un .tscn con decenas de nodos Control que
## haya que abrir en el editor para cambiar un texto.

const TITULO := "SMART TOP DOWN"
const SUBTITULO := "Enemigos con maquina de estados, pathfinding A* y un agente entrenado por algoritmo genetico"

## Cada fila: [tecla, accion]
const CONTROLES := [
	["W A S D", "Moverte en las cuatro direcciones"],
	["Raton", "Apuntar"],
	["Click izquierdo", "Ataque cuerpo a cuerpo"],
	["Click derecho", "Disparar un proyectil"],
	["Shift", "Defender: bloquea dano, pero te deja inmovil y gasta escudo"],
	["Q", "Usar una pocion del inventario"],
	["R", "Reiniciar el nivel"],
	["F1", "Ver los estados de la FSM de cada enemigo"],
	["Esc", "Volver a este menu"],
]

const ENEMIGOS := [
	[Color(0.87, 0.30, 0.26), "Tipo A", "Te persigue y golpea de cerca. Si le queda poca vida, busca una pocion."],
	[Color(0.36, 0.55, 0.92), "Tipo B", "No se mueve: dispara desde su puesto. Si te acercas, levanta la guardia."],
	[Color(0.93, 0.72, 0.24), "Tipo C", "Dispara de lejos y huye si te acercas. A quemarropa, contraataca."],
	[Color(0.55, 0.95, 0.60), "Agente", "El enemigo entrenado. Decide con una red neuronal, no con reglas."],
]

const NIVELES := [
	["level_01", "Nivel 1", "Arena abierta con pilares"],
	["level_02", "Nivel 2", "Habitaciones y pasillos"],
	["level_03", "Nivel 3", "Corredores estrechos y puas"],
]

const FONDO := Color(0.09, 0.08, 0.12)
const PANEL := Color(0.14, 0.13, 0.18)
const TEXTO := Color(0.86, 0.86, 0.90)
const TENUE := Color(0.55, 0.55, 0.62)
const ACENTO := Color(0.35, 0.85, 0.95)


func _ready() -> void:
	# El menu debe responder aunque el arbol este pausado (se entra aqui desde
	# la partida con Esc, que pausa).
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Audio.enabled = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var fondo := ColorRect.new()
	fondo.color = FONDO
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margen := MarginContainer.new()
	margen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for lado in ["left", "right"]:
		margen.add_theme_constant_override("margin_" + lado, 48)
	margen.add_theme_constant_override("margin_top", 34)
	margen.add_theme_constant_override("margin_bottom", 34)
	scroll.add_child(margen)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margen.add_child(col)

	col.add_child(_titulo(TITULO, 38, ACENTO))
	col.add_child(_parrafo(SUBTITULO, 13, TENUE))
	col.add_child(_separador())

	# La accion principal va primero: elegir nivel no deberia exigir scroll.
	col.add_child(_titulo("ELIGE NIVEL", 18, TEXTO))
	col.add_child(_botones_nivel())
	col.add_child(_separador())

	# Controles y enemigos en dos columnas: asi la referencia completa cabe en
	# pantalla en vez de quedar por debajo del pliegue.
	var dos := HBoxContainer.new()
	dos.add_theme_constant_override("separation", 40)
	dos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(dos)

	var izq := VBoxContainer.new()
	izq.add_theme_constant_override("separation", 8)
	izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	izq.size_flags_stretch_ratio = 1.05
	izq.add_child(_titulo("CONTROLES", 18, TEXTO))
	izq.add_child(_tabla_controles())
	dos.add_child(izq)

	var der := VBoxContainer.new()
	der.add_theme_constant_override("separation", 8)
	der.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	der.add_child(_titulo("A QUIEN TE ENFRENTAS", 18, TEXTO))
	der.add_child(_tabla_enemigos())
	dos.add_child(der)

	col.add_child(_separador())
	var salir := Button.new()
	salir.text = "Salir del juego"
	salir.custom_minimum_size = Vector2(0, 32)
	salir.pressed.connect(func() -> void: get_tree().quit())
	col.add_child(salir)


# --- Piezas de interfaz -------------------------------------------------------

func _titulo(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l


func _parrafo(texto: String, tam: int, color: Color) -> Label:
	var l := _titulo(texto, tam, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _separador() -> HSeparator:
	return HSeparator.new()


func _tabla_controles() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for fila in CONTROLES:
		var tecla := _titulo(str(fila[0]), 13, ACENTO)
		tecla.custom_minimum_size = Vector2(118, 0)
		grid.add_child(tecla)
		grid.add_child(_parrafo(str(fila[1]), 13, TEXTO))
	return grid


func _tabla_enemigos() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e in ENEMIGOS:
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 12)
		fila.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Cuadro del color real que usa ese enemigo en el juego, para poder
		# identificarlo de un vistazo en pantalla.
		var punto := ColorRect.new()
		punto.color = e[0]
		punto.custom_minimum_size = Vector2(16, 16)
		punto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fila.add_child(punto)

		var nombre := _titulo(str(e[1]), 14, TEXTO)
		nombre.custom_minimum_size = Vector2(80, 0)
		fila.add_child(nombre)
		fila.add_child(_parrafo(str(e[2]), 13, TENUE))
		col.add_child(fila)
	return col


func _botones_nivel() -> Control:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)
	fila.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in NIVELES:
		var b := Button.new()
		b.text = "%s\n%s" % [n[1], n[2]]
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_jugar.bind(str(n[0])))
		fila.add_child(b)
	return fila


func _jugar(nivel: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://game/%s.tscn" % nivel)
