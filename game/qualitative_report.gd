class_name QualitativeReport
extends RefCounted
## Genera el benchmark CUALITATIVO (seccion 3.3.3 del PDF) a partir de los datos
## del cuantitativo.
##
## No sustituye al analisis escrito a mano: produce las observaciones que se
## deducen directamente de los numeros ("contra el Tipo C el agente huyo mas que
## contra el Tipo A") para que el informe parta de hechos medidos y no de
## impresiones.


static func generate(rows: Array, bot_scenarios: Array = []) -> String:
	if rows.is_empty():
		return "# Benchmark cualitativo\n\nNo hay datos.\n"

	var by_scenario := _group_by(rows, "escenario")
	var lines: Array = []
	lines.append("# Benchmark cualitativo del agente entrenado")
	lines.append("")
	lines.append("Generado automaticamente a partir de %d corridas registradas." % rows.size())
	lines.append("")

	# --- Tabla resumen por escenario -----------------------------------------
	lines.append("## Resumen por escenario")
	lines.append("")
	lines.append("| Escenario | Corridas | Victorias agente | Vida agente (s) | DPS agente | Tasa de exito |")
	lines.append("|---|---|---|---|---|---|")
	var ordered_ids: Array = by_scenario.keys()
	ordered_ids.sort()
	for sid in ordered_ids:
		var group: Array = by_scenario[sid]
		var label := str((group[0] as Dictionary).get("escenario_label", sid))
		lines.append("| %s | %d | %.0f%% | %.1f | %.1f | %.2f |" % [
			label, group.size(),
			_win_rate(group) * 100.0,
			_mean(group, "tiempo_vida_agente_s"),
			_mean(group, "dps_agente"),
			_mean(group, "tasa_exito"),
		])
	lines.append("")

	# --- Observaciones deducidas de los datos --------------------------------
	lines.append("## Observaciones")
	lines.append("")
	for obs in _observations(by_scenario):
		lines.append("- %s" % obs)
	lines.append("")

	# --- Limitaciones ---------------------------------------------------------
	lines.append("## Limitaciones conocidas")
	lines.append("")
	for lim in limitations(bot_scenarios):
		lines.append("- %s" % lim)
	lines.append("")
	return "\n".join(lines)


## Observaciones deducidas de los datos, como lista.
##
## Publica para que el Excel y el informe en Markdown salgan de la MISMA fuente.
## Si el Excel reprodujera el texto por su cuenta, los dos entregables podrian
## acabar diciendo cosas distintas sobre la misma corrida.
static func observations(rows: Array) -> Array:
	if rows.is_empty():
		return []
	return _observations(_group_by(rows, "escenario"))


## Limitaciones metodologicas, como lista.
static func limitations(bot_scenarios: Array = []) -> Array:
	var ids: Array = bot_scenarios if not bot_scenarios.is_empty() \
			else ScenarioCatalog.bot_substituted_ids()
	return [
		"Los escenarios con \"jugador humano\" (%s) se corrieron contra el bot " % ", ".join(ids)
			+ "sustituto `ScriptedBot`, no contra una persona. Un humano no puede meterse en "
			+ "un barrido automatizado de miles de partidas. Estos resultados miden al agente "
			+ "frente a un oponente HUMANO-SIMULADO de reglas fijas y deben reportarse como "
			+ "tales; complementarlos con partidas manuales contra humano real.",
		"El barrido de variables es OFAT (una variable a la vez desde una configuracion base), "
			+ "no factorial completo. Mide efectos marginales; no detecta interacciones entre "
			+ "variables.",
		"El agente recibe distancia y angulo al objetivo aunque no lo vea; la oclusion va "
			+ "aparte en el sensor de linea de vision. Es la lista de sensores que fija el PDF, "
			+ "pero implica que el agente no tiene que resolver busqueda con informacion parcial.",
	]


## Por debajo de esta fraccion de decisiones, una accion se considera anecdotica
## y no se compara con otra: los cocientes entre numeros casi nulos disparan
## conclusiones falsas.
const _MIN_RELEVANT_SHARE := 0.02


static func _observations(by_scenario: Dictionary) -> Array:
	var obs: Array = []

	# Comparacion de la tasa de huida entre tipos de enemigo.
	var flee_a := _mean_action(by_scenario, "s01_A_1v1", "Huir")
	var flee_c := _mean_action(by_scenario, "s03_C_1v1", "Huir")
	if flee_a >= 0.0 and flee_c >= 0.0:
		# Comparar en proporcion cuando los dos valores son casi cero produce
		# frases sin sentido del tipo "huyo mas del Tipo A (0%) que del Tipo C
		# (0%)": una diferencia entre 0.4% y 0.1% es del triple en proporcion,
		# pero no significa nada. Por debajo de este umbral no se compara.
		if flee_a < _MIN_RELEVANT_SHARE and flee_c < _MIN_RELEVANT_SHARE:
			obs.append("El agente practicamente no uso la huida en los duelos 1v1 "
					+ "(%.1f%% contra el Tipo A y %.1f%% contra el Tipo C de sus decisiones): "
					% [flee_a * 100.0, flee_c * 100.0]
					+ "su politica es plantarse y pelear, sin importar el tipo de rival.")
		elif flee_c > flee_a * 1.15:
			obs.append("Contra el enemigo Tipo C el agente huyo mas que contra el Tipo A "
					+ "(%.0f%% vs %.0f%% de sus decisiones): el kiter lo obliga a ceder "
					% [flee_c * 100.0, flee_a * 100.0]
					+ "distancia, mientras que contra el perseguidor melee le conviene plantarse.")
		elif flee_a > flee_c * 1.15:
			obs.append("El agente huyo mas del Tipo A (%.0f%%) que del Tipo C (%.0f%%), "
					% [flee_a * 100.0, flee_c * 100.0]
					+ "lo que sugiere que aprendio a evitar el combate cuerpo a cuerpo.")
		else:
			obs.append("La tasa de huida es similar contra Tipo A y Tipo C (%.0f%% vs %.0f%%): "
					% [flee_a * 100.0, flee_c * 100.0]
					+ "el agente no diferencia su politica segun el tipo de rival.")

	# Uso de la defensa contra el Tipo B.
	var defend_b := _mean_action(by_scenario, "s02_B_1v1", "Defender")
	if defend_b >= 0.0:
		if defend_b > 0.15:
			obs.append("Frente al Tipo B (torreta) el agente dedico el %.0f%% de sus decisiones "
					% (defend_b * 100.0)
					+ "a defender, aprovechando el escudo contra el fuego a distancia.")
		else:
			obs.append("El agente apenas uso la defensa contra el Tipo B (%.0f%%): "
					% (defend_b * 100.0)
					+ "prefirio cerrar distancia antes que bloquear proyectiles.")

	# Victorias sin merito: gana pero no hace dano.
	#
	# Este chequeo existe porque paso de verdad en las primeras corridas: el
	# agente marcaba 100% de victorias contra el Tipo A con 0.0 de DPS. No
	# estaba ganando -- el enemigo se mataba solo contra una pua mientras lo
	# perseguia. Sin este aviso, la tabla de victorias se lee como exito del
	# agente y la conclusion del informe seria falsa.
	for sid in by_scenario:
		var group: Array = by_scenario[sid]
		var wr := _win_rate(group)
		var dps := _mean(group, "dps_agente")
		var kills := _mean(group, "kills_agente")
		if wr >= 0.5 and dps < 1.0 and kills < 0.25:
			var label := str((group[0] as Dictionary).get("escenario_label", sid))
			obs.append("AVISO en \"%s\": el agente gana el %.0f%% de las partidas pero su "
					% [label, wr * 100.0]
					+ "DPS es %.1f y mata %.2f oponentes de media. Esas victorias NO son "
					% [dps, kills]
					+ "suyas: los oponentes estan muriendo en las puas del nivel. No "
					+ "interpretar esta fila como desempeno del agente.")

	# Efecto de aumentar el numero de oponentes.
	var solo := _mean_over(by_scenario, ["s01_A_1v1", "s02_B_1v1", "s03_C_1v1"], "tasa_exito")
	var many := _mean_over(by_scenario, ["s05_A_varios", "s06_B_varios", "s07_C_varios"], "tasa_exito")
	if solo >= 0.0 and many >= 0.0:
		var verb := "cae" if many < solo else ("sube" if many > solo else "se mantiene")
		obs.append("La tasa de exito %s de %.2f en los duelos 1v1 a %.2f contra varios "
				% [verb, solo, many]
				+ "oponentes, que es la prueba de estres que pide la seccion 3.3.2 del PDF.")

	# Ventaja de jugar en grupo.
	var one_agent := _mean_over(by_scenario, ["s08_mixto_1agente"], "tasa_exito")
	var many_agents := _mean_over(by_scenario, ["s09_mixto_varios"], "tasa_exito")
	if one_agent >= 0.0 and many_agents >= 0.0:
		var verb := "mejora" if many_agents > one_agent else "empeora"
		obs.append("Con varios agentes contra el grupo mixto la tasa de exito %s "
				% verb + "(%.2f vs %.2f con un solo agente)." % [many_agents, one_agent])

	# Escenario mas dificil.
	var worst_id := ""
	var worst_rate := 2.0
	for sid in by_scenario:
		var wr := _win_rate(by_scenario[sid])
		if wr < worst_rate:
			worst_rate = wr
			worst_id = str(sid)
	if worst_id != "":
		var label := str((by_scenario[worst_id][0] as Dictionary).get("escenario_label", worst_id))
		obs.append("El escenario mas duro fue \"%s\", con %.0f%% de victorias del agente."
				% [label, worst_rate * 100.0])

	# Inactividad (thresholding por umbral).
	var idle_total := 0.0
	var idle_n := 0
	for sid in by_scenario:
		for r in by_scenario[sid]:
			idle_total += float((r as Dictionary).get("ticks_inactivo", 0))
			idle_n += 1
	if idle_n > 0 and idle_total / float(idle_n) > 60.0:
		obs.append("El agente paso una media de %.0f ticks por episodio sin activar ninguna "
				% (idle_total / float(idle_n))
				+ "accion. Es sintoma de un umbral de thresholding demasiado alto: la red "
				+ "no alcanza la confianza minima y el agente se queda inmovil.")

	return obs


# --- Utilidades estadisticas --------------------------------------------------

static func _group_by(rows: Array, key: String) -> Dictionary:
	var out := {}
	for r in rows:
		var k := str((r as Dictionary).get(key, ""))
		if not out.has(k):
			out[k] = []
		out[k].append(r)
	return out


static func _mean(group: Array, field: String) -> float:
	if group.is_empty():
		return 0.0
	var total := 0.0
	for r in group:
		total += float((r as Dictionary).get(field, 0.0))
	return total / float(group.size())


static func _mean_over(by_scenario: Dictionary, ids: Array, field: String) -> float:
	var total := 0.0
	var n := 0
	for sid in ids:
		if not by_scenario.has(sid):
			continue
		for r in by_scenario[sid]:
			total += float((r as Dictionary).get(field, 0.0))
			n += 1
	return -1.0 if n == 0 else total / float(n)


static func _win_rate(group: Array) -> float:
	if group.is_empty():
		return 0.0
	var wins := 0
	for r in group:
		if str((r as Dictionary).get("ganador", "")) == "agente":
			wins += 1
	return float(wins) / float(group.size())


## Fraccion media de decisiones dedicadas a una accion en un escenario.
## Devuelve -1 si no hay datos.
static func _mean_action(by_scenario: Dictionary, scenario_id: String, action: String) -> float:
	if not by_scenario.has(scenario_id):
		return -1.0
	var total := 0.0
	var n := 0
	for r in by_scenario[scenario_id]:
		var mix = (r as Dictionary).get("mezcla_acciones", null)
		if mix is Dictionary and mix.has(action):
			total += float(mix[action])
			n += 1
	return -1.0 if n == 0 else total / float(n)
