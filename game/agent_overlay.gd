class_name AgentOverlay
extends Node2D
## Dibuja lo que el agente PERCIBE y lo que DECIDE, encima de la arena.
##
## Es la pieza que convierte la red neuronal de caja negra en algo que se puede
## ensenar. Sobre cada agente pinta:
##   - los 7 sensores como barras, con su nombre y su valor normalizado
##   - las 6 salidas de la red como barras de probabilidad, con la elegida
##     marcada
##   - la ruta A* que esta siguiendo
##   - la accion actual sobre la cabeza
##   - el rastro de por donde ha pasado
##
## Todo son datos reales leidos del agente: `last_inputs` y `last_probs` son
## exactamente los vectores que entraron y salieron de la red en su ultima
## decision, no una reconstruccion.
##
## SOLO PRESENTACION. Vive fuera del Arena, se le pasa a que agente mirar, y no
## existe durante el barrido.

const MAX_RASTRO := 220
const ANCHO_PANEL := 132.0

## Que capas mostrar. La interfaz las conmuta.
var mostrar_sensores: bool = true
var mostrar_salidas: bool = true
var mostrar_ruta: bool = true
var mostrar_rastro: bool = true

var agente: AgentEnemy = null
## Arena que se esta observando. Al fijarla, el overlay se engancha solo al
## primer agente que encuentre; asi quien lo usa no tiene que perseguir el
## cambio de agente en cada episodio.
var arena: Arena = null

var _rastro: PackedVector2Array = PackedVector2Array()
var _ultimo_registrado: Vector2 = Vector2.INF


func _ready() -> void:
	z_index = 90


func _process(_delta: float) -> void:
	var siguiente: AgentEnemy = null
	if arena != null and is_instance_valid(arena) and not arena.agents.is_empty():
		siguiente = arena.agents[0] as AgentEnemy
	refrescar(siguiente)


## Se llama cada fotograma desde quien dibuja la arena.
func refrescar(nuevo_agente: AgentEnemy) -> void:
	if nuevo_agente != agente:
		agente = nuevo_agente
		_rastro = PackedVector2Array()
		_ultimo_registrado = Vector2.INF
	if agente != null and is_instance_valid(agente) and agente.alive:
		var p := agente.global_position
		# Solo se guarda al desplazarse de verdad: sin este filtro, un agente
		# quieto llena el rastro de puntos identicos y borra su propia historia.
		if _ultimo_registrado == Vector2.INF or p.distance_squared_to(_ultimo_registrado) > 90.0:
			_rastro.append(p)
			_ultimo_registrado = p
			if _rastro.size() > MAX_RASTRO:
				_rastro.remove_at(0)
	queue_redraw()


func limpiar() -> void:
	_rastro = PackedVector2Array()
	_ultimo_registrado = Vector2.INF
	queue_redraw()


func _draw() -> void:
	if agente == null or not is_instance_valid(agente):
		return

	if mostrar_rastro and _rastro.size() >= 2:
		# Degradado por tramos: lo reciente brilla, lo viejo se apaga. Un rastro
		# de color plano no dice hacia donde iba.
		for i in range(1, _rastro.size()):
			var t := float(i) / float(_rastro.size())
			draw_line(_rastro[i - 1], _rastro[i],
					Color(UI.COLOR_AGENTE.r, UI.COLOR_AGENTE.g, UI.COLOR_AGENTE.b,
					0.08 + 0.42 * t), 1.0 + 1.4 * t)

	if not agente.alive:
		return

	var origen := agente.global_position

	if mostrar_ruta:
		_dibujar_ruta(origen)

	# Anillo de pulso: se cierra a medida que se acerca la siguiente decision.
	var fase := 1.0 - float(agente.ticks_since_decision) / float(AgentEnemy.DECISION_INTERVAL)
	draw_arc(origen, GameConfig.ACTOR_RADIUS + 6.0 + 4.0 * fase, 0.0, TAU, 20,
			Color(UI.COLOR_AGENTE.r, UI.COLOR_AGENTE.g, UI.COLOR_AGENTE.b, 0.25 + 0.35 * fase), 1.5)

	# Accion actual sobre la cabeza.
	var accion := AgentActions.name_of(agente.current_action)
	if agente.current_action == Thresholding.NO_ACTION:
		accion = "(sin accion)"
	UI.texto_dibujado(self, origen + Vector2(0, -GameConfig.ACTOR_RADIUS - 22.0),
			accion, 12, UI.COLOR_AGENTE, HORIZONTAL_ALIGNMENT_CENTER)

	if mostrar_sensores:
		_panel_sensores(origen + Vector2(-ANCHO_PANEL - 26.0, -58.0))
	if mostrar_salidas:
		_panel_salidas(origen + Vector2(26.0, -58.0))


func _dibujar_ruta(origen: Vector2) -> void:
	if agente.pathing == null:
		return
	var puntos := agente.pathing.debug_path()
	if puntos.is_empty():
		return
	var previo := origen
	for punto in puntos:
		draw_line(previo, punto, Color(1.0, 1.0, 1.0, 0.28), 1.0)
		draw_circle(punto, 2.0, Color(1.0, 1.0, 1.0, 0.35))
		previo = punto


func _panel_sensores(esquina: Vector2) -> void:
	var valores := agente.last_inputs
	if valores.size() < AgentSensors.COUNT:
		return
	var alto := 14.0 + AgentSensors.COUNT * 12.0
	UI.caja_dibujada(self, Rect2(esquina, Vector2(ANCHO_PANEL, alto)),
			Color(0.05, 0.05, 0.08, 0.82), Color(UI.ACENTO.r, UI.ACENTO.g, UI.ACENTO.b, 0.35))
	UI.texto_dibujado(self, esquina + Vector2(6, 11), "SENSORES", 9, UI.ACENTO)
	for i in AgentSensors.COUNT:
		var y := esquina.y + 20.0 + i * 12.0
		var v := float(valores[i])
		# El angulo viene en [-1, 1]; se remapea para que la barra tenga sentido.
		var fraccion: float = (v + 1.0) * 0.5 if i == AgentSensors.ANGLE_TO_TARGET else v
		UI.texto_dibujado(self, Vector2(esquina.x + 6, y + 7), AgentSensors.NAMES[i],
				9, UI.TENUE)
		var barra_x := esquina.x + 74.0
		draw_rect(Rect2(Vector2(barra_x, y), Vector2(38.0, 7.0)), Color(0.18, 0.18, 0.23))
		draw_rect(Rect2(Vector2(barra_x, y), Vector2(38.0 * clampf(fraccion, 0.0, 1.0), 7.0)),
				UI.ACENTO)
		UI.texto_dibujado(self, Vector2(esquina.x + ANCHO_PANEL - 4, y + 7),
				"%.2f" % v, 9, UI.TEXTO, HORIZONTAL_ALIGNMENT_RIGHT)


func _panel_salidas(esquina: Vector2) -> void:
	var probs := agente.last_probs
	if probs.size() < AgentActions.COUNT:
		return
	var alto := 14.0 + AgentActions.COUNT * 12.0
	UI.caja_dibujada(self, Rect2(esquina, Vector2(ANCHO_PANEL, alto)),
			Color(0.05, 0.05, 0.08, 0.82), Color(UI.EXITO.r, UI.EXITO.g, UI.EXITO.b, 0.35))
	UI.texto_dibujado(self, esquina + Vector2(6, 11), "RED -> ACCION", 9, UI.EXITO)
	for i in AgentActions.COUNT:
		var y := esquina.y + 20.0 + i * 12.0
		var p := float(probs[i])
		var elegida: bool = i == agente.current_action
		UI.texto_dibujado(self, Vector2(esquina.x + 6, y + 7), AgentActions.NAMES[i],
				9, UI.TEXTO if elegida else UI.TENUE)
		var barra_x := esquina.x + 74.0
		draw_rect(Rect2(Vector2(barra_x, y), Vector2(38.0, 7.0)), Color(0.18, 0.18, 0.23))
		draw_rect(Rect2(Vector2(barra_x, y), Vector2(38.0 * clampf(p, 0.0, 1.0), 7.0)),
				UI.EXITO if elegida else Color(0.30, 0.45, 0.35))
		UI.texto_dibujado(self, Vector2(esquina.x + ANCHO_PANEL - 4, y + 7),
				"%.2f" % p, 9, UI.TEXTO if elegida else UI.TENUE,
				HORIZONTAL_ALIGNMENT_RIGHT)
