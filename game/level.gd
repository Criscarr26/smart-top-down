extends Node2D
## Partida jugable. Monta un Arena en modo interactivo con el jugador humano
## contra los tres tipos de enemigo FSM y el agente entrenado.
##
## Usa EXACTAMENTE el mismo Arena que el benchmark; la unica diferencia es
## `interactive = true` (que enciende el dibujado) y que el bando "jugador" lo
## ocupa una persona en vez del bot.
##
## Todo lo que hay en este archivo -- HUD, minimapa, sacudida de camara, numeros
## de dano, pausa y pantalla de resultados -- es presentacion construida ENCIMA
## del Arena, no dentro. El barrido no instancia este nodo, asi que nada de esto
## puede alterar una sola fila del Excel.

## Cambiar en el inspector para jugar los niveles 2 y 3, o el de validacion.
@export_enum("level_01", "level_02", "level_03", "validation")
var level_name: String = "level_01"

## Modo por oleadas: los enemigos llegan en tandas que crecen, con puntuacion,
## cadena de bajas y record. Es el modo por defecto. En false se juega el mapa
## como un escenario cerrado, que es como estaba antes y sigue sirviendo para
## probar una composicion concreta.
@export var modo_oleadas: bool = true

@export var enemies_type_a: int = 2
@export var enemies_type_b: int = 1
@export var enemies_type_c: int = 1
@export var enemies_type_d: int = 0
## Agentes entrenados que acompanan a los enemigos. Cargan el genoma de
## `res://results/genomas/` si existe; si no, salen con pesos aleatorios.
@export var trained_agents: int = 1

## El agente que entrena el jugador desde el menu manda sobre el que trae el
## proyecto: si no, entrenar uno mejor no cambiaria nada de lo que se juega.
const GENOME_USER := "user://genoma_entrenado.json"
const GENOME_BUNDLED := "res://results/genoma_base_base.json"

## Alias locales de la paleta de UI. No son colores nuevos: existen solo para
## que el codigo de abajo se lea, y cambiar la paleta sigue siendo tocar un
## unico archivo.
const TEXTO := UI.TEXTO
const TENUE := UI.TENUE
const ACENTO := UI.ACENTO
const VERDE := UI.EXITO
const ROJO := UI.PELIGRO

var arena: Arena
## Configuracion con la que se entreno el genoma cargado. Importa: la topologia
## decide cuantos pesos tiene la red, y el thresholding decide como el agente
## convierte la salida en accion. Jugar con otra distinta seria jugar contra un
## agente que no es el que se entreno.
var _agent_config: GAConfig = ExperimentMatrix.baseline()

var puntuacion := ScoreSystem.new()
var oleadas: WaveDirector
var perfil := PlayerProfile.cargar()
## Anuncios en curso: [{texto, color, ticks}]. Los dibuja el HUD.
var avisos: Array = []

var _efectos: Effects
var _camera: Camera2D
var _hud: Hud
var _pausa: Control
var _resultado: Control
var _fade: ColorRect
## Intensidad de la sacudida de camara, en pixeles. Decae sola.
var _sacudida: float = 0.0
var _terminado: bool = false


func _ready() -> void:
	# La pausa y el fundido tienen que responder con el arbol pausado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Audio.enabled = true
	_build_arena()
	_build_camera()
	_build_efectos()
	_build_hud()
	_conectar_actores()
	_build_progresion()
	if not AssetLibrary.has_art():
		print("[Level] No hay arte generado. Corre:")
		print("        python tools/generate_sprites.py")
		print("        python tools/generate_sfx.py")


## Rompe los ciclos de referencia de la arena al salir del nivel.
##
## GDScript no recoge ciclos, y un Enemy apunta a su StateMachine, que apunta a
## cada EnemyState, que apunta de vuelta al Enemy. En el barrido esto hacia
## crecer la memoria sin techo; aqui el efecto es mas lento pero identico:
## reiniciar el nivel con R veinte veces deja veinte arenas enteras en memoria.
func _exit_tree() -> void:
	if arena != null and is_instance_valid(arena):
		arena.dispose()


func _build_arena() -> void:
	var spec := ArenaSpec.create("jugable", "Partida jugable")
	spec.level_name = level_name
	spec.opponent_kind = ArenaSpec.Opponent.HUMAN
	spec.agent_count = trained_agents
	# El genoma primero: al leerlo se resuelve tambien con que configuracion se
	# entreno, y esa es la que tiene que llevar el spec.
	spec.agent_genome = _load_genome()
	spec.ga_config = _agent_config
	# En la partida jugable TODOS los enemigos van contra el jugador: el agente
	# entrenado es un enemigo mas, no el rival de los enemigos FSM.
	spec.fsm_opposes_agent = false
	if modo_oleadas:
		# En oleadas la arena arranca vacia: los enemigos los trae el director.
		# Y no puede terminar por "bando enemigo eliminado", porque entre oleada
		# y oleada ese bando esta legitimamente vacio.
		spec.finish_on_side_wipe = false
	else:
		if enemies_type_a > 0:
			spec.with_enemies("A", enemies_type_a)
		if enemies_type_b > 0:
			spec.with_enemies("B", enemies_type_b)
		if enemies_type_c > 0:
			spec.with_enemies("C", enemies_type_c)
		if enemies_type_d > 0:
			spec.with_enemies("D", enemies_type_d)
	spec.seed = int(Time.get_unix_time_from_system())
	spec.max_ticks = 999_999   # sin limite de tiempo cuando juega una persona

	arena = Arena.new()
	add_child(arena)
	arena.episode_finished.connect(_on_episode_finished)
	arena.setup(spec, true)


## Engancha cada actor a los efectos. Se llama despues de setup() y otra vez tras
## cada oleada, porque los enemigos nuevos nacen a mitad de partida. Es
## idempotente: reconectar una senal ya conectada seria un error en Godot.
func _conectar_actores() -> void:
	for a in arena.actors:
		var actor := a as Actor
		if not actor.damaged.is_connected(_on_damaged):
			actor.damaged.connect(_on_damaged)
		if not actor.died.is_connected(_on_died):
			actor.died.connect(_on_died)


func _on_damaged(actor: Actor, applied: float, blocked: float) -> void:
	if _efectos == null:
		return
	var es_jugador := actor is Player
	if blocked > 1.0:
		_efectos.numero(actor.global_position, "%d" % roundi(blocked), ACENTO)
		_efectos.impacto(actor.global_position, 6, Color(0.4, 0.7, 1.0))
	if applied >= 1.0:
		_efectos.numero(actor.global_position, "%d" % roundi(applied),
				ROJO if es_jugador else Color(1.0, 0.85, 0.35))
		_efectos.impacto(actor.global_position, 8,
				Color(0.95, 0.35, 0.35) if es_jugador else Color(0.95, 0.75, 0.35))
	# Solo sacude cuando le pegan al jugador. Sacudir con cada golpe del mapa
	# convierte una refriega en un terremoto ilegible.
	if es_jugador and applied >= 1.0:
		_sacudida = minf(11.0, _sacudida + 2.0 + applied * 0.18)
		puntuacion.registrar_dano(applied)


func _on_died(actor: Actor, killer: Actor) -> void:
	if _efectos != null:
		_efectos.muerte(actor.global_position, actor.body_color)
	_sacudida = minf(13.0, _sacudida + (9.0 if actor is Player else 4.0))

	# Solo puntuan las bajas del jugador: las de las puas o el fuego amigo no
	# son merito suyo, y contarlas convertiria "esperar" en una estrategia.
	if killer is Player and actor.team == Actor.Team.ENEMY:
		var tipo := "AGENT" if actor is AgentEnemy else ""
		if actor is Enemy:
			tipo = (actor as Enemy).profile.type_id
		var ganados := puntuacion.registrar_baja(tipo)
		if _efectos != null:
			_efectos.numero(actor.global_position + Vector2(0, -14),
					"+%d" % ganados, UI.AVISO)


# =============================================================================
# Progresion: puntuacion, oleadas y record
# =============================================================================

func _build_progresion() -> void:
	puntuacion.evento.connect(_anunciar)
	if not modo_oleadas:
		return
	oleadas = WaveDirector.new(arena)
	oleadas.oleada_empezo.connect(func(numero: int, comp: Dictionary) -> void:
			# Los enemigos de la oleada acaban de nacer: hay que engancharlos a
			# los efectos y a la puntuacion como a los demas.
			_conectar_actores()
			_anunciar("OLEADA %d    %s" % [numero, WaveDirector.describir(comp)], UI.ACENTO)
			Audio.play("alert", Vector2.ZERO))
	oleadas.oleada_limpiada.connect(_al_limpiar_oleada)
	oleadas.empezar()


func _al_limpiar_oleada(numero: int) -> void:
	var p := _jugador()
	var precision := 0.0
	if p != null and p.melee_swings > 0:
		precision = float(p.melee_hits) / float(p.melee_swings)
	puntuacion.cerrar_oleada(precision)
	_anunciar("OLEADA %d SUPERADA" % numero, UI.EXITO)
	# Un respiro real: recupera algo de escudo entre oleadas. Sin esto, una mala
	# racha en la oleada 3 condena la partida entera sin que se pueda remontar.
	if p != null and p.alive:
		p.shield = minf(p.max_shield, p.shield + 35.0)


## Cola de anuncios del HUD. Se muestran de uno en uno para que no se pisen.
func _anunciar(texto: String, color: Color) -> void:
	avisos.append({"texto": texto, "color": color, "ticks": 150})
	while avisos.size() > 4:
		avisos.pop_front()


func _build_efectos() -> void:
	_efectos = Effects.new()
	add_child(_efectos)


## Carga el agente a usar: primero el que haya entrenado el jugador desde el
## menu, y si no hay, el que dejo el barrido del benchmark.
func _load_genome() -> Genome:
	var propio := _read_genome(GENOME_USER)
	if propio != null:
		return propio
	var incluido := _read_genome(GENOME_BUNDLED)
	if incluido == null:
		print("[Level] Sin genoma entrenado. El agente saldra con pesos aleatorios.")
		print("        Entrenalo desde el menu principal, o corre el benchmark.")
	return incluido


## Acepta las dos formas de archivo: el JSON suelto que escribe el benchmark
## ({params, fitness, stats}) y el envoltorio de la pantalla de entrenamiento,
## que ademas guarda con que configuracion se entreno.
func _read_genome(path: String) -> Genome:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("[Level] Genoma ilegible en %s" % path)
		return null

	var d: Dictionary = parsed
	var crudo: Dictionary = d
	# La configuracion se arma en una variable local y solo se adopta si el
	# genoma resulta valido: si se escribiera en _agent_config aqui, un archivo
	# incompatible dejaria su topologia puesta y romperia tambien el respaldo.
	var config := ExperimentMatrix.baseline()
	if d.get("genoma") is Dictionary:
		crudo = d["genoma"]
		if d.get("config_ga") is Dictionary:
			var bruto: Dictionary = (d["config_ga"] as Dictionary).duplicate()
			if d.get("capas_ocultas") is Array:
				bruto["capas_ocultas"] = d["capas_ocultas"]
			config = GAConfig.from_dict(bruto)

	var genome := Genome.from_dict(crudo)
	# Un genoma de otra topologia tiene otro numero de pesos, y Arena lo
	# descartaria en silencio poniendo pesos aleatorios: el agente pareceria
	# entrenado sin serlo. Mejor decirlo.
	var esperado := NeuralNetwork.new(config.topology()).param_count()
	if genome.size() != esperado:
		push_warning("[Level] %s tiene %d pesos y la red espera %d; se ignora."
				% [path, genome.size(), esperado])
		print("[Level] Genoma incompatible en %s (%d pesos, se esperaban %d)."
				% [path, genome.size(), esperado])
		return null

	_agent_config = config
	print("[Level] Agente cargado desde %s (fitness %.2f, topologia %s)"
			% [path, genome.fitness,
			"-".join(config.topology().map(func(v: int) -> String: return str(v)))])
	return genome


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


# =============================================================================
# Interfaz
# =============================================================================

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	_hud = Hud.new()
	_hud.nivel = self
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)

	_pausa = _panel_pausa()
	layer.add_child(_pausa)

	_resultado = Control.new()
	_resultado.set_anchors_preset(Control.PRESET_FULL_RECT)
	_resultado.visible = false
	layer.add_child(_resultado)

	# El fundido va el ultimo para quedar por encima de todo.
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.45)


func _fondo_oscuro(padre: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.07, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	padre.add_child(bg)


func _panel_pausa() -> Control:
	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.visible = false
	raiz.process_mode = Node.PROCESS_MODE_ALWAYS
	_fondo_oscuro(raiz)

	var caja := VBoxContainer.new()
	caja.set_anchors_preset(Control.PRESET_CENTER)
	caja.grow_horizontal = Control.GROW_DIRECTION_BOTH
	caja.grow_vertical = Control.GROW_DIRECTION_BOTH
	caja.custom_minimum_size = Vector2(320, 0)
	caja.add_theme_constant_override("separation", 10)
	raiz.add_child(caja)

	caja.add_child(_etiqueta("PAUSA", 30, ACENTO, HORIZONTAL_ALIGNMENT_CENTER))
	caja.add_child(_etiqueta("Esc para seguir", 12, TENUE, HORIZONTAL_ALIGNMENT_CENTER))
	caja.add_child(HSeparator.new())
	caja.add_child(_boton("Continuar", func() -> void: _alternar_pausa()))
	caja.add_child(_boton("Reiniciar nivel", func() -> void: _reiniciar()))
	caja.add_child(_boton("Volver al menu", func() -> void: _ir_al_menu()))
	return raiz


func _etiqueta(t: String, tam: int, color: Color,
		alineacion: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = alineacion
	return l


func _boton(t: String, accion: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 36)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	b.pressed.connect(accion)
	return b


## Pantalla de fin de partida con el desglose de lo que hizo el jugador. Los
## numeros salen de los mismos contadores de Actor que alimentan el fitness del
## agente, asi que quien juega ve exactamente las magnitudes con las que se
## entrena a la IA.
func _mostrar_resultado(gano: bool) -> void:
	for c in _resultado.get_children():
		c.queue_free()
	_fondo_oscuro(_resultado)

	var caja := VBoxContainer.new()
	caja.set_anchors_preset(Control.PRESET_CENTER)
	caja.grow_horizontal = Control.GROW_DIRECTION_BOTH
	caja.grow_vertical = Control.GROW_DIRECTION_BOTH
	caja.custom_minimum_size = Vector2(400, 0)
	caja.add_theme_constant_override("separation", 8)
	_resultado.add_child(caja)

	var p := _jugador()
	var segundos := float(arena.tick) / float(GameConfig.TICKS_PER_SECOND)
	var oleada_alcanzada: int = oleadas.oleada if oleadas != null else 0
	var record_previo := perfil.record_de(level_name)
	var batido := perfil.registrar_partida(level_name, puntuacion.puntos,
			oleada_alcanzada, puntuacion.bajas, puntuacion.combo_maximo, segundos)

	var titulo := "NIVEL SUPERADO" if gano else "HAS MUERTO"
	if modo_oleadas:
		titulo = "CAISTE EN LA OLEADA %d" % oleada_alcanzada if not gano else "SUPERADO"
	caja.add_child(_etiqueta(titulo, 34, VERDE if gano else ROJO,
			HORIZONTAL_ALIGNMENT_CENTER))
	if modo_oleadas:
		caja.add_child(_etiqueta("%d PUNTOS" % puntuacion.puntos, 26,
				ACENTO, HORIZONTAL_ALIGNMENT_CENTER))
		if batido:
			caja.add_child(_etiqueta("NUEVO RECORD  (antes %d)"
					% int(record_previo.get("puntos", 0)), 14, VERDE,
					HORIZONTAL_ALIGNMENT_CENTER))
		else:
			caja.add_child(_etiqueta("record del nivel: %d"
					% int(record_previo.get("puntos", 0)), 12, TENUE,
					HORIZONTAL_ALIGNMENT_CENTER))
	caja.add_child(HSeparator.new())
	var rejilla := GridContainer.new()
	rejilla.columns = 2
	rejilla.add_theme_constant_override("h_separation", 24)
	rejilla.add_theme_constant_override("v_separation", 4)
	caja.add_child(rejilla)

	var punteria := 0.0
	if p != null and p.melee_swings > 0:
		punteria = 100.0 * float(p.melee_hits) / float(p.melee_swings)
	for fila in [
		["Tiempo", "%.1f s" % segundos],
		["Oleadas superadas", "%d" % maxi(0, oleada_alcanzada - 1)],
		["Cadena maxima", "x%d" % puntuacion.combo_maximo],
		["Enemigos abatidos", "%d" % (p.kills if p != null else 0)],
		["Dano infligido", "%.0f" % (p.damage_dealt if p != null else 0.0)],
		["Dano recibido", "%.0f" % (p.damage_taken if p != null else 0.0)],
		["Dano bloqueado", "%.0f" % (p.damage_blocked if p != null else 0.0)],
		["Golpes acertados", "%d de %d (%.0f%%)" % [
			p.melee_hits if p != null else 0,
			p.melee_swings if p != null else 0, punteria]],
		["Disparos", "%d" % (p.shots_fired if p != null else 0)],
		["Pociones usadas", "%d" % (p.potions_used if p != null else 0)],
	]:
		rejilla.add_child(_etiqueta(str(fila[0]), 13, TENUE))
		rejilla.add_child(_etiqueta(str(fila[1]), 13, TEXTO))

	caja.add_child(HSeparator.new())
	caja.add_child(_boton("Reiniciar (R)", func() -> void: _reiniciar()))
	caja.add_child(_boton("Volver al menu (Esc)", func() -> void: _ir_al_menu()))
	_resultado.visible = true


# =============================================================================
# Bucle de presentacion
# =============================================================================

## Un tick de simulacion. Corre a la misma frecuencia que Arena.step(), asi que
## la ventana del combo y la cuenta atras entre oleadas se miden en ticks igual
## que todo lo demas, y no dependen de los fotogramas por segundo.
func _physics_process(_delta: float) -> void:
	if _terminado or get_tree().paused or arena == null or not arena.running:
		return
	puntuacion.tick()
	for i in range(avisos.size() - 1, -1, -1):
		var aviso: Dictionary = avisos[i]
		aviso["ticks"] = int(aviso["ticks"]) - 1
		if int(aviso["ticks"]) <= 0:
			avisos.remove_at(i)
	if oleadas != null:
		var p := _jugador()
		oleadas.tick(p.global_position if p != null else Vector2.ZERO)


func _process(delta: float) -> void:
	_procesar_entrada()

	var player := _jugador()
	if _camera != null:
		if player != null:
			_camera.global_position = player.global_position
		# Sacudida: desplazamiento aleatorio que decae. Se aplica al offset y no
		# a la posicion para no pelearse con el suavizado del seguimiento.
		if _sacudida > 0.01:
			_sacudida = maxf(0.0, _sacudida - delta * 26.0)
			_camera.offset = Vector2(randf_range(-_sacudida, _sacudida),
					randf_range(-_sacudida, _sacudida))
		elif _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO

	if _hud != null:
		_hud.queue_redraw()


func _procesar_entrada() -> void:
	if Input.is_action_just_pressed("pause_game"):
		if _terminado:
			_ir_al_menu()
		else:
			_alternar_pausa()
		return
	if Input.is_action_just_pressed("restart_level"):
		_reiniciar()
		return
	if Input.is_action_just_pressed("toggle_debug"):
		Enemy.debug_draw = not Enemy.debug_draw


func _alternar_pausa() -> void:
	if _terminado:
		return
	var pausado := not get_tree().paused
	get_tree().paused = pausado
	_pausa.visible = pausado


func _reiniciar() -> void:
	get_tree().paused = false
	_transicion(func() -> void: get_tree().reload_current_scene())


func _ir_al_menu() -> void:
	get_tree().paused = false
	_transicion(func() -> void:
			get_tree().change_scene_to_file("res://game/main_menu.tscn"))


## Funde a negro y despues cambia de escena. El corte seco entre el nivel y el
## menu es lo que mas barato hace parecer un juego.
func _transicion(accion: Callable) -> void:
	if _fade == null:
		accion.call()
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.28)
	tw.tween_callback(accion)


func _jugador() -> Player:
	if arena == null:
		return null
	for a in arena.actors:
		if a is Player:
			return a as Player
	return null


func enemigos_vivos() -> int:
	if arena == null:
		return 0
	var n := 0
	for a in arena.actors:
		var actor := a as Actor
		if actor.alive and actor.team == Actor.Team.ENEMY:
			n += 1
	return n


func enemigos_totales() -> int:
	if arena == null:
		return 0
	var n := 0
	for a in arena.actors:
		if (a as Actor).team == Actor.Team.ENEMY:
			n += 1
	return n


func _on_episode_finished(result: Dictionary) -> void:
	_terminado = true
	var gano := str(result.get("motivo_fin", "")) == "bando_enemigo_eliminado"
	# Un respiro antes del panel: si aparece en el mismo fotograma en que muere
	# el ultimo enemigo, tapa la explosion que acaba de provocar el jugador.
	var t := get_tree().create_timer(0.9, true, false, true)
	t.timeout.connect(func() -> void: _mostrar_resultado(gano))


# =============================================================================
# HUD
# =============================================================================

## Barras, contadores y minimapa, dibujados en un solo _draw.
##
## Un HUD hecho de nodos Control (una barra = un ColorRect de fondo + otro de
## relleno + un Label) son ocho nodos que hay que mantener sincronizados cada
## fotograma. Dibujarlo es menos codigo y no puede desincronizarse.
class Hud extends Control:
	const TEXTO := UI.TEXTO
	const TENUE := UI.TENUE
	const FONDO := Color(0.06, 0.06, 0.09, 0.72)
	const BORDE := Color(0.30, 0.30, 0.38, 0.9)

	const MARGEN := 14.0
	## Compacto a proposito. La primera version media 256x96 y se comia la
	## esquina: en un top-down lo que hay que mirar es el campo, no el HUD. Las
	## barras dan la lectura periferica (color y longitud) y el numero exacto
	## queda de apoyo, no al reves.
	const ANCHO_BARRA := 132.0
	const MINIMAPA := Vector2(150.0, 100.0)

	var nivel                     # el Level dueno del HUD

	func _draw() -> void:
		if nivel == null or nivel.arena == null:
			return
		var p: Player = nivel._jugador()
		_panel_jugador(p)
		_panel_enemigos()
		_panel_puntuacion()
		_avisos()
		_minimapa()
		_ayuda()

	## Puntuacion arriba en el centro, con la cadena debajo. Va centrado y grande
	## porque es la unica cifra que el jugador mira mientras pelea.
	func _panel_puntuacion() -> void:
		if not nivel.modo_oleadas:
			return
		var s: ScoreSystem = nivel.puntuacion
		var cx := size.x * 0.5
		UI.texto_dibujado(self, Vector2(cx, MARGEN + 26.0), str(s.puntos), 30,
				TEXTO, HORIZONTAL_ALIGNMENT_CENTER)
		var record := int(nivel.perfil.record_de(nivel.level_name).get("puntos", 0))
		if record > 0:
			UI.texto_dibujado(self, Vector2(cx, MARGEN + 40.0), "record %d" % record,
					UI.T_MICRO, UI.APAGADO, HORIZONTAL_ALIGNMENT_CENTER)

		if s.combo >= 2:
			# La barra se vacia con la ventana del combo: es un reloj visible que
			# empuja a ir a por el siguiente en vez de esperar a que vengan.
			var w := 150.0
			var x := cx - w * 0.5
			var y := MARGEN + 50.0
			UI.texto_dibujado(self, Vector2(cx, y - 2.0), "CADENA x%d   (x%.2f)"
					% [s.combo, s.multiplicador()], UI.T_PEQUENO, UI.AVISO,
					HORIZONTAL_ALIGNMENT_CENTER)
			draw_rect(Rect2(Vector2(x, y + 3.0), Vector2(w, 4.0)), Color(0.18, 0.18, 0.22))
			draw_rect(Rect2(Vector2(x, y + 3.0), Vector2(w * s.fraccion_combo(), 4.0)),
					UI.AVISO)

	## Anuncios apilados bajo la puntuacion. Se desvanecen al agotarse sus ticks.
	func _avisos() -> void:
		var y := size.y * 0.30
		for a in nivel.avisos:
			var t: float = clampf(float(a["ticks"]) / 150.0, 0.0, 1.0)
			var c: Color = a["color"]
			c.a = clampf(t * 2.2, 0.0, 1.0)
			UI.texto_dibujado(self, Vector2(size.x * 0.5, y), str(a["texto"]),
					UI.T_SECCION, c, HORIZONTAL_ALIGNMENT_CENTER)
			y += 20.0

	func _caja(rect: Rect2) -> void:
		draw_rect(rect, FONDO)
		draw_rect(rect, BORDE, false, 1.0)

	## Barra desnuda: sin etiqueta ni numero dentro. El texto va fuera y solo
	## donde aporta, que es lo que permite que el panel mida un tercio.
	func _barra(pos: Vector2, ancho: float, alto: float, fraccion: float,
			color: Color) -> void:
		draw_rect(Rect2(pos, Vector2(ancho, alto)), Color(0.16, 0.16, 0.20))
		draw_rect(Rect2(pos, Vector2(ancho * clampf(fraccion, 0.0, 1.0), alto)), color)

	func _panel_jugador(p: Player) -> void:
		if p == null:
			return
		var alto := 42.0
		_caja(Rect2(Vector2(MARGEN, MARGEN), Vector2(ANCHO_BARRA + 16.0, alto)))
		var x := MARGEN + 8.0
		var y := MARGEN + 8.0
		var fuente := ThemeDB.fallback_font

		# Rojo cuando la salud baja: la lectura periferica importa mas que el
		# numero exacto cuando hay seis enemigos encima.
		var color_vida := Color(0.30, 0.85, 0.40)
		if p.health_fraction() < 0.3:
			color_vida = Color(0.95, 0.30, 0.30)
		elif p.health_fraction() < 0.6:
			color_vida = Color(0.95, 0.75, 0.30)
		_barra(Vector2(x, y), ANCHO_BARRA, 9.0, p.health_fraction(), color_vida)
		draw_string(fuente, Vector2(x + ANCHO_BARRA - 3, y + 8), "%d" % roundi(p.health),
				HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color(1, 1, 1, 0.9))
		y += 12.0

		var color_escudo := Color(0.35, 0.65, 1.0)
		if p.is_shield_broken():
			color_escudo = Color(0.65, 0.30, 0.30)
		_barra(Vector2(x, y), ANCHO_BARRA, 6.0, p.shield_fraction(), color_escudo)
		if p.is_shield_broken():
			draw_string(fuente, Vector2(x + ANCHO_BARRA - 3, y + 6), "ROTO",
					HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, Color(1, 0.75, 0.75, 0.95))
		y += 9.0

		# El impulso solo se dibuja mientras recarga: cuando esta listo no hay
		# nada que informar, y una barra llena permanente es ruido.
		var listo := p.dash_ready_fraction() >= 1.0
		if not listo:
			_barra(Vector2(x, y), ANCHO_BARRA, 4.0, p.dash_ready_fraction(),
					Color(0.30, 0.45, 0.55))
		else:
			_barra(Vector2(x, y), ANCHO_BARRA, 4.0, 1.0, Color(0.55, 0.95, 1.0))
		y += 8.0

		# Pociones como puntos. Solo se dibujan los que tiene mas uno vacio de
		# referencia; cinco huecos permanentes ocupaban sitio para no decir nada.
		var puntos: int = maxi(1, mini(5, p.potions + 1))
		for i in puntos:
			var c := Color(0.45, 0.9, 0.55) if i < p.potions else Color(0.24, 0.24, 0.29)
			draw_rect(Rect2(Vector2(x + i * 9.0, y), Vector2(6, 6)), c)

	func _panel_enemigos() -> void:
		var fuente := ThemeDB.fallback_font
		var ancho := 168.0
		var rect := Rect2(Vector2(size.x - MARGEN - ancho, MARGEN), Vector2(ancho, 52.0))
		_caja(rect)
		var vivos: int = nivel.enemigos_vivos()
		var total: int = nivel.enemigos_totales()
		var titulo := "ENEMIGOS"
		if nivel.oleadas != null:
			titulo = "OLEADA %d" % nivel.oleadas.oleada
			total = nivel.oleadas.total_de_la_oleada()
			vivos = nivel.oleadas.vivos()
		draw_string(fuente, rect.position + Vector2(10, 20), titulo,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TENUE)
		draw_string(fuente, rect.position + Vector2(ancho - 10, 22),
				"%d / %d" % [vivos, total], HORIZONTAL_ALIGNMENT_RIGHT, -1, 17,
				TEXTO if vivos > 0 else Color(0.45, 0.92, 0.55))
		var segundos := float(nivel.arena.tick) / float(GameConfig.TICKS_PER_SECOND)
		draw_string(fuente, rect.position + Vector2(10, 42), "TIEMPO",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TENUE)
		draw_string(fuente, rect.position + Vector2(ancho - 10, 42),
				"%d:%02d" % [int(segundos) / 60, int(segundos) % 60],
				HORIZONTAL_ALIGNMENT_RIGHT, -1, 13, TEXTO)

	## Mapa del nivel a escala con un punto por actor. En un top-down con
	## enemigos que disparan desde fuera de camara, saber de donde viene el fuego
	## es la diferencia entre morir y cubrirse.
	func _minimapa() -> void:
		var data: LevelData = nivel.arena.data
		if data == null:
			return
		var origen := Vector2(size.x - MARGEN - MINIMAPA.x, size.y - MARGEN - MINIMAPA.y)
		_caja(Rect2(origen - Vector2(4, 4), MINIMAPA + Vector2(8, 8)))

		var mundo := Vector2(data.width, data.height) * GameConfig.CELL_SIZE
		var escala: float = minf(MINIMAPA.x / mundo.x, MINIMAPA.y / mundo.y)
		var desfase := origen + (MINIMAPA - mundo * escala) * 0.5
		draw_rect(Rect2(desfase, mundo * escala), Color(0.13, 0.13, 0.17))

		for r in data.wall_runs():
			var run: Rect2i = r
			draw_rect(Rect2(desfase + Vector2(run.position) * GameConfig.CELL_SIZE * escala,
					Vector2(run.size) * GameConfig.CELL_SIZE * escala),
					Color(0.34, 0.32, 0.42))

		for s in nivel.arena.spikes:
			draw_circle(desfase + (s as Node2D).global_position * escala, 1.6,
					Color(0.85, 0.35, 0.35, 0.75))
		for pot in nivel.arena.potions:
			if (pot as Potion).available:
				draw_circle(desfase + (pot as Node2D).global_position * escala, 2.0,
						Color(0.45, 0.95, 0.55))

		for a in nivel.arena.actors:
			var actor := a as Actor
			if not actor.alive:
				continue
			var punto := desfase + actor.global_position * escala
			if actor is Player:
				draw_circle(punto, 3.6, Color(0.35, 0.85, 0.95))
				draw_arc(punto, 5.5, 0.0, TAU, 12, Color(0.35, 0.85, 0.95, 0.55), 1.0)
			else:
				draw_circle(punto, 2.6, actor.body_color)

	func _ayuda() -> void:
		draw_string(ThemeDB.fallback_font, Vector2(MARGEN, size.y - MARGEN),
				"Flechas mover · raton apuntar · click izq melee · click der disparo · "
				+ "Espacio impulso · Shift defender · Q pocion · R reiniciar · "
				+ "F1 depuracion · Esc pausa",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TENUE)
