class_name Chart
extends Control
## Grafica de lineas reutilizable, con varias series y marcas verticales.
##
## Sustituye a la curva a medida que tenia la pantalla de entrenamiento. Se usa
## para el fitness por generacion, la tasa de victoria y el reparto de acciones,
## y todas se ven igual porque son el mismo control.
##
## Nunca inventa datos: si una serie esta vacia, dibuja el marco y lo dice.

class Serie extends RefCounted:
	var nombre: String
	var color: Color
	var valores: Array = []
	var grosor: float = 1.6

	func _init(p_nombre: String, p_color: Color, p_grosor: float = 1.6) -> void:
		nombre = p_nombre
		color = p_color
		grosor = p_grosor


const MARGEN_IZQ := 42.0
const MARGEN_DER := 8.0
const MARGEN_SUP := 20.0
const MARGEN_INF := 16.0

var titulo: String = ""
var series: Array = []
## Indices del eje X donde pintar una linea vertical (cambios de etapa).
var marcas: Array = []
var etiqueta_x: String = ""
## Fuerza el minimo del eje Y en 0 (util para porcentajes y conteos).
var base_cero: bool = false
## Sufijo del eje Y ("%" para tasas).
var sufijo: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(0, 130)


func anadir_serie(nombre: String, color: Color, grosor: float = 1.6) -> Serie:
	var s := Serie.new(nombre, color, grosor)
	series.append(s)
	return s


func limpiar() -> void:
	for s in series:
		(s as Serie).valores.clear()
	marcas.clear()
	queue_redraw()


func marcar(indice: int) -> void:
	if indice > 0:
		marcas.append(indice)
	queue_redraw()


func _puntos_maximos() -> int:
	var n := 0
	for s in series:
		n = maxi(n, (s as Serie).valores.size())
	return n


func _draw() -> void:
	var marco := Rect2(Vector2.ZERO, size)
	UI.caja_dibujada(self, marco, UI.PANEL, UI.BORDE)
	if titulo != "":
		UI.texto_dibujado(self, Vector2(8, 13), titulo, UI.T_PEQUENO, UI.TENUE)

	var n := _puntos_maximos()
	if n < 2:
		UI.texto_dibujado(self, Vector2(size.x * 0.5, size.y * 0.5),
				"sin datos todavia", UI.T_PEQUENO, UI.APAGADO, HORIZONTAL_ALIGNMENT_CENTER)
		_leyenda()
		return

	var lo := INF
	var hi := -INF
	for s in series:
		for v in (s as Serie).valores:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
	if base_cero:
		lo = minf(lo, 0.0)
	# Rango minimo: sin esto una serie plana (justo el sintoma del agente que no
	# aprende) se dibuja como ruido a pantalla completa y enganaria al ojo.
	if hi - lo < 0.0001:
		hi = lo + 1.0
	var margen_rango := (hi - lo) * 0.08
	lo -= margen_rango
	hi += margen_rango

	var ancho := size.x - MARGEN_IZQ - MARGEN_DER
	var alto := size.y - MARGEN_SUP - MARGEN_INF
	var y_de := func(v: float) -> float:
		return MARGEN_SUP + alto * (1.0 - (v - lo) / (hi - lo))

	# Rejilla horizontal en tres niveles, con sus valores.
	for i in 3:
		var t := float(i) / 2.0
		var v: float = lo + (hi - lo) * (1.0 - t)
		var y: float = MARGEN_SUP + alto * t
		draw_line(Vector2(MARGEN_IZQ, y), Vector2(size.x - MARGEN_DER, y),
				Color(1, 1, 1, 0.05), 1.0)
		UI.texto_dibujado(self, Vector2(MARGEN_IZQ - 5, y + 3),
				_formato(v), UI.T_MICRO, UI.APAGADO, HORIZONTAL_ALIGNMENT_RIGHT)

	# Eje del cero, si el rango lo cruza.
	if lo < 0.0 and hi > 0.0:
		var y0: float = y_de.call(0.0)
		draw_line(Vector2(MARGEN_IZQ, y0), Vector2(size.x - MARGEN_DER, y0),
				Color(1, 1, 1, 0.16), 1.0)

	for m in marcas:
		var x: float = MARGEN_IZQ + ancho * (float(m) / float(maxi(1, n - 1)))
		draw_line(Vector2(x, MARGEN_SUP), Vector2(x, size.y - MARGEN_INF),
				Color(UI.AVISO.r, UI.AVISO.g, UI.AVISO.b, 0.35), 1.0)

	for s in series:
		var serie := s as Serie
		if serie.valores.size() < 2:
			continue
		var puntos := PackedVector2Array()
		for i in serie.valores.size():
			puntos.append(Vector2(
					MARGEN_IZQ + ancho * (float(i) / float(maxi(1, n - 1))),
					y_de.call(float(serie.valores[i]))))
		draw_polyline(puntos, serie.color, serie.grosor, true)

	if etiqueta_x != "":
		UI.texto_dibujado(self, Vector2(size.x - MARGEN_DER, size.y - 4),
				etiqueta_x, UI.T_MICRO, UI.APAGADO, HORIZONTAL_ALIGNMENT_RIGHT)
	_leyenda()


func _leyenda() -> void:
	var x := MARGEN_IZQ + 4.0
	for s in series:
		var serie := s as Serie
		var ultimo := ""
		if not serie.valores.is_empty():
			ultimo = "  " + _formato(float(serie.valores[serie.valores.size() - 1]))
		draw_rect(Rect2(Vector2(x, size.y - 12.0), Vector2(8, 8)), serie.color)
		UI.texto_dibujado(self, Vector2(x + 11.0, size.y - 5.0),
				serie.nombre + ultimo, UI.T_MICRO, UI.TENUE)
		x += 24.0 + ThemeDB.fallback_font.get_string_size(
				serie.nombre + ultimo, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.T_MICRO).x


func _formato(v: float) -> String:
	if sufijo == "%":
		return "%d%%" % int(round(v * 100.0))
	if absf(v) >= 100.0:
		return "%d" % int(round(v))
	return "%.1f" % v
