class_name TrainingMetrics
extends RefCounted
## Acumula lo que ocurre durante una corrida de entrenamiento.
##
## TODO sale de datos reales del Trainer: cada campo de aqui se calcula a partir
## de los episodios que se simularon de verdad. No hay ni un contador decorativo;
## si un dato no se puede medir, no aparece en el panel.
##
## Separada del Trainer a proposito: el Trainer entrena, esto observa. Asi el
## barrido del benchmark puede usar el Trainer sin arrastrar el coste de llevar
## historiales que nadie va a mirar.

enum Estado { LISTO, ENTRENANDO, PAUSADO, DETENIDO, COMPLETADO, EVALUANDO }

const NOMBRES_ESTADO := {
	Estado.LISTO: "Listo",
	Estado.ENTRENANDO: "Entrenando",
	Estado.PAUSADO: "Pausado",
	Estado.DETENIDO: "Detenido",
	Estado.COMPLETADO: "Completado",
	Estado.EVALUANDO: "Evaluando",
}

var estado: int = Estado.LISTO

# --- Posicion en el curriculum ------------------------------------------------
var etapa_indice: int = 0
var etapa_nombre: String = "-"
var etapas_totales: int = 0
var generacion: int = 0
var generaciones_por_etapa: int = 0

# --- Acumulados ---------------------------------------------------------------
var episodios_totales: int = 0
var ticks_totales: int = 0
var generaciones_totales: int = 0
var kills_totales: int = 0

# --- Fitness ------------------------------------------------------------------
var mejor_actual: float = 0.0
var medio_actual: float = 0.0
var peor_actual: float = 0.0
## Mejor fitness visto en toda la corrida, no solo en la generacion actual.
var mejor_historico: float = -INF
var mejor_historico_en: String = "-"

# --- Rendimiento --------------------------------------------------------------
var tasa_victoria: float = 0.0
var victorias_totales: int = 0

# --- Series para las graficas -------------------------------------------------
var serie_mejor: Array = []
var serie_medio: Array = []
var serie_victoria: Array = []
## Indices donde empieza una etapa nueva, para las marcas verticales.
var cortes: Array = []
## Reparto de acciones de la ultima generacion.
var acciones: Dictionary = {}
## Resumen por etapa: [{etapa, mejor, tasa_victoria, generaciones}].
var por_etapa: Array = []

var _ms_inicio: int = 0
var _ms_pausa_acumulada: int = 0
var _ms_pausa_inicio: int = 0


func iniciar(total_etapas: int, gens_por_etapa: int) -> void:
	etapas_totales = total_etapas
	generaciones_por_etapa = gens_por_etapa
	estado = Estado.ENTRENANDO
	_ms_inicio = Time.get_ticks_msec()
	_ms_pausa_acumulada = 0
	_ms_pausa_inicio = 0
	episodios_totales = 0
	ticks_totales = 0
	generaciones_totales = 0
	kills_totales = 0
	victorias_totales = 0
	mejor_historico = -INF
	mejor_historico_en = "-"
	serie_mejor.clear()
	serie_medio.clear()
	serie_victoria.clear()
	cortes.clear()
	acciones.clear()
	por_etapa.clear()


func pausar(si: bool) -> void:
	if si and estado == Estado.ENTRENANDO:
		estado = Estado.PAUSADO
		_ms_pausa_inicio = Time.get_ticks_msec()
	elif not si and estado == Estado.PAUSADO:
		estado = Estado.ENTRENANDO
		_ms_pausa_acumulada += Time.get_ticks_msec() - _ms_pausa_inicio
		_ms_pausa_inicio = 0


func terminar(detenido: bool) -> void:
	estado = Estado.DETENIDO if detenido else Estado.COMPLETADO


## Segundos de entrenamiento efectivo, descontando el tiempo en pausa.
func segundos() -> float:
	if _ms_inicio == 0:
		return 0.0
	var pausa := _ms_pausa_acumulada
	if _ms_pausa_inicio > 0:
		pausa += Time.get_ticks_msec() - _ms_pausa_inicio
	return float(Time.get_ticks_msec() - _ms_inicio - pausa) / 1000.0


func nombre_estado() -> String:
	return str(NOMBRES_ESTADO.get(estado, "?"))


func color_estado() -> Color:
	match estado:
		Estado.ENTRENANDO: return UI.ACENTO
		Estado.EVALUANDO: return UI.VIOLETA
		Estado.PAUSADO: return UI.AVISO
		Estado.COMPLETADO: return UI.EXITO
		Estado.DETENIDO: return UI.PELIGRO
	return UI.TENUE


func empezar_etapa(indice: int, nombre: String) -> void:
	etapa_indice = indice
	etapa_nombre = nombre
	if not serie_mejor.is_empty():
		cortes.append(serie_mejor.size())
	por_etapa.append({"etapa": nombre, "mejor": -INF, "victorias": 0,
			"episodios": 0, "generaciones": 0})


## Consume el diccionario que emite Trainer.generation_completed.
func registrar_generacion(stats: Dictionary) -> void:
	generacion = int(stats.get("generacion", 0))
	generaciones_totales += 1
	mejor_actual = float(stats.get("mejor", 0.0))
	medio_actual = float(stats.get("medio", 0.0))
	peor_actual = float(stats.get("peor", 0.0))
	episodios_totales += int(stats.get("episodios", 0))
	ticks_totales += int(stats.get("ticks", 0))
	kills_totales += int(stats.get("kills", 0))
	victorias_totales += int(stats.get("victorias", 0))
	tasa_victoria = float(stats.get("tasa_victoria", 0.0))

	if mejor_actual > mejor_historico:
		mejor_historico = mejor_actual
		mejor_historico_en = "%s gen %d" % [etapa_nombre, generacion + 1]

	serie_mejor.append(mejor_actual)
	serie_medio.append(medio_actual)
	serie_victoria.append(tasa_victoria)
	if stats.get("acciones") is Dictionary:
		acciones = (stats["acciones"] as Dictionary).duplicate()

	if not por_etapa.is_empty():
		var e: Dictionary = por_etapa[por_etapa.size() - 1]
		e["mejor"] = maxf(float(e["mejor"]), mejor_actual)
		e["victorias"] = int(e["victorias"]) + int(stats.get("victorias", 0))
		e["episodios"] = int(e["episodios"]) + int(stats.get("episodios", 0))
		e["generaciones"] = int(e["generaciones"]) + 1


## Fraccion de la corrida completada, para la barra de progreso.
func progreso() -> float:
	var total := etapas_totales * maxi(1, generaciones_por_etapa)
	if total <= 0:
		return 0.0
	return clampf(float(generaciones_totales) / float(total), 0.0, 1.0)


## Episodios por segundo real. Es la medida honesta de "cuanto rinde el equipo".
func episodios_por_segundo() -> float:
	var s := segundos()
	return 0.0 if s <= 0.0 else float(episodios_totales) / s
