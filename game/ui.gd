class_name UI
extends RefCounted
## Lenguaje visual unico del proyecto: paleta, tipografia, espaciado y fabricas
## de controles.
##
## Antes cada pantalla declaraba sus propios Color(0.09, 0.08, 0.12) y montaba
## sus botones a mano. Con tres pantallas eso ya eran tres paletas que se
## parecian pero no coincidian, y cualquier ajuste habia que hacerlo tres veces.
## Todo lo que se ve sale de aqui.

# --- Paleta ------------------------------------------------------------------
const FONDO := Color(0.055, 0.055, 0.075)
const PANEL := Color(0.095, 0.095, 0.125)
const PANEL_ALTO := Color(0.13, 0.13, 0.17)
const BORDE := Color(0.22, 0.22, 0.30)
const TEXTO := Color(0.90, 0.90, 0.94)
const TENUE := Color(0.56, 0.56, 0.65)
const APAGADO := Color(0.36, 0.36, 0.44)

const ACENTO := Color(0.30, 0.80, 0.95)      ## azul: informacion, seleccion
const EXITO := Color(0.35, 0.90, 0.55)       ## verde: bien, mejor, victoria
const AVISO := Color(0.98, 0.72, 0.28)       ## ambar: cuidado, medio
const PELIGRO := Color(0.95, 0.36, 0.36)     ## rojo: mal, dano, derrota
const VIOLETA := Color(0.68, 0.52, 0.95)     ## secundario para graficas

## Colores de los actores. Fuente unica: antes estaban repetidos en el menu, en
## la leyenda del entrenamiento y en cada EnemyProfile.
const COLOR_JUGADOR := Color(0.35, 0.85, 0.95)
const COLOR_AGENTE := Color(0.55, 0.95, 0.60)
const COLOR_A := Color(0.87, 0.30, 0.26)
const COLOR_B := Color(0.36, 0.55, 0.92)
const COLOR_C := Color(0.93, 0.72, 0.24)
const COLOR_D := Color(0.85, 0.45, 0.85)

# --- Tipografia y ritmo -------------------------------------------------------
const T_TITULO := 30
const T_SECCION := 15
const T_CUERPO := 13
const T_PEQUENO := 11
const T_MICRO := 10

const ESPACIO := 8
const MARGEN := 20
const RADIO := 4.0


static func color_actor(type_id: String) -> Color:
	match type_id.to_upper():
		"A": return COLOR_A
		"B": return COLOR_B
		"C": return COLOR_C
		"D": return COLOR_D
		"AGENT": return COLOR_AGENTE
	return COLOR_JUGADOR


# =============================================================================
# Fabricas de controles
# =============================================================================

static func etiqueta(texto: String, tam: int = T_CUERPO, color: Color = TEXTO,
		alineacion: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = alineacion
	return l


static func parrafo(texto: String, tam: int = T_PEQUENO, color: Color = TENUE) -> Label:
	var l := etiqueta(texto, tam, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func titulo(texto: String) -> Label:
	return etiqueta(texto, T_TITULO, ACENTO)


static func seccion(texto: String) -> Label:
	var l := etiqueta(texto, T_SECCION, ACENTO)
	l.add_theme_constant_override("line_spacing", 2)
	return l


static func boton(texto: String, accion: Callable, alto: int = 32,
		principal: bool = false) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(0, alto)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.add_theme_font_size_override("font_size", T_CUERPO if principal else T_PEQUENO)
	if principal:
		b.add_theme_color_override("font_color", FONDO)
		b.add_theme_color_override("font_hover_color", FONDO)
		b.add_theme_stylebox_override("normal", _caja(ACENTO, ACENTO))
		b.add_theme_stylebox_override("hover", _caja(ACENTO.lightened(0.18), ACENTO))
		b.add_theme_stylebox_override("pressed", _caja(ACENTO.darkened(0.15), ACENTO))
	else:
		b.add_theme_stylebox_override("normal", _caja(PANEL_ALTO, BORDE))
		b.add_theme_stylebox_override("hover", _caja(PANEL_ALTO.lightened(0.10), ACENTO))
		b.add_theme_stylebox_override("pressed", _caja(PANEL, ACENTO))
	b.add_theme_stylebox_override("disabled", _caja(PANEL, BORDE.darkened(0.3)))
	b.add_theme_color_override("font_disabled_color", APAGADO)
	if accion.is_valid():
		b.pressed.connect(accion)
	return b


static func _caja(relleno: Color, borde: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = relleno
	sb.border_color = borde
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(RADIO))
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	return sb


## Contenedor con fondo y borde, el ladrillo de todos los paneles.
static func panel(titulo_texto: String = "") -> VBoxContainer:
	var marco := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = BORDE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(RADIO))
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	marco.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ESPACIO)
	marco.add_child(col)
	if titulo_texto != "":
		col.add_child(seccion(titulo_texto))
	# El llamante recibe la COLUMNA, no el marco: asi solo tiene que anadir
	# hijos. El marco se recupera con .get_parent() cuando hace falta.
	return col


static func separador() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", ESPACIO)
	return s


static func spin(valor: float, minimo: float, maximo: float, paso: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minimo
	s.max_value = maximo
	s.step = paso
	s.value = valor
	s.select_all_on_focus = true
	s.custom_minimum_size = Vector2(104, 0)
	return s


static func opciones(items: Array, seleccion: int) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(str(items[i]), i)
	o.selected = clampi(seleccion, 0, maxi(0, items.size() - 1))
	o.custom_minimum_size = Vector2(104, 0)
	o.add_theme_font_size_override("font_size", T_PEQUENO)
	return o


# =============================================================================
# Primitivas de dibujado, compartidas por HUD, dashboard y minimapa
# =============================================================================

static func caja_dibujada(c: CanvasItem, rect: Rect2, relleno: Color = PANEL,
		borde: Color = BORDE) -> void:
	c.draw_rect(rect, relleno)
	c.draw_rect(rect, borde, false, 1.0)


## Barra con etiqueta a la izquierda y valor a la derecha, ambos dentro.
static func barra(c: CanvasItem, pos: Vector2, ancho: float, alto: float,
		fraccion: float, color: Color, izquierda: String = "",
		derecha: String = "") -> void:
	var fuente := ThemeDB.fallback_font
	c.draw_rect(Rect2(pos, Vector2(ancho, alto)), Color(0.15, 0.15, 0.19))
	c.draw_rect(Rect2(pos, Vector2(ancho * clampf(fraccion, 0.0, 1.0), alto)), color)
	c.draw_rect(Rect2(pos, Vector2(ancho, alto)), Color(0, 0, 0, 0.40), false, 1.0)
	var linea_base := pos + Vector2(0.0, alto - maxf(3.0, (alto - 9.0) * 0.5))
	if izquierda != "":
		c.draw_string(fuente, linea_base + Vector2(6, 0), izquierda,
				HORIZONTAL_ALIGNMENT_LEFT, -1, T_PEQUENO, Color(1, 1, 1, 0.88))
	if derecha != "":
		c.draw_string(fuente, linea_base + Vector2(ancho - 6, 0), derecha,
				HORIZONTAL_ALIGNMENT_RIGHT, -1, T_PEQUENO, Color(1, 1, 1, 0.88))


static func texto_dibujado(c: CanvasItem, pos: Vector2, texto: String,
		tam: int = T_PEQUENO, color: Color = TEXTO,
		alineacion: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	c.draw_string(ThemeDB.fallback_font, pos, texto, alineacion, -1, tam, color)


## Formatea segundos como m:ss.
static func reloj(segundos: float) -> String:
	var s := int(maxf(0.0, segundos))
	return "%d:%02d" % [s / 60, s % 60]
