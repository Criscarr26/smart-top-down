extends Control
## Laboratorio de entrenamiento: pantalla completa, tres columnas.
##
##   izquierda  configuracion (heuristica, algoritmo genetico, corrida)
##   centro     la arena dibujandose, con los sensores y las decisiones encima
##   derecha    metricas reales, graficas y registro
##
## Sustituye al panel apretado que habia dentro del menu. La diferencia no es de
## tamano: aqui se puede mirar UN episodio con detalle mientras corren otros
## quince, comparar la curva con lo que hace el agente en pantalla, y cambiar la
## velocidad para pasar de "ver el combate" a "terminar la corrida" sin parar.
##
## Corre el MISMO Trainer, el MISMO SimPool y las MISMAS Arena que el barrido del
## benchmark. Si tuviera un simulador propio, lo que se aprende aqui no tendria
## por que valer alla y el proyecto entero dejaria de sostenerse.
##
## Ninguna cifra del panel es decorativa: todas salen de TrainingMetrics, que a
## su vez solo consume lo que el Trainer midio en episodios que ocurrieron.

const RUTA_GENOMA := "user://genoma_entrenado.json"
const RUTA_EVALUACION := "user://evaluacion_agente.csv"

## Repeticiones por escenario al evaluar. Las mismas que uso el barrido
## entregado, para que la tabla se compare sin corregir por tamano de muestra.
const REPETICIONES_EVAL := 5

var cfg := TrainingConfig.new()
var m := TrainingMetrics.new()

var _pool: SimPool
var _trainer: Trainer
var _ocupado: bool = false
var _entrenando: bool = false
var _mejor_genoma: Genome = null
var _config_genoma: GAConfig = null

var _vista: ArenaView
## Segunda vista, la de la ventana aparte, con sus propias metricas. Ambas son
## null mientras la ventana esta cerrada.
var _vista_grande: ArenaView
var _metricas_ventana: PanelMetricas
var _ventana: Window
var _chart_fitness: Chart
var _chart_victoria: Chart
var _panel_metricas: PanelMetricas
var _panel_acciones: PanelAcciones
var _log: RichTextLabel
var _barra_progreso: ProgressBar
var _label_estado: Label
var _label_coste: Label

var _b_entrenar: Button
var _b_pausar: Button
var _b_detener: Button
var _b_evaluar: Button
var _b_ventana: Button
var _b_jugar: Button
var _b_volver: Button

var _ticks_fisica_previos: int = 60
var _pasos_fisica_previos: int = 256


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_ticks_fisica_previos = Engine.physics_ticks_per_second
	_pasos_fisica_previos = Engine.max_physics_steps_per_frame
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_construir()
	cfg.cambio.connect(_actualizar_coste)
	cfg.cargar()
	_actualizar_coste()
	_actualizar_botones()
	cfg.spin_velocidad().value_changed.connect(func(v: float) -> void:
			if _ocupado:
				_acelerar(int(v)))


func _exit_tree() -> void:
	Engine.physics_ticks_per_second = _ticks_fisica_previos
	Engine.max_physics_steps_per_frame = _pasos_fisica_previos
	Audio.enabled = true
	if _vista_grande != null and is_instance_valid(_vista_grande):
		_vista_grande.soltar()


func _process(_delta: float) -> void:
	if _panel_metricas != null:
		_panel_metricas.queue_redraw()
	if _panel_acciones != null:
		_panel_acciones.queue_redraw()
	if _metricas_ventana != null and is_instance_valid(_metricas_ventana):
		_metricas_ventana.queue_redraw()
	if _barra_progreso != null and _entrenando:
		_barra_progreso.value = m.progreso() * 100.0
	if _label_estado != null:
		_label_estado.text = m.nombre_estado().to_upper()
		_label_estado.add_theme_color_override("font_color", m.color_estado())


# =============================================================================
# Interfaz
# =============================================================================

func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.color = UI.FONDO
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 14)
	add_child(margen)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margen.add_child(col)

	col.add_child(_barra_superior())

	var tres := HBoxContainer.new()
	tres.add_theme_constant_override("separation", 10)
	tres.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tres)

	tres.add_child(_columna_config())
	tres.add_child(_columna_centro())
	tres.add_child(_columna_metricas())


func _barra_superior() -> Control:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 10)

	var izq := VBoxContainer.new()
	izq.add_theme_constant_override("separation", 0)
	izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	izq.add_child(UI.etiqueta("LABORATORIO DE ENTRENAMIENTO", 22, UI.ACENTO))
	_label_coste = UI.parrafo("", UI.T_MICRO, UI.TENUE)
	izq.add_child(_label_coste)
	fila.add_child(izq)

	_label_estado = UI.etiqueta("LISTO", UI.T_SECCION, UI.TENUE)
	_label_estado.custom_minimum_size = Vector2(120, 0)
	_label_estado.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fila.add_child(_label_estado)

	_barra_progreso = ProgressBar.new()
	_barra_progreso.custom_minimum_size = Vector2(150, 0)
	_barra_progreso.show_percentage = false
	_barra_progreso.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(_barra_progreso)

	_b_entrenar = UI.boton("Entrenar", _entrenar, 34, true)
	_b_entrenar.custom_minimum_size = Vector2(96, 34)
	_b_pausar = UI.boton("Pausar", _pausar, 34)
	_b_pausar.custom_minimum_size = Vector2(84, 34)
	_b_detener = UI.boton("Detener", _detener, 34)
	_b_detener.custom_minimum_size = Vector2(84, 34)
	_b_evaluar = UI.boton("Evaluar", _evaluar, 34)
	_b_evaluar.custom_minimum_size = Vector2(96, 34)
	for b in [_b_entrenar, _b_pausar, _b_detener, _b_evaluar]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		fila.add_child(b)
	return fila


func _columna_config() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	scroll.custom_minimum_size = Vector2(280, 0)

	var col := UI.panel()
	col.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col.get_parent())
	cfg.construir(col)

	col.add_child(UI.separador())
	var f1 := HBoxContainer.new()
	f1.add_theme_constant_override("separation", 6)
	f1.add_child(UI.boton("Por defecto", func() -> void:
			cfg.restaurar()
			_escribir("Valores por defecto restaurados.")))
	f1.add_child(UI.boton("Guardar", func() -> void:
			_escribir("Ajustes guardados." if cfg.guardar() else "No se pudo guardar.")))
	f1.add_child(UI.boton("Cargar", func() -> void:
			_escribir("Ajustes cargados." if cfg.cargar() else "No hay ajustes guardados.")))
	col.add_child(f1)
	return scroll


func _columna_centro() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 2.3

	_vista = ArenaView.new()
	_vista.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_vista)

	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 6)
	barra.add_child(UI.etiqueta("Ver:", UI.T_PEQUENO, UI.TENUE))
	barra.add_child(_toggle("Sensores", true, func(on: bool) -> void:
			_con_overlay(func(o: AgentOverlay) -> void: o.mostrar_sensores = on)))
	barra.add_child(_toggle("Red -> accion", true, func(on: bool) -> void:
			_con_overlay(func(o: AgentOverlay) -> void: o.mostrar_salidas = on)))
	barra.add_child(_toggle("Ruta A*", true, func(on: bool) -> void:
			_con_overlay(func(o: AgentOverlay) -> void: o.mostrar_ruta = on)))
	barra.add_child(_toggle("Rastro", true, func(on: bool) -> void:
			_con_overlay(func(o: AgentOverlay) -> void: o.mostrar_rastro = on)))
	_b_ventana = UI.boton("Ventana aparte", _alternar_ventana, 26)
	_b_ventana.size_flags_horizontal = Control.SIZE_SHRINK_END
	_b_ventana.custom_minimum_size = Vector2(130, 26)
	barra.add_child(_b_ventana)
	col.add_child(barra)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 110)
	_log.add_theme_font_size_override("normal_font_size", UI.T_PEQUENO)
	_log.add_theme_font_size_override("mono_font_size", UI.T_PEQUENO)
	col.add_child(_log)

	var pie := HBoxContainer.new()
	pie.add_theme_constant_override("separation", 6)
	_b_jugar = UI.boton("Jugar contra este agente", _jugar)
	pie.add_child(_b_jugar)
	_b_volver = UI.boton("Volver al menu", func() -> void:
			get_tree().change_scene_to_file("res://game/main_menu.tscn"))
	pie.add_child(_b_volver)
	col.add_child(pie)
	return col


func _toggle(texto: String, activo: bool, accion: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = texto
	c.button_pressed = activo
	c.add_theme_font_size_override("font_size", UI.T_MICRO)
	c.toggled.connect(accion)
	return c


func _con_overlay(accion: Callable) -> void:
	if _pool == null or not is_instance_valid(_pool):
		return
	var o := _pool.showcase_overlay()
	if o != null and is_instance_valid(o):
		accion.call(o)


func _columna_metricas() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.35
	col.custom_minimum_size = Vector2(290, 0)

	_panel_metricas = PanelMetricas.new()
	_panel_metricas.m = m
	_panel_metricas.custom_minimum_size = Vector2(0, 188)
	col.add_child(_panel_metricas)

	_chart_fitness = Chart.new()
	_chart_fitness.titulo = "FITNESS POR GENERACION"
	_chart_fitness.etiqueta_x = "generacion"
	_chart_fitness.anadir_serie("mejor", UI.EXITO, 1.8)
	_chart_fitness.anadir_serie("medio", UI.ACENTO, 1.3)
	col.add_child(_chart_fitness)

	_chart_victoria = Chart.new()
	_chart_victoria.titulo = "TASA DE VICTORIA POR GENERACION"
	_chart_victoria.etiqueta_x = "generacion"
	_chart_victoria.base_cero = true
	_chart_victoria.sufijo = "%"
	_chart_victoria.anadir_serie("victorias", UI.VIOLETA, 1.8)
	col.add_child(_chart_victoria)

	_panel_acciones = PanelAcciones.new()
	_panel_acciones.m = m
	_panel_acciones.custom_minimum_size = Vector2(0, 108)
	col.add_child(_panel_acciones)
	return col


# =============================================================================
# Entrenamiento
# =============================================================================

func _entrenar() -> void:
	if _ocupado:
		return
	cfg.leer()
	var curriculum := cfg.curriculum()
	if curriculum.is_empty():
		_escribir("[color=#fb8]No hay ninguna etapa marcada.[/color]")
		return

	_ocupado = true
	_entrenando = true
	cfg.habilitar(false)
	_actualizar_botones()
	_log.clear()
	_chart_fitness.limpiar()
	_chart_victoria.limpiar()
	m.iniciar(curriculum.size(), cfg.ga.generations)

	_escribir("[color=#5de]Topologia %s - poblacion %d - %d generaciones x %d etapas[/color]"
			% ["-".join(cfg.ga.topology().map(func(v: int) -> String: return str(v))),
			cfg.ga.population_size, cfg.ga.generations, curriculum.size()])

	_abrir_pool()
	Rng.reseed(cfg.semilla())

	_trainer = Trainer.new(cfg.ga, _pool)
	_trainer.fitness_weights = cfg.pesos
	_trainer.episode_ticks = GameConfig.secs_to_ticks(cfg.segundos_episodio())
	_trainer.log_enabled = false
	_trainer.stage_started.connect(_al_empezar_etapa)
	_trainer.generation_completed.connect(_al_terminar_generacion)
	add_child(_trainer)

	var mejor: Genome = await _trainer.train(curriculum)
	_terminar(mejor, curriculum)


func _al_empezar_etapa(indice: int, nombre: String) -> void:
	m.empezar_etapa(indice, nombre)
	_chart_fitness.marcar(m.serie_mejor.size())
	_chart_victoria.marcar(m.serie_victoria.size())
	_escribir("[color=#5de]Etapa %d/%d: %s[/color]"
			% [indice + 1, m.etapas_totales, nombre])


func _al_terminar_generacion(_indice: int, generacion: int, stats: Dictionary) -> void:
	m.registrar_generacion(stats)
	(_chart_fitness.series[0] as Chart.Serie).valores = m.serie_mejor
	(_chart_fitness.series[1] as Chart.Serie).valores = m.serie_medio
	(_chart_victoria.series[0] as Chart.Serie).valores = m.serie_victoria
	_chart_fitness.queue_redraw()
	_chart_victoria.queue_redraw()
	_vista.subtitulo = "gen %d/%d" % [generacion + 1, cfg.ga.generations]
	_escribir("  gen %2d/%d   mejor=%8.2f  medio=%8.2f  victorias %d/%d" % [
		generacion + 1, cfg.ga.generations, float(stats["mejor"]), float(stats["medio"]),
		int(stats.get("victorias", 0)), int(stats.get("episodios", 0))])


func _pausar() -> void:
	if _trainer == null or not is_instance_valid(_trainer):
		return
	_trainer.paused = not _trainer.paused
	m.pausar(_trainer.paused)
	_b_pausar.text = "Reanudar" if _trainer.paused else "Pausar"
	_escribir("[color=#fb8]Pausado.[/color]" if _trainer.paused else "Reanudado.")


func _detener() -> void:
	if _trainer != null and is_instance_valid(_trainer):
		_trainer.paused = false
		_trainer.abort = true
		_b_detener.disabled = true
		_escribir("[color=#fb8]Parando al terminar el lote en curso...[/color]")


func _terminar(mejor: Genome, curriculum: Array) -> void:
	var parado: bool = _trainer != null and _trainer.abort
	var curva: Array = _trainer.convergence_curve() if _trainer != null else []
	if _trainer != null and is_instance_valid(_trainer):
		_trainer.queue_free()
	_trainer = null
	_cerrar_pool()

	_entrenando = false
	_ocupado = false
	cfg.habilitar(true)
	_b_pausar.text = "Pausar"
	m.terminar(parado)

	if mejor == null:
		_escribir("[color=#f88]No se llego a evaluar ninguna generacion.[/color]")
		_actualizar_botones()
		return

	_mejor_genoma = mejor
	_config_genoma = cfg.ga.duplicate_config()
	for e in m.por_etapa:
		var ep := int(e["episodios"])
		_escribir("  %s: mejor %.2f, victorias %d/%d (%.0f%%)" % [e["etapa"],
				float(e["mejor"]), int(e["victorias"]), ep,
				0.0 if ep == 0 else 100.0 * float(e["victorias"]) / float(ep)])

	if _guardar_genoma(mejor, curriculum, curva):
		_escribir("[color=#8f9]Agente guardado en %s[/color]"
				% ProjectSettings.globalize_path(RUTA_GENOMA))
	_escribir("Pulsa Evaluar para medirlo en los 10 escenarios del nivel de validacion.")
	_actualizar_botones()


# =============================================================================
# Evaluacion
# =============================================================================

func _evaluar() -> void:
	if _ocupado:
		return
	var agente := _resolver_agente()
	if agente.is_empty():
		_escribir("[color=#fb8]No hay agente entrenado todavia.[/color]")
		return
	var genoma: Genome = agente[0]
	var config: GAConfig = agente[1]

	_ocupado = true
	m.estado = TrainingMetrics.Estado.EVALUANDO
	cfg.habilitar(false)
	_actualizar_botones()
	_escribir("[color=#a8f]Evaluando: 10 escenarios x %d repeticiones en el nivel de validacion[/color]"
			% REPETICIONES_EVAL)

	_abrir_pool()
	var filas: Array = []
	for rep in REPETICIONES_EVAL:
		var specs := ScenarioCatalog.all(config, genoma)
		for i in specs.size():
			# Mismas semillas que benchmark_runner, para que la tabla se compare
			# con la del Excel escenario por escenario.
			(specs[i] as ArenaSpec).seed = cfg.semilla() + rep * 7919 + i * 131
			(specs[i] as ArenaSpec).fitness_weights = cfg.pesos
		var res: Array = await _pool.run_batch(specs)
		for r in res:
			if r is Dictionary:
				filas.append(r)
		_vista.subtitulo = "evaluacion %d/%d" % [rep + 1, REPETICIONES_EVAL]

	_cerrar_pool()
	_ocupado = false
	cfg.habilitar(true)
	m.estado = TrainingMetrics.Estado.COMPLETADO
	_mostrar_tabla(filas)
	_actualizar_botones()


func _resolver_agente() -> Array:
	if _mejor_genoma != null and _config_genoma != null:
		return [_mejor_genoma, _config_genoma]
	if not FileAccess.file_exists(RUTA_GENOMA):
		return []
	var f := FileAccess.open(RUTA_GENOMA, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("genoma") is Dictionary):
		return []
	var d: Dictionary = parsed
	var bruto: Dictionary = {}
	if d.get("config_ga") is Dictionary:
		bruto = (d["config_ga"] as Dictionary).duplicate()
	if d.get("capas_ocultas") is Array:
		bruto["capas_ocultas"] = d["capas_ocultas"]
	var config := GAConfig.from_dict(bruto)
	var genoma := Genome.from_dict(d["genoma"])
	if genoma.size() != NeuralNetwork.new(config.topology()).param_count():
		_escribir("[color=#f88]El agente guardado no encaja con su topologia.[/color]")
		return []
	return [genoma, config]


func _mostrar_tabla(filas: Array) -> void:
	if filas.is_empty():
		_escribir("[color=#f88]La evaluacion no produjo resultados.[/color]")
		return
	var tabla := BenchmarkTables.per_scenario(filas)
	var lineas: Array = ["[code]" + "%-19s %3s %3s %8s %7s %7s %6s %6s"
			% ["Escenario", "Ag", "Op", "Victoria", "Exito", "Kills", "DPS", "Vida"]]
	for t in tabla:
		var d := t as Dictionary
		lineas.append("%-19s %3d %3d %7.1f%% %7.2f %7.2f %6.1f %6.1f" % [
			str(d["escenario"]).substr(0, 19), int(d["agentes"]), int(d["oponentes"]),
			float(d["ratio_victorias"]) * 100.0, float(d["tasa_exito"]),
			float(d["kills_agente"]), float(d["dps_agente"]),
			float(d["tiempo_vida_agente_s"])])
	lineas.append("[/code]")
	_escribir("\n".join(lineas))

	var victorias := 0
	for r in filas:
		if str((r as Dictionary).get("ganador", "")) == "agente":
			victorias += 1
	_escribir("[color=#8f9]%d victorias de %d episodios (%.1f%%)[/color]"
			% [victorias, filas.size(), 100.0 * float(victorias) / float(filas.size())])

	var rec := MetricsRecorder.new()
	for t in tabla:
		rec.add(t)
	if rec.save_csv(RUTA_EVALUACION):
		_escribir("Tabla guardada en %s" % ProjectSettings.globalize_path(RUTA_EVALUACION))


# =============================================================================
# Pool, ventana y estado
# =============================================================================

func _abrir_pool() -> void:
	_acelerar(cfg.velocidad())
	_pool = SimPool.new(cfg.paralelo())
	if cfg.vitrina():
		_pool.showcase_slot = 0
	add_child(_pool)
	_vista.pool = _pool
	if _vista_grande != null and is_instance_valid(_vista_grande):
		_vista_grande.pool = _pool


func _cerrar_pool() -> void:
	# Las texturas se sueltan ANTES de liberar el pool: son ViewportTexture del
	# SubViewport que esta a punto de desaparecer.
	for v in [_vista, _vista_grande]:
		if v != null and is_instance_valid(v):
			(v as ArenaView).soltar()
			(v as ArenaView).subtitulo = ""
	if _pool != null and is_instance_valid(_pool):
		_pool.shutdown()
		_pool.queue_free()
	_pool = null
	_restaurar_velocidad()


## Acelera subiendo la FRECUENCIA de fisica, no Engine.time_scale.
##
## Misma decision que el benchmark y por el mismo motivo medido: time_scale=40 da
## una aceleracion real de x1.2 porque escala el delta pero no hace que el motor
## ejecute mas pasos. Es seguro porque la simulacion avanza con SIM_DT fijo, y
## por eso tambien se puede mover en mitad de una corrida.
func _acelerar(velocidad: int) -> void:
	Audio.enabled = false
	Engine.physics_ticks_per_second = GameConfig.TICKS_PER_SECOND * maxi(1, velocidad)
	Engine.max_physics_steps_per_frame = maxi(256, velocidad * 8)


func _restaurar_velocidad() -> void:
	Engine.physics_ticks_per_second = _ticks_fisica_previos
	Engine.max_physics_steps_per_frame = _pasos_fisica_previos
	Audio.enabled = true


## Abre la vista como ventana independiente del sistema operativo: se agranda,
## se lleva a otro monitor y se sigue el combate mientras se tocan los pesos en
## la ventana principal.
func _alternar_ventana() -> void:
	if _ventana != null and is_instance_valid(_ventana):
		_cerrar_ventana()
		return
	_ventana = Window.new()
	_ventana.title = "Smart Top Down - arena de entrenamiento"
	_ventana.size = Vector2i(1100, 760)
	_ventana.min_size = Vector2i(420, 320)
	_ventana.close_requested.connect(_cerrar_ventana)
	add_child(_ventana)

	var fondo := ColorRect.new()
	fondo.color = UI.FONDO
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ventana.add_child(fondo)

	# La ventana no es solo la imagen: lleva sus propias metricas debajo para
	# poder llevarla a otro monitor y seguir la corrida entera desde ahi, sin
	# tener que mirar a la ventana principal para saber por que generacion va.
	var caja := MarginContainer.new()
	caja.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		caja.add_theme_constant_override("margin_" + lado, 8)
	_ventana.add_child(caja)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	caja.add_child(col)

	_vista_grande = ArenaView.new()
	_vista_grande.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vista_grande.pool = _pool
	col.add_child(_vista_grande)

	_metricas_ventana = PanelMetricas.new()
	_metricas_ventana.m = m
	_metricas_ventana.custom_minimum_size = Vector2(0, 172)
	col.add_child(_metricas_ventana)

	_ventana.show()
	_b_ventana.text = "Cerrar ventana"


func _cerrar_ventana() -> void:
	if _vista_grande != null and is_instance_valid(_vista_grande):
		_vista_grande.soltar()
	_vista_grande = null
	_metricas_ventana = null
	if _ventana != null and is_instance_valid(_ventana):
		_ventana.queue_free()
	_ventana = null
	if _b_ventana != null:
		_b_ventana.text = "Ventana aparte"


func _hay_agente() -> bool:
	return _mejor_genoma != null or FileAccess.file_exists(RUTA_GENOMA)


func _actualizar_botones() -> void:
	var hay := _hay_agente()
	_b_entrenar.disabled = _ocupado
	_b_pausar.disabled = not _entrenando
	_b_detener.disabled = not _entrenando
	_b_evaluar.disabled = _ocupado or not hay
	_b_volver.disabled = _ocupado
	_b_jugar.disabled = _ocupado or not hay
	_b_jugar.text = "Jugar contra este agente" if hay \
			else "Jugar contra este agente (entrena primero)"


func _actualizar_coste() -> void:
	if _label_coste == null:
		return
	var e := cfg.estimacion()
	if int(e["episodios"]) <= 0:
		_label_coste.text = "Marca al menos una etapa del curriculum."
		return
	var v := cfg.velocidad()
	_label_coste.text = "%d episodios = %d etapas x %d gen x %d individuos x %d.  Cota alta ~%.0f min.  A x%d, 1 s real = %d s de juego%s" \
			% [int(e["episodios"]), int(e["etapas"]), int(e["generaciones"]),
			int(e["poblacion"]), int(e["episodios_ind"]), ceil(float(e["minutos"])),
			v, v, "  (baja a x2-x4 para seguir el combate)" if v > 6 else ""]


func _escribir(linea: String) -> void:
	if _log != null:
		_log.append_text(linea + "\n")


func _jugar() -> void:
	get_tree().change_scene_to_file("res://game/level_01.tscn")


## Guarda el genoma CON las heuristicas y los parametros que lo produjeron. Un
## vector de pesos suelto no dice nada seis semanas despues.
func _guardar_genoma(mejor: Genome, curriculum: Array, curva: Array) -> bool:
	var etapas: Array = []
	for e in curriculum:
		etapas.append(str(e.get("name", "")))
	var f := FileAccess.open(RUTA_GENOMA, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"genoma": mejor.to_dict(),
		"pesos_fitness": cfg.pesos.to_dict(),
		"config_ga": cfg.ga.to_dict(),
		# Las capas van aparte porque GAConfig.to_dict() solo guarda la topologia
		# como texto para el CSV. Sin ellas, un agente entrenado con otra red se
		# cargaria con un numero de pesos distinto al que espera la partida.
		"capas_ocultas": cfg.ga.hidden_layers,
		"etapas": etapas,
		"semilla": cfg.semilla(),
		"segundos_por_episodio": cfg.segundos_episodio(),
		"episodios_simulados": m.episodios_totales,
		"ticks_simulados": m.ticks_totales,
		"segundos_entrenando": m.segundos(),
		"mejor_historico": m.mejor_historico,
		"curva_convergencia": curva,
	}, "\t"))
	f.close()
	return true


# =============================================================================
# Paneles dibujados
# =============================================================================

## Rejilla de tarjetas con las metricas de la corrida. Todo lo que muestra sale
## de TrainingMetrics, que solo acumula episodios que ocurrieron de verdad.
class PanelMetricas extends Control:
	var m: TrainingMetrics

	func _draw() -> void:
		UI.caja_dibujada(self, Rect2(Vector2.ZERO, size), UI.PANEL, UI.BORDE)
		UI.texto_dibujado(self, Vector2(10, 15), "METRICAS DE LA CORRIDA",
				UI.T_PEQUENO, UI.ACENTO)
		if m == null:
			return

		var tarjetas := [
			["Etapa", "%d/%d" % [m.etapa_indice + 1, maxi(1, m.etapas_totales)], UI.TEXTO],
			["Generacion", "%d/%d" % [m.generacion + 1, maxi(1, m.generaciones_por_etapa)], UI.TEXTO],
			["Episodios", str(m.episodios_totales), UI.TEXTO],
			["Pasos simulados", _corto(m.ticks_totales), UI.TEXTO],
			["Fitness mejor", "%.2f" % m.mejor_actual, UI.EXITO],
			["Fitness medio", "%.2f" % m.medio_actual, UI.ACENTO],
			["Mejor historico", ("-" if m.mejor_historico == -INF
					else "%.2f" % m.mejor_historico), UI.EXITO],
			["Tasa de exito", "%.0f%%" % (m.tasa_victoria * 100.0), UI.VIOLETA],
			["Bajas del agente", str(m.kills_totales), UI.TEXTO],
			["Tiempo", UI.reloj(m.segundos()), UI.TEXTO],
			["Episodios/s", "%.1f" % m.episodios_por_segundo(), UI.TENUE],
			["Estado", m.nombre_estado(), m.color_estado()],
		]

		var cols := 2
		var ancho := (size.x - 20.0) / float(cols)
		for i in tarjetas.size():
			var fila := i / cols
			var c := i % cols
			var x := 10.0 + c * ancho
			var y := 30.0 + fila * 26.0
			if y + 22.0 > size.y:
				break
			UI.texto_dibujado(self, Vector2(x, y + 9), str(tarjetas[i][0]),
					UI.T_MICRO, UI.TENUE)
			UI.texto_dibujado(self, Vector2(x, y + 21), str(tarjetas[i][1]),
					UI.T_CUERPO, tarjetas[i][2])

		if m.mejor_historico != -INF:
			UI.texto_dibujado(self, Vector2(size.x - 10, size.y - 6),
					"mejor en: " + m.mejor_historico_en, UI.T_MICRO, UI.APAGADO,
					HORIZONTAL_ALIGNMENT_RIGHT)

	func _corto(n: int) -> String:
		if n >= 1_000_000:
			return "%.1fM" % (float(n) / 1_000_000.0)
		if n >= 1000:
			return "%.1fk" % (float(n) / 1000.0)
		return str(n)


## En que gasta sus decisiones el agente. Es la lectura cualitativa: un agente
## con buen fitness que pasa el 90% del tiempo huyendo no aprendio a pelear,
## aprendio a sobrevivir, y eso solo se ve aqui.
class PanelAcciones extends Control:
	var m: TrainingMetrics

	func _draw() -> void:
		UI.caja_dibujada(self, Rect2(Vector2.ZERO, size), UI.PANEL, UI.BORDE)
		UI.texto_dibujado(self, Vector2(10, 15), "EN QUE DECIDE EL AGENTE",
				UI.T_PEQUENO, UI.ACENTO)
		if m == null or m.acciones.is_empty():
			UI.texto_dibujado(self, Vector2(size.x * 0.5, size.y * 0.55),
					"sin datos todavia", UI.T_PEQUENO, UI.APAGADO,
					HORIZONTAL_ALIGNMENT_CENTER)
			return
		var y := 26.0
		for nombre in AgentActions.NAMES:
			if y + 12.0 > size.y:
				break
			var v := float(m.acciones.get(nombre, 0.0))
			UI.texto_dibujado(self, Vector2(10, y + 8), str(nombre), UI.T_MICRO, UI.TENUE)
			var bx := 86.0
			var bw: float = size.x - bx - 44.0
			draw_rect(Rect2(Vector2(bx, y), Vector2(bw, 9.0)), Color(0.16, 0.16, 0.21))
			draw_rect(Rect2(Vector2(bx, y), Vector2(bw * clampf(v, 0.0, 1.0), 9.0)),
					UI.ACENTO)
			UI.texto_dibujado(self, Vector2(size.x - 10, y + 8),
					"%d%%" % int(round(v * 100.0)), UI.T_MICRO, UI.TEXTO,
					HORIZONTAL_ALIGNMENT_RIGHT)
			y += 13.0
