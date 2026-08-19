extends Control
## Menu principal. Es la escena de arranque y el unico punto desde el que se
## llega a todo: jugar, entrenar y ver los records.
##
## La interfaz se construye por codigo, igual que el HUD y el laboratorio: asi
## no hay un .tscn con decenas de nodos Control que haya que abrir en el editor
## para cambiar un texto, y todo el estilo sale de UI.
##
## Se organiza en pestanas y no en una sola columna con scroll porque el criterio
## es que se sepa de un vistazo QUE se puede hacer aqui. Con scroll, la mitad de
## las opciones vivian por debajo del pliegue.

const TITULO := "SMART TOP DOWN"
const SUBTITULO := "Enemigos con maquina de estados, pathfinding A* y un agente entrenado por algoritmo genetico"

## Genoma entrenado por el jugador. Tiene prioridad sobre el que trae el
## proyecto; ver Level._read_genome().
const RUTA_GENOMA := "user://genoma_entrenado.json"

const PESTANAS := ["JUGAR", "ENTRENAR", "RECORDS", "CONTROLES"]

const CONTROLES := [
	["Flechas", "Moverte. Hay inercia: acelerar y frenar cuesta, y el posicionamiento importa"],
	["Raton", "Apuntar. El cuerpo va a un lado y el arma a otro"],
	["Click izq.", "Ataque cuerpo a cuerpo en arco frontal"],
	["Click der.", "Disparar un proyectil"],
	["Espacio", "Impulso: te saca de una inercia que no puedes cancelar. No ataca ni defiende"],
	["Shift", "Defender: bloquea la mayor parte del dano, pero inmoviliza y gasta escudo"],
	["Q", "Usar una pocion del inventario"],
	["R", "Reiniciar"],
	["F1", "Ver los estados de la FSM, radios y lineas de vision"],
	["Esc", "Pausa"],
]

const ENEMIGOS := [
	[UI.COLOR_A, "Tipo A", "Perseguidor. Pesado: se pasa de frenada, y ese sobrepaso es tu hueco."],
	[UI.COLOR_B, "Tipo B", "Torreta. No se mueve, dispara y levanta la guardia si te acercas."],
	[UI.COLOR_C, "Tipo C", "Kiter. Ligero, cambia de sentido en seco y contraataca a quemarropa."],
	[UI.COLOR_D, "Tipo D", "Sanador. Cura a los demas: mientras viva, tu dano se deshace."],
	[UI.COLOR_AGENTE, "Agente", "El entrenado. Decide con una red neuronal, no con reglas."],
]

const NIVELES := [
	["level_01", "Arena abierta", "Pilares y espacio para rodear. Buen sitio para aprender."],
	["level_02", "Habitaciones", "Pasillos y puertas: aqui el A* de los enemigos importa."],
	["level_03", "Corredores", "Estrecho y lleno de puas. Castiga moverse en linea recta."],
]

var _perfil := PlayerProfile.cargar()
var _contenido: VBoxContainer
var _pestanas: Array = []


func _ready() -> void:
	# El menu debe responder aunque el arbol este pausado (se llega aqui desde
	# la partida, que pausa).
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Audio.enabled = true
	# Devuelve el motor a velocidad normal por si se sale del laboratorio a lo
	# bruto con una aceleracion alta puesta.
	Engine.physics_ticks_per_second = GameConfig.TICKS_PER_SECOND
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_construir()


func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.color = UI.FONDO
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right"]:
		margen.add_theme_constant_override("margin_" + lado, 44)
	margen.add_theme_constant_override("margin_top", 26)
	margen.add_theme_constant_override("margin_bottom", 22)
	add_child(margen)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UI.ESPACIO)
	margen.add_child(col)

	col.add_child(UI.etiqueta(TITULO, 38, UI.ACENTO))
	col.add_child(UI.parrafo(SUBTITULO, UI.T_CUERPO, UI.TENUE))
	col.add_child(UI.separador())

	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 6)
	col.add_child(barra)
	for i in PESTANAS.size():
		var b := UI.boton(PESTANAS[i], _ir_a.bind(i), 34, i == 0)
		_pestanas.append(b)
		barra.add_child(b)
	var salir := UI.boton("Salir", func() -> void: get_tree().quit(), 34)
	salir.size_flags_horizontal = Control.SIZE_SHRINK_END
	salir.custom_minimum_size = Vector2(90, 34)
	barra.add_child(salir)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_contenido = VBoxContainer.new()
	_contenido.add_theme_constant_override("separation", UI.ESPACIO)
	_contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_contenido)

	_ir_a(0)


func _ir_a(indice: int) -> void:
	for i in _pestanas.size():
		var b := _pestanas[i] as Button
		# La pestana activa se pinta como boton principal; el resto, secundarios.
		b.add_theme_color_override("font_color", UI.FONDO if i == indice else UI.TEXTO)
		b.add_theme_stylebox_override("normal", UI._caja(
				UI.ACENTO if i == indice else UI.PANEL_ALTO,
				UI.ACENTO if i == indice else UI.BORDE))
	for c in _contenido.get_children():
		_contenido.remove_child(c)
		c.queue_free()
	match indice:
		0: _pestana_jugar()
		1: _pestana_entrenar()
		2: _pestana_records()
		3: _pestana_controles()


# =============================================================================
# Pestanas
# =============================================================================

func _anadir_panel(col: VBoxContainer) -> void:
	_contenido.add_child(col.get_parent())


func _pestana_jugar() -> void:
	var col := UI.panel("ELIGE NIVEL")
	col.add_child(UI.parrafo("Modo oleadas: los enemigos llegan en tandas que crecen y "
			+ "cada una introduce un tipo nuevo. Encadena bajas antes de que se agote "
			+ "la ventana para multiplicar los puntos."))
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 10)
	col.add_child(fila)
	for n in NIVELES:
		var tarjeta := VBoxContainer.new()
		tarjeta.add_theme_constant_override("separation", 2)
		tarjeta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tarjeta.add_child(UI.boton(str(n[1]), _jugar.bind(str(n[0])), 46, true))
		tarjeta.add_child(UI.parrafo(str(n[2]), UI.T_MICRO, UI.TENUE))
		var r := _perfil.record_de(str(n[0]))
		if int(r.get("puntos", 0)) > 0:
			tarjeta.add_child(UI.etiqueta("record %d  ·  oleada %d"
					% [int(r["puntos"]), int(r["oleada"])], UI.T_MICRO, UI.EXITO))
		fila.add_child(tarjeta)
	_anadir_panel(col)

	var der := UI.panel("A QUIEN TE ENFRENTAS")
	for e in ENEMIGOS:
		var f := HBoxContainer.new()
		f.add_theme_constant_override("separation", 10)
		var punto := ColorRect.new()
		punto.color = e[0]
		punto.custom_minimum_size = Vector2(14, 14)
		punto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		f.add_child(punto)
		var nombre := UI.etiqueta(str(e[1]), UI.T_CUERPO)
		nombre.custom_minimum_size = Vector2(74, 0)
		f.add_child(nombre)
		f.add_child(UI.parrafo(str(e[2]), UI.T_PEQUENO, UI.TENUE))
		der.add_child(f)
	_anadir_panel(der)


func _pestana_entrenar() -> void:
	var col := UI.panel("LABORATORIO DE ENTRENAMIENTO")
	col.add_child(UI.parrafo("Edita la funcion de fitness y los parametros del "
			+ "algoritmo genetico, corre el mismo entrenamiento que usa el benchmark "
			+ "y mira lo que percibe y decide el agente mientras aprende. Al terminar, "
			+ "evalualo en los 10 escenarios del nivel de validacion."))
	var hay := FileAccess.file_exists(RUTA_GENOMA)
	col.add_child(UI.etiqueta(
			"Ahora mismo los niveles usan TU agente entrenado." if hay
			else "Todavia no has entrenado ninguno: los niveles usan el que trae el proyecto.",
			UI.T_PEQUENO, UI.EXITO if hay else UI.TENUE))
	col.add_child(UI.boton("Abrir el laboratorio", func() -> void:
			get_tree().change_scene_to_file("res://game/training_lab.tscn"), 46, true))
	_anadir_panel(col)

	var info := UI.panel("QUE VAS A VER")
	for linea in [
		"Los 7 sensores del agente, con su valor normalizado, en tiempo real.",
		"Las 6 salidas de la red y cual gana: la decision, no solo el resultado.",
		"La ruta A* que esta siguiendo y por donde ha pasado.",
		"Fitness y tasa de victoria por generacion, con marca en cada cambio de etapa.",
		"Episodios, pasos simulados, tiempo y rendimiento reales de la corrida.",
	]:
		info.add_child(UI.parrafo("·  " + linea, UI.T_PEQUENO, UI.TENUE))
	_anadir_panel(info)


func _pestana_records() -> void:
	var col := UI.panel("RECORDS POR NIVEL")
	var rejilla := GridContainer.new()
	rejilla.columns = 6
	rejilla.add_theme_constant_override("h_separation", 24)
	rejilla.add_theme_constant_override("v_separation", 5)
	for cab in ["Nivel", "Puntos", "Oleada", "Bajas", "Cadena", "Tiempo"]:
		rejilla.add_child(UI.etiqueta(cab, UI.T_PEQUENO, UI.ACENTO))
	for n in NIVELES:
		var r := _perfil.record_de(str(n[0]))
		var hay := int(r.get("puntos", 0)) > 0
		rejilla.add_child(UI.etiqueta(str(n[1]), UI.T_PEQUENO))
		rejilla.add_child(UI.etiqueta(str(int(r.get("puntos", 0))), UI.T_PEQUENO,
				UI.EXITO if hay else UI.APAGADO))
		rejilla.add_child(UI.etiqueta(str(int(r.get("oleada", 0))), UI.T_PEQUENO))
		rejilla.add_child(UI.etiqueta(str(int(r.get("bajas", 0))), UI.T_PEQUENO))
		rejilla.add_child(UI.etiqueta("x%d" % int(r.get("combo", 0)), UI.T_PEQUENO))
		rejilla.add_child(UI.etiqueta(UI.reloj(float(r.get("segundos", 0.0))), UI.T_PEQUENO))
	col.add_child(rejilla)
	_anadir_panel(col)

	var tot := UI.panel("EN TOTAL")
	var f := HBoxContainer.new()
	f.add_theme_constant_override("separation", 44)
	for par in [["Partidas", str(_perfil.partidas)],
			["Bajas", str(_perfil.bajas_totales)],
			["Tiempo jugado", UI.reloj(_perfil.segundos_jugados)]]:
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 0)
		c.add_child(UI.etiqueta(str(par[0]), UI.T_MICRO, UI.TENUE))
		c.add_child(UI.etiqueta(str(par[1]), 22, UI.TEXTO))
		f.add_child(c)
	tot.add_child(f)
	if _perfil.partidas == 0:
		tot.add_child(UI.parrafo("Todavia no hay partidas registradas.",
				UI.T_PEQUENO, UI.APAGADO))
	_anadir_panel(tot)


func _pestana_controles() -> void:
	var col := UI.panel("CONTROLES")
	var rejilla := GridContainer.new()
	rejilla.columns = 2
	rejilla.add_theme_constant_override("h_separation", 24)
	rejilla.add_theme_constant_override("v_separation", 6)
	for fila in CONTROLES:
		var tecla := UI.etiqueta(str(fila[0]), UI.T_CUERPO, UI.ACENTO)
		tecla.custom_minimum_size = Vector2(112, 0)
		rejilla.add_child(tecla)
		rejilla.add_child(UI.parrafo(str(fila[1]), UI.T_PEQUENO, UI.TEXTO))
	col.add_child(rejilla)
	_anadir_panel(col)


func _jugar(nivel: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://game/%s.tscn" % nivel)
