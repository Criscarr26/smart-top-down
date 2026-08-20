extends Node
## Punto de entrada UNICO de toda la bateria de pruebas. Entrena, evalua los 10 escenarios sobre la matriz de
## configuraciones, y deja CSV + JSON + informe cualitativo. Sin intervencion
## manual entre corridas.
##
## Uso:
##   godot --headless --path . res://game/benchmark_runner.tscn -- [opciones]
##
## Opciones:
##   --quick             matriz reducida y pocas generaciones (prueba de humo)
##   --repeats N         repeticiones por escenario (por defecto 5)
##   --parallel N        arenas simultaneas (por defecto 8)
##   --speed N           Engine.time_scale (por defecto 20)
##   --generations N     fuerza el numero de generaciones de todas las configs
##   --population N      fuerza el tamano de poblacion de todas las configs
##   --seed N            semilla base (por defecto 20260408)
##   --out RUTA          carpeta de salida (por defecto res://results)
##   --only-eval         omite el entrenamiento y evalua con pesos aleatorios
##                       (util para validar el harness sin gastar tiempo)

const DEFAULT_OUT := "res://results"

var repeats: int = 5
## 16 salio como el mejor punto medido en este equipo: por debajo se
## desaprovecha el paso de fisica, por encima de ~32 el rendimiento agregado
## empieza a caer. Vuelve a medirlo en tu maquina con probe_throughput.tscn.
var parallel: int = 16
var speed: float = 60.0
var base_seed: int = 20260408
var out_dir: String = DEFAULT_OUT
var quick: bool = false
var only_eval: bool = false
## Regenera el Excel y el informe desde un benchmark.json ya existente, sin
## volver a entrenar. Util cuando cambia el formato de salida y repetir la
## corrida costaria horas.
var rebuild_only: bool = false
var force_generations: int = -1
var force_population: int = -1

var _pool: SimPool
var _recorder := MetricsRecorder.new()
var _start_ms: int = 0


func _ready() -> void:
	_parse_args()
	_start_ms = Time.get_ticks_msec()

	if rebuild_only:
		_rebuild_from_json()
		get_tree().quit()
		return

	_apply_acceleration()

	_pool = SimPool.new(parallel)
	add_child(_pool)

	print("=".repeat(70))
	print("BENCHMARK SMART TOP DOWN")
	print("  repeticiones=%d  paralelo=%d  aceleracion=x%.0f (%d ticks/s)  semilla=%d"
			% [repeats, parallel, speed, Engine.physics_ticks_per_second, base_seed])
	print("  salida=%s%s" % [out_dir, "  [MODO RAPIDO]" if quick else ""])
	print("=".repeat(70))

	var matrix: Array = ExperimentMatrix.quick() if quick else ExperimentMatrix.ofat()
	_apply_overrides(matrix)

	for i in matrix.size():
		await _run_configuration(matrix[i], i, matrix.size())

	_write_outputs()
	print("\nListo en %.1f s. %d filas registradas."
			% [(Time.get_ticks_msec() - _start_ms) / 1000.0, _recorder.size()])
	_pool.shutdown()
	get_tree().quit()


## Acelera la simulacion subiendo la FRECUENCIA de physics, no Engine.time_scale.
##
## Se midio: time_scale=40 da una aceleracion real de x1.2. En Godot 4,
## time_scale escala el delta que reciben _process/_physics_process, pero no
## hace que el motor ejecute mas pasos de fisica por segundo real, que es lo que
## aqui hace falta. Subir physics_ticks_per_second si multiplica los pasos.
##
## Es seguro precisamente por la decision de GameConfig: la simulacion avanza
## con SIM_DT fijo (1/60) e ignora el delta del motor, asi que 3600 pasos por
## segundo real siguen representando 60 segundos de juego por segundo real, con
## resultados identicos a velocidad normal. Si la logica usara el delta del
## motor, esto cambiaria la fisica del juego.
func _apply_acceleration() -> void:
	# Sin sonido en el barrido: son decenas de miles de episodios en headless y
	# cada disparo intentaria reproducir un efecto.
	Audio.enabled = false
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = int(GameConfig.TICKS_PER_SECOND * speed)
	# Permite rafagas grandes de pasos por frame; sin esto el motor descarta
	# tiempo acumulado y la aceleracion se queda muy por debajo de lo pedido.
	Engine.max_physics_steps_per_frame = maxi(256, int(speed) * 8)


func _run_configuration(entry: Dictionary, index: int, total: int) -> void:
	var config: GAConfig = entry["config"]
	var variable := str(entry["variable"])
	var value := str(entry["valor"])
	var tag := "%s=%s" % [variable, value]

	print("\n[%d/%d] Configuracion %s  (%s)" % [index + 1, total, tag, config.label()])

	# Misma semilla base para todas las configuraciones: la diferencia entre
	# ellas debe venir de la variable barrida, no de haber tenido mas suerte.
	Rng.reseed(base_seed)

	var best: Genome = null
	if only_eval:
		var net := NeuralNetwork.new(config.topology())
		best = Genome.create(net.param_count(), config.init_mode, config.init_scale)
		print("  (--only-eval: pesos aleatorios, sin entrenar)")
	else:
		var trainer := Trainer.new(config, _pool)
		add_child(trainer)
		best = await trainer.train()
		MetricsRecorder.save_rows(
				"%s/convergencia_%s_%s.json" % [out_dir, variable, value],
				trainer.convergence_curve())
		MetricsRecorder.save_rows(
				"%s/genoma_%s_%s.json" % [out_dir, variable, value],
				best.to_dict())
		trainer.queue_free()
		print("  Entrenamiento terminado. Fitness del mejor: %.2f" % best.fitness)

	await _evaluate(config, best, variable, value)


## Corre los 10 escenarios x N repeticiones para una configuracion.
func _evaluate(config: GAConfig, genome: Genome, variable: String, value: String) -> void:
	var config_columns := config.to_dict()
	for rep in repeats:
		var specs := ScenarioCatalog.all(config, genome)
		for s_index in specs.size():
			var s: ArenaSpec = specs[s_index]
			# La semilla incluye la repeticion y el escenario: repeticiones
			# distintas dan partidas distintas, pero la corrida entera se
			# reproduce exactamente con la misma --seed.
			s.seed = base_seed + rep * 7919 + s_index * 131
		var results: Array = await _pool.run_batch(specs)
		for r in results:
			if r == null or not (r is Dictionary):
				continue
			var row: Dictionary = {
				"variable_barrida": variable,
				"valor_variable": value,
				"repeticion": rep,
			}
			row.merge(config_columns)
			row.merge(r as Dictionary)
			_recorder.add(row)
		print("  repeticion %d/%d completada (%d escenarios)" % [rep + 1, repeats, results.size()])


func _write_outputs() -> void:
	# La mezcla de acciones se reparte en columnas ANTES de guardar nada, para
	# que el CSV, el JSON y el Excel tengan la misma forma. Cuando el CSV
	# guardaba un JSON dentro de una celda y el Excel columnas sueltas, verificar
	# en el CSV una observacion del informe obligaba a parsear a mano.
	var expandidas := _expand_action_mix(_recorder.rows)
	_recorder.replace_rows(expandidas)

	_recorder.save_csv("%s/benchmark.csv" % out_dir)
	_recorder.save_json("%s/benchmark.json" % out_dir)
	var report := QualitativeReport.generate(_recorder.rows)
	MetricsRecorder.save_text("%s/benchmark_cualitativo.md" % out_dir, report)
	_write_xlsx()
	print("\nArchivos escritos:")
	print("  %s/benchmark.csv" % out_dir)
	print("  %s/benchmark.json" % out_dir)
	print("  %s/benchmark.xlsx" % out_dir)
	print("  %s/benchmark_cualitativo.md" % out_dir)


## Columnas que se muestran como porcentaje (el valor viaja como fraccion 0..1).
const PERCENT_COLUMNS := [
	"tasa_exito", "ratio_victorias", "tasa_seleccion", "tasa_mutacion",
]
## Columnas que son cuentas enteras. Se declaran porque al releer desde JSON
## todo numero vuelve como float y "repeticion 0.00" se ve mal.
const INT_COLUMNS := [
	"repeticion", "num_pobladores", "generaciones", "elite", "corridas",
	"episodios_por_individuo", "tam_torneo", "semilla", "ticks",
	"kills_agente", "pociones_agente", "agentes_vivos", "oponentes_vivos",
	"oponentes_total", "ticks_inactivo", "ticks_en_combate",
	"agentes_total", "agentes", "oponentes",
]


## Excel de cuatro hojas, con estilos, listo para el informe.
func _write_xlsx() -> void:
	var w := XlsxWriter.new()
	_add_sheet(w, "Datos", _recorder.rows)
	_add_sheet(w, "Resumen por escenario", BenchmarkTables.per_scenario(_recorder.rows))
	_add_sheet(w, "Efecto de variables", BenchmarkTables.per_variable(_recorder.rows))

	# Hoja 4: la tabla cruzada escenario x configuracion.
	var cross := BenchmarkTables.scenario_by_variable(_recorder.rows, "tasa_exito")
	var cross_fmt: Array = [XlsxWriter.FMT_TEXT]
	for i in range(1, (cross[0] as Array).size()):
		cross_fmt.append(XlsxWriter.FMT_PERCENT)
	w.add_sheet("Escenario x variable", cross[0], cross[1], cross_fmt)

	# Hoja 5: el informe cualitativo. Va dentro del Excel y no solo suelto en un
	# .md para que el entregable sea UN archivo: quien abra el libro encuentra
	# ahi mismo la lectura de los numeros que acaba de ver.
	_add_qualitative_sheet(w)

	if not w.save("%s/benchmark.xlsx" % out_dir):
		push_warning("No se pudo escribir el Excel; el CSV si esta.")


## Las observaciones y las limitaciones salen de QualitativeReport, la misma
## fuente que genera el .md. Si el Excel las reprodujera por su cuenta, los dos
## entregables podrian acabar diciendo cosas distintas de la misma corrida.
func _add_qualitative_sheet(w: XlsxWriter) -> void:
	var rows: Array = []
	for obs in QualitativeReport.observations(_recorder.rows):
		rows.append(["Observación", str(obs)])
	for lim in QualitativeReport.limitations():
		rows.append(["Limitación conocida", str(lim)])
	if rows.is_empty():
		return
	w.add_sheet(
		"Cualitativo",
		["Tipo", "Detalle"],
		rows,
		[XlsxWriter.FMT_TEXT, XlsxWriter.FMT_WRAP],
		[22.0, 110.0],
	)


## Convierte una lista de diccionarios en hoja, con los formatos por columna.
func _add_sheet(w: XlsxWriter, sheet_name: String, records: Array) -> void:
	if records.is_empty():
		return
	var cols: Array = []
	for r in records:
		for k in (r as Dictionary).keys():
			if not cols.has(k):
				cols.append(k)
	var rows: Array = []
	for r in records:
		var row: Array = []
		for c in cols:
			row.append(_coerce(str(c), (r as Dictionary).get(c, "")))
		rows.append(row)
	w.add_sheet(sheet_name, cols, rows, _formats_for(cols, rows))


func _coerce(column: String, value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and INT_COLUMNS.has(column):
		return int(round(value))
	return value


func _formats_for(columns: Array, rows: Array) -> Array:
	var out: Array = []
	for c in columns.size():
		var name := str(columns[c])
		if name.begins_with("acc_") or PERCENT_COLUMNS.has(name):
			out.append(XlsxWriter.FMT_PERCENT)
			continue
		var fmt := XlsxWriter.FMT_TEXT
		for r in rows:
			var row: Array = r
			if c >= row.size():
				continue
			match typeof(row[c]):
				TYPE_INT:
					fmt = XlsxWriter.FMT_INT
				TYPE_FLOAT:
					fmt = XlsxWriter.FMT_DECIMAL
				_:
					if str(row[c]) == "":
						continue
			break
		out.append(fmt)
	return out


## Saca `mezcla_acciones` de su celda JSON y la reparte en una columna por
## accion. Un diccionario serializado dentro de una celda no se puede ordenar,
## filtrar ni graficar; en columnas si.
func _expand_action_mix(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var src := (r as Dictionary).duplicate()
		var mix = src.get("mezcla_acciones", null)
		src.erase("mezcla_acciones")
		if mix is Dictionary:
			for action in AgentActions.NAMES:
				src["acc_" + str(action)] = float((mix as Dictionary).get(action, 0.0))
		out.append(src)
	return out


## Recarga las filas de un benchmark.json anterior y reescribe las salidas.
func _rebuild_from_json() -> void:
	var path := "%s/benchmark.json" % out_dir
	if not FileAccess.file_exists(path):
		push_error("No existe %s; no hay nada que regenerar." % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		push_error("%s no contiene un array de resultados." % path)
		return
	for row in parsed:
		if row is Dictionary:
			_recorder.add(row)
	print("Regenerando salidas desde %d filas de %s" % [_recorder.size(), path])
	_write_outputs()


func _apply_overrides(matrix: Array) -> void:
	if force_generations <= 0 and force_population <= 0:
		return
	for entry in matrix:
		var c: GAConfig = entry["config"]
		if force_generations > 0:
			c.generations = force_generations
		# No pisa la poblacion en la propia variante que barre poblacion: seria
		# anular el experimento.
		if force_population > 0 and str(entry["variable"]) != "num_pobladores":
			c.population_size = force_population


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		match a:
			"--quick": quick = true
			"--only-eval": only_eval = true
			"--rebuild-xlsx": rebuild_only = true
			"--repeats":
				i += 1; repeats = maxi(1, int(args[i]))
			"--parallel":
				i += 1; parallel = maxi(1, int(args[i]))
			"--speed":
				i += 1; speed = maxf(1.0, float(args[i]))
			"--generations":
				i += 1; force_generations = int(args[i])
			"--population":
				i += 1; force_population = int(args[i])
			"--seed":
				i += 1; base_seed = int(args[i])
			"--out":
				i += 1; out_dir = str(args[i])
			_:
				if a.begins_with("--"):
					push_warning("Opcion desconocida: %s" % a)
		i += 1
	if quick:
		repeats = mini(repeats, 2)
