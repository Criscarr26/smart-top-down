class_name TrainingConfig
extends RefCounted
## El formulario de entrenamiento: construye los controles, los lee, los escribe
## y los guarda en disco.
##
## Esta separado del laboratorio a proposito. Antes la pantalla de entrenamiento
## era un solo archivo de 44 KB que montaba la interfaz, llevaba el estado del
## formulario, orquestaba el Trainer, dibujaba la curva y escribia los archivos.
## Aqui vive UNA cosa: la configuracion. El laboratorio la usa sin saber como
## esta hecha, y anadir un peso nuevo al fitness no obliga a tocar la pantalla.

signal cambio

const RUTA_AJUSTES := "user://ajustes_entrenamiento.json"

## Etapas del curriculum. La cuarta usa el bot sustituto: un
## humano no cabe dentro de un bucle de miles de episodios.
const ETAPAS := [
	["vs_tipo_A", "Contra Tipo A (persigue y golpea)"],
	["vs_tipo_B", "Contra Tipo B (torreta que se defiende)"],
	["vs_tipo_C", "Contra Tipo C (dispara y huye)"],
	["vs_humano_bot", "Contra el bot sustituto del humano"],
	["vs_escolta_D", "Contra un Tipo A escoltado por un sanador"],
]

var pesos: Fitness.Weights = Fitness.defaults()
var ga: GAConfig = ExperimentMatrix.baseline()

var _campos_fitness: Dictionary = {}
var _campos_ga: Dictionary = {}
var _checks: Array = []
var _capas: LineEdit
var _spin_paralelo: SpinBox
var _spin_velocidad: SpinBox
var _spin_semilla: SpinBox
var _spin_segundos: SpinBox
var _check_vitrina: CheckBox
var _aviso: Label


# =============================================================================
# Construccion
# =============================================================================

func construir(col: VBoxContainer) -> void:
	col.add_child(UI.seccion("FUNCION DE FITNESS"))
	col.add_child(UI.parrafo("La heuristica: define que cuenta como jugar bien. "
			+ "Cambiarla cambia el problema, no solo la busqueda."))
	for f in Fitness.FIELDS:
		var key := str(f["key"])
		var s := _fila_num(col, str(f["label"]), float(pesos.get(key)),
				float(f["min"]), float(f["max"]), float(f["step"]), str(f["hint"]))
		s.value_changed.connect(func(_v: float) -> void: _revisar_aviso())
		_campos_fitness[key] = s

	_aviso = UI.parrafo("", UI.T_MICRO, UI.AVISO)
	col.add_child(_aviso)

	col.add_child(UI.seccion("ALGORITMO GENETICO"))
	col.add_child(UI.parrafo("Como se busca la solucion: las ocho variables del barrido, "
			+ "mas la topologia de la red."))
	_campos_ga["population_size"] = _fila_num(col, "Pobladores (i)", ga.population_size,
			2, 200, 1, "Mas exploracion por generacion, y mas coste.")
	_campos_ga["generations"] = _fila_num(col, "Generaciones", ga.generations,
			1, 200, 1, "Ciclos de evaluar-reproducir por etapa.")
	_campos_ga["elite_count"] = _fila_num(col, "Elite", ga.elite_count,
			0, 20, 1, "Pasan intactos. Sin esto se puede perder el mejor.")
	_campos_ga["episodes_per_individual"] = _fila_num(col, "Episodios/individuo",
			ga.episodes_per_individual, 1, 10, 1, "Su fitness es la MEDIA de estos.")
	_campos_ga["mutation_rate"] = _fila_num(col, "Tasa mutacion (ii)", ga.mutation_rate,
			0.0, 1.0, 0.01, "Probabilidad de que cada peso mute.")
	_campos_ga["mutation_strength"] = _fila_num(col, "Fuerza mutacion", ga.mutation_strength,
			0.0, 3.0, 0.05, "Desviacion del ruido, o amplitud del reemplazo.")
	_campos_ga["mutation_mode"] = _fila_opt(col, "Tecnica mutacion (v)",
			[Mutation.mode_name(Mutation.Mode.GAUSSIAN),
			Mutation.mode_name(Mutation.Mode.RANDOM_RESET)], ga.mutation_mode,
			"Gaussiana afina; reemplazo saca de optimos locales.")
	_campos_ga["selection_mode"] = _fila_opt(col, "Tecnica seleccion (vi)",
			[Selection.mode_name(Selection.Mode.TOURNAMENT),
			Selection.mode_name(Selection.Mode.ROULETTE)], ga.selection_mode,
			"El torneo compara; la ruleta necesita desplazar el fitness negativo.")
	_campos_ga["selection_rate"] = _fila_num(col, "Tasa seleccion (iv)", ga.selection_rate,
			0.05, 1.0, 0.05, "Fraccion superior que puede reproducirse.")
	_campos_ga["tournament_size"] = _fila_num(col, "Tamano torneo", ga.tournament_size,
			2, 10, 1, "Mas grande, mas presion selectiva.")
	_campos_ga["crossover_mode"] = _fila_opt(col, "Tecnica cruce (vii)",
			[Crossover.mode_name(Crossover.Mode.UNIFORM),
			Crossover.mode_name(Crossover.Mode.ONE_POINT)], ga.crossover_mode,
			"Uniforme mezcla peso a peso; un punto corta el vector.")
	_campos_ga["init_mode"] = _fila_opt(col, "Pesos iniciales (iii)",
			[Genome.init_name(Genome.Init.RANDOM), Genome.init_name(Genome.Init.EQUAL),
			Genome.init_name(Genome.Init.ZERO)], ga.init_mode,
			"Con pesos nulos la primera generacion es ciega.")
	_campos_ga["thresholding_mode"] = _fila_opt(col, "Thresholding (viii)",
			[Thresholding.mode_name(Thresholding.Mode.SOFTMAX_ARGMAX),
			Thresholding.mode_name(Thresholding.Mode.FIXED_THRESHOLD),
			Thresholding.mode_name(Thresholding.Mode.STOCHASTIC)], ga.thresholding_mode,
			"Como se convierte la salida de la red en UNA accion.")
	_campos_ga["threshold_value"] = _fila_num(col, "Valor umbral", ga.threshold_value,
			0.0, 1.0, 0.01, "Solo lo usa 'umbral_fijo'.")
	_capas = _fila_texto(col, "Capas ocultas", _capas_a_texto(ga.hidden_layers),
			"Comas: 10,6. Vacio = red shallow (alternativa a la profunda).")

	col.add_child(UI.seccion("CORRIDA"))
	col.add_child(UI.parrafo("Cada etapa arranca con el mejor agente de la anterior "
			+ "sembrando con el mejor. Desmarcar etapas abarata la corrida."))
	for e in ETAPAS:
		var chk := CheckBox.new()
		chk.text = str(e[1])
		chk.button_pressed = true
		chk.add_theme_font_size_override("font_size", UI.T_PEQUENO)
		chk.toggled.connect(func(_on: bool) -> void: cambio.emit())
		col.add_child(chk)
		_checks.append(chk)

	_spin_segundos = _fila_num(col, "Duracion episodio (s)",
			float(GameConfig.TRAINING_EPISODE_TICKS) / float(GameConfig.TICKS_PER_SECOND),
			5, 60, 1, "Sin resolver en 30 s ya es empate.")
	_spin_paralelo = _fila_num(col, "Arenas en paralelo", 16, 1, 32, 1,
			"Cada una con su World2D. 16 fue el mejor punto medido.")
	_spin_velocidad = _fila_num(col, "Aceleracion (x)", 30, 1, 60, 1,
			"Se puede mover MIENTRAS corre. No cambia el resultado.")
	_spin_semilla = _fila_num(col, "Semilla", 20260408, 0, 99999999, 1,
			"Misma semilla y mismos ajustes = misma corrida.")

	_check_vitrina = CheckBox.new()
	_check_vitrina.text = "Dibujar una arena en vivo"
	_check_vitrina.button_pressed = true
	_check_vitrina.add_theme_font_size_override("font_size", UI.T_PEQUENO)
	col.add_child(_check_vitrina)

	for s in [_spin_segundos, _spin_paralelo, _spin_velocidad]:
		s.value_changed.connect(func(_v: float) -> void: cambio.emit())
	for k in ["population_size", "generations", "episodes_per_individual"]:
		(_campos_ga[k] as SpinBox).value_changed.connect(
				func(_v: float) -> void: cambio.emit())
	_revisar_aviso()


func _fila(padre: VBoxContainer, etiqueta: String, control: Control, hint: String) -> void:
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 1)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", UI.ESPACIO)
	var l := UI.etiqueta(etiqueta, UI.T_PEQUENO)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(l)
	control.tooltip_text = hint
	fila.add_child(control)
	caja.add_child(fila)
	# La ayuda va a la vista y no solo en el tooltip: en una demo delante de
	# alguien, un tooltip que hay que descubrir con el raton es como no estar.
	caja.add_child(UI.parrafo(hint, UI.T_MICRO, UI.APAGADO))
	padre.add_child(caja)


func _fila_num(padre: VBoxContainer, etiqueta: String, valor: float, minimo: float,
		maximo: float, paso: float, hint: String) -> SpinBox:
	var s := UI.spin(valor, minimo, maximo, paso)
	_fila(padre, etiqueta, s, hint)
	return s


func _fila_opt(padre: VBoxContainer, etiqueta: String, items: Array, sel: int,
		hint: String) -> OptionButton:
	var o := UI.opciones(items, sel)
	_fila(padre, etiqueta, o, hint)
	return o


func _fila_texto(padre: VBoxContainer, etiqueta: String, valor: String,
		hint: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = valor
	e.custom_minimum_size = Vector2(104, 0)
	_fila(padre, etiqueta, e, hint)
	return e


# =============================================================================
# Formulario <-> datos
# =============================================================================

func leer() -> void:
	for f in Fitness.FIELDS:
		var key := str(f["key"])
		pesos.set(key, float((_campos_fitness[key] as SpinBox).value))
	ga.population_size = int((_campos_ga["population_size"] as SpinBox).value)
	ga.generations = int((_campos_ga["generations"] as SpinBox).value)
	ga.elite_count = int((_campos_ga["elite_count"] as SpinBox).value)
	ga.episodes_per_individual = int((_campos_ga["episodes_per_individual"] as SpinBox).value)
	ga.mutation_rate = float((_campos_ga["mutation_rate"] as SpinBox).value)
	ga.mutation_strength = float((_campos_ga["mutation_strength"] as SpinBox).value)
	ga.threshold_value = float((_campos_ga["threshold_value"] as SpinBox).value)
	ga.selection_rate = float((_campos_ga["selection_rate"] as SpinBox).value)
	ga.tournament_size = int((_campos_ga["tournament_size"] as SpinBox).value)
	ga.mutation_mode = (_campos_ga["mutation_mode"] as OptionButton).selected
	ga.selection_mode = (_campos_ga["selection_mode"] as OptionButton).selected
	ga.crossover_mode = (_campos_ga["crossover_mode"] as OptionButton).selected
	ga.init_mode = (_campos_ga["init_mode"] as OptionButton).selected
	ga.thresholding_mode = (_campos_ga["thresholding_mode"] as OptionButton).selected
	ga.hidden_layers = _texto_a_capas(_capas.text)
	# El elitismo no puede llevarse a mas individuos de los que hay: la
	# poblacion siguiente se llenaria de copias y no quedaria sitio para hijos.
	ga.elite_count = mini(ga.elite_count, maxi(0, ga.population_size - 1))


func volcar() -> void:
	for f in Fitness.FIELDS:
		var key := str(f["key"])
		(_campos_fitness[key] as SpinBox).value = float(pesos.get(key))
	(_campos_ga["population_size"] as SpinBox).value = ga.population_size
	(_campos_ga["generations"] as SpinBox).value = ga.generations
	(_campos_ga["elite_count"] as SpinBox).value = ga.elite_count
	(_campos_ga["episodes_per_individual"] as SpinBox).value = ga.episodes_per_individual
	(_campos_ga["mutation_rate"] as SpinBox).value = ga.mutation_rate
	(_campos_ga["mutation_strength"] as SpinBox).value = ga.mutation_strength
	(_campos_ga["threshold_value"] as SpinBox).value = ga.threshold_value
	(_campos_ga["selection_rate"] as SpinBox).value = ga.selection_rate
	(_campos_ga["tournament_size"] as SpinBox).value = ga.tournament_size
	(_campos_ga["mutation_mode"] as OptionButton).selected = ga.mutation_mode
	(_campos_ga["selection_mode"] as OptionButton).selected = ga.selection_mode
	(_campos_ga["crossover_mode"] as OptionButton).selected = ga.crossover_mode
	(_campos_ga["init_mode"] as OptionButton).selected = ga.init_mode
	(_campos_ga["thresholding_mode"] as OptionButton).selected = ga.thresholding_mode
	_capas.text = _capas_a_texto(ga.hidden_layers)
	_revisar_aviso()


func restaurar() -> void:
	pesos = Fitness.defaults()
	ga = ExperimentMatrix.baseline()
	for c in _checks:
		(c as CheckBox).button_pressed = true
	_spin_paralelo.value = 16
	_spin_velocidad.value = 30
	_spin_semilla.value = 20260408
	_spin_segundos.value = float(GameConfig.TRAINING_EPISODE_TICKS) \
			/ float(GameConfig.TICKS_PER_SECOND)
	_check_vitrina.button_pressed = true
	volcar()
	cambio.emit()


# --- Accesores ----------------------------------------------------------------

func paralelo() -> int: return int(_spin_paralelo.value)
func velocidad() -> int: return int(_spin_velocidad.value)
func semilla() -> int: return int(_spin_semilla.value)
func segundos_episodio() -> float: return float(_spin_segundos.value)
func vitrina() -> bool: return _check_vitrina.button_pressed
func spin_velocidad() -> SpinBox: return _spin_velocidad


func curriculum() -> Array:
	var todas := Trainer.default_curriculum()
	var out: Array = []
	for i in ETAPAS.size():
		if i < _checks.size() and (_checks[i] as CheckBox).button_pressed:
			out.append(todas[i])
	return out


## Cota ALTA del coste. Los episodios que acaban con un bando eliminado duran
## menos que el corte, asi que en la practica sale por debajo.
func estimacion() -> Dictionary:
	var etapas := curriculum().size()
	var pob := int((_campos_ga["population_size"] as SpinBox).value)
	var gens := int((_campos_ga["generations"] as SpinBox).value)
	var eps := int((_campos_ga["episodes_per_individual"] as SpinBox).value)
	var episodios := etapas * gens * pob * eps
	var rendimiento := maxf(1.0, float(paralelo()) * float(velocidad()))
	return {
		"etapas": etapas, "generaciones": gens, "poblacion": pob, "episodios_ind": eps,
		"episodios": episodios,
		"minutos": float(episodios) * segundos_episodio() / rendimiento / 60.0,
	}


func _revisar_aviso() -> void:
	if _aviso == null:
		return
	var base := Fitness.defaults()
	var modificado := false
	for f in Fitness.FIELDS:
		var key := str(f["key"])
		if not is_equal_approx(float((_campos_fitness[key] as SpinBox).value),
				float(base.get(key))):
			modificado = true
			break
	_aviso.text = "" if not modificado else \
			"Fitness modificado: el valor absoluto ya no es comparable con el Excel. " \
			+ "Las victorias y la tasa de exito si lo siguen siendo."


# =============================================================================
# Persistencia
# =============================================================================

func guardar() -> bool:
	leer()
	var etapas: Array = []
	for c in _checks:
		etapas.append((c as CheckBox).button_pressed)
	var f := FileAccess.open(RUTA_AJUSTES, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"pesos_fitness": pesos.to_dict(),
		"config_ga": ga.to_dict(),
		"capas_ocultas": ga.hidden_layers,
		"etapas": etapas,
		"paralelo": paralelo(), "velocidad": velocidad(), "semilla": semilla(),
		"segundos_por_episodio": segundos_episodio(), "vitrina": vitrina(),
	}, "\t"))
	f.close()
	return true


func cargar() -> bool:
	if not FileAccess.file_exists(RUTA_AJUSTES):
		return false
	var f := FileAccess.open(RUTA_AJUSTES, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	if d.get("pesos_fitness") is Dictionary:
		pesos.apply_dict(d["pesos_fitness"])
	if d.get("config_ga") is Dictionary:
		var bruto: Dictionary = (d["config_ga"] as Dictionary).duplicate()
		# to_dict() no serializa las capas; van en su propia clave.
		if d.get("capas_ocultas") is Array:
			bruto["capas_ocultas"] = d["capas_ocultas"]
		ga = GAConfig.from_dict(bruto)
	if d.get("etapas") is Array:
		var etapas: Array = d["etapas"]
		for i in mini(etapas.size(), _checks.size()):
			(_checks[i] as CheckBox).button_pressed = bool(etapas[i])
	_spin_paralelo.value = int(d.get("paralelo", _spin_paralelo.value))
	_spin_velocidad.value = int(d.get("velocidad", _spin_velocidad.value))
	_spin_semilla.value = int(d.get("semilla", _spin_semilla.value))
	_spin_segundos.value = float(d.get("segundos_por_episodio", _spin_segundos.value))
	_check_vitrina.button_pressed = bool(d.get("vitrina", _check_vitrina.button_pressed))
	volcar()
	cambio.emit()
	return true


# =============================================================================
# Utilidades
# =============================================================================

func habilitar(si: bool) -> void:
	for k in _campos_fitness:
		(_campos_fitness[k] as Control).editable = si
	for k in _campos_ga:
		var c: Control = _campos_ga[k]
		if c is SpinBox:
			(c as SpinBox).editable = si
		elif c is OptionButton:
			(c as OptionButton).disabled = not si
	_capas.editable = si
	for c in _checks:
		(c as CheckBox).disabled = not si
	_check_vitrina.disabled = not si
	# La aceleracion se deja viva: cambiarla en caliente es seguro y es lo que
	# permite bajar a x2 para mirar el combate y volver a subir.
	_spin_velocidad.editable = true


static func _capas_a_texto(capas: Array) -> String:
	var partes: Array = []
	for c in capas:
		partes.append(str(int(c)))
	return ", ".join(partes)


## Acepta "10,6", "10 6", "10, 6" y vacio (= red shallow). Ignora lo que no sea
## entero positivo en vez de fallar: es un campo libre en una demo.
static func _texto_a_capas(texto: String) -> Array:
	var out: Array = []
	for parte in texto.replace(";", ",").replace(" ", ",").split(",", false):
		var n := int(str(parte).strip_edges())
		if n > 0:
			out.append(n)
	return out
