class_name BenchmarkTables
extends RefCounted
## Agregaciones de los resultados crudos, en el formato de tabla que muestra el
## PDF del profesor (seccion 3.3.4.d).
##
## Se calculan aqui, en GDScript, y no solo en el script de Python, para que el
## Excel salga completo del propio benchmark sin depender de que alguien tenga
## pandas instalado.

## Orden de escenarios por dificultad creciente, como sugiere el PDF.
const SCENARIO_ORDER := [
	"s01_A_1v1", "s02_B_1v1", "s03_C_1v1", "s04_humano_1v1",
	"s05_A_varios", "s06_B_varios", "s07_C_varios",
	"s08_mixto_1agente", "s09_mixto_varios", "s10_humano_varios",
]


## Tabla 1: una fila por escenario, con las 4 metricas del PDF promediadas.
static func per_scenario(rows: Array) -> Array:
	var groups := _group_by(rows, "escenario")
	var out: Array = []
	for sid in _ordered_keys(groups):
		var g: Array = groups[sid]
		out.append({
			"escenario": sid,
			"descripcion": str((g[0] as Dictionary).get("escenario_label", sid)),
			"corridas": g.size(),
			"ratio_victorias": _win_rate(g),
			"tiempo_vida_agente_s": _mean(g, "tiempo_vida_agente_s"),
			"tiempo_vida_oponente_s": _mean(g, "tiempo_vida_oponente_s"),
			"dps_agente": _mean(g, "dps_agente"),
			"tasa_exito": _mean(g, "tasa_exito"),
			"kills_agente": _mean(g, "kills_agente"),
			"fitness": _mean(g, "fitness"),
		})
	return out


## Tabla 2: efecto marginal de cada variable del barrido, promediando sobre los
## 10 escenarios. Es la lectura que hace util un barrido OFAT.
static func per_variable(rows: Array) -> Array:
	var groups: Dictionary = {}
	for r in rows:
		var d := r as Dictionary
		var key := "%s=%s" % [d.get("variable_barrida", ""), d.get("valor_variable", "")]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(d)

	var out: Array = []
	for key in groups:
		var g: Array = groups[key]
		var first := g[0] as Dictionary
		out.append({
			"variable_barrida": str(first.get("variable_barrida", "")),
			"valor_variable": str(first.get("valor_variable", "")),
			"corridas": g.size(),
			"ratio_victorias": _win_rate(g),
			"tasa_exito": _mean(g, "tasa_exito"),
			"dps_agente": _mean(g, "dps_agente"),
			"tiempo_vida_agente_s": _mean(g, "tiempo_vida_agente_s"),
			"fitness": _mean(g, "fitness"),
		})
	out.sort_custom(func(a, b): return float(a["tasa_exito"]) > float(b["tasa_exito"]))
	return out


## Tabla 3: la tabla cruzada del PDF -- filas = configuracion, columnas =
## escenario, celdas = una metrica. Devuelve [columnas, filas] para pasarla
## directamente a XlsxWriter.add_sheet.
static func scenario_by_variable(rows: Array, metric: String = "tasa_exito") -> Array:
	var configs: Array = []
	var scenarios: Array = []
	var cells: Dictionary = {}

	for r in rows:
		var d := r as Dictionary
		var config := "%s=%s" % [d.get("variable_barrida", ""), d.get("valor_variable", "")]
		var scenario := str(d.get("escenario", ""))
		if not configs.has(config):
			configs.append(config)
		if not scenarios.has(scenario):
			scenarios.append(scenario)
		var key := config + "|" + scenario
		if not cells.has(key):
			cells[key] = []
		cells[key].append(float(d.get(metric, 0.0)))

	# Escenarios en orden de dificultad, no de aparicion.
	var ordered: Array = []
	for s in SCENARIO_ORDER:
		if scenarios.has(s):
			ordered.append(s)
	for s in scenarios:
		if not ordered.has(s):
			ordered.append(s)

	var columns: Array = ["configuracion"]
	columns.append_array(ordered)

	var table: Array = []
	for config in configs:
		var row: Array = [config]
		for scenario in ordered:
			var values: Array = cells.get(config + "|" + scenario, [])
			row.append(_avg(values))
		table.append(row)
	return [columns, table]


# --- Utilidades ---------------------------------------------------------------

static func _group_by(rows: Array, key: String) -> Dictionary:
	var out := {}
	for r in rows:
		var k := str((r as Dictionary).get(key, ""))
		if not out.has(k):
			out[k] = []
		out[k].append(r)
	return out


static func _ordered_keys(groups: Dictionary) -> Array:
	var out: Array = []
	for s in SCENARIO_ORDER:
		if groups.has(s):
			out.append(s)
	for k in groups:
		if not out.has(k):
			out.append(k)
	return out


static func _mean(group: Array, field: String) -> float:
	if group.is_empty():
		return 0.0
	var total := 0.0
	for r in group:
		total += float((r as Dictionary).get(field, 0.0))
	return total / float(group.size())


static func _avg(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


static func _win_rate(group: Array) -> float:
	if group.is_empty():
		return 0.0
	var wins := 0
	for r in group:
		if str((r as Dictionary).get("ganador", "")) == "agente":
			wins += 1
	return float(wins) / float(group.size())
