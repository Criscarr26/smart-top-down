class_name ScoreSystem
extends RefCounted
## Puntuacion, cadena de bajas y eventos de la partida jugable.
##
## POR QUE UN MULTIPLICADOR POR CADENA. Sin el, la estrategia optima del juego es
## esconderse detras de una esquina y matar de uno en uno: lento, seguro y
## aburrido. Con una ventana de 3 segundos entre bajas, encadenar obliga a
## moverte hacia el siguiente enemigo mientras todavia te estan disparando, que
## es exactamente el riesgo que hace interesante un top-down. Es la misma idea
## que la funcion de fitness del agente: la recompensa define el juego que se
## acaba jugando.
##
## Avanza por TICKS, no por segundos del motor, igual que el resto de la
## simulacion. Asi la ventana del combo dura lo mismo pase lo que pase con la
## velocidad del motor.

signal puntos_cambiaron(total: int)
signal combo_cambio(cadena: int, multiplicador: float)
## Texto corto para que el HUD lo anuncie ("COMBO x3", "SIN DANO").
signal evento(texto: String, color: Color)

## Ventana para encadenar la siguiente baja.
const VENTANA_COMBO_TICKS := 180        # 3 s
const COMBO_MAXIMO := 8
## Cuanto suma cada eslabon al multiplicador.
const PASO_MULTIPLICADOR := 0.35

## Puntos base por tipo. El sanador vale mas que nadie a proposito: el sistema de
## puntos debe premiar la misma prioridad que premia el buen juego.
const PUNTOS_BASE := {
	"A": 100, "B": 140, "C": 120, "D": 220, "AGENT": 260, "": 80,
}

const BONUS_OLEADA_LIMPIA := 500        ## terminar una oleada sin recibir dano
const BONUS_PRECISION := 300            ## >70% de aciertos de melee en la oleada

var puntos: int = 0
var combo: int = 0
var combo_maximo: int = 0
var bajas: int = 0
## Dano recibido desde que empezo la oleada; decide el bonus de oleada limpia.
var dano_en_oleada: float = 0.0

var _ticks_combo: int = 0


func multiplicador() -> float:
	return 1.0 + float(combo) * PASO_MULTIPLICADOR


## Ticks que le quedan a la ventana, como fraccion. Alimenta la barra del HUD.
func fraccion_combo() -> float:
	if combo <= 0:
		return 0.0
	return clampf(float(_ticks_combo) / float(VENTANA_COMBO_TICKS), 0.0, 1.0)


## Un tick de simulacion. La ventana solo corre si hay cadena viva.
func tick() -> void:
	if combo <= 0:
		return
	_ticks_combo -= 1
	if _ticks_combo <= 0:
		_romper_combo()


func registrar_baja(type_id: String) -> int:
	bajas += 1
	combo = mini(COMBO_MAXIMO, combo + 1)
	combo_maximo = maxi(combo_maximo, combo)
	_ticks_combo = VENTANA_COMBO_TICKS

	var base: int = int(PUNTOS_BASE.get(type_id.to_upper(), PUNTOS_BASE[""]))
	var ganados := int(round(float(base) * multiplicador()))
	puntos += ganados
	puntos_cambiaron.emit(puntos)
	combo_cambio.emit(combo, multiplicador())
	if combo >= 2:
		evento.emit("CADENA x%d" % combo, UI.AVISO)
	return ganados


func registrar_dano(cantidad: float) -> void:
	dano_en_oleada += cantidad


## Cierra una oleada y cobra los bonus. `precision` es la fraccion de golpes de
## melee que conectaron, en 0..1.
func cerrar_oleada(precision: float) -> int:
	var extra := 0
	if dano_en_oleada <= 0.0:
		extra += BONUS_OLEADA_LIMPIA
		evento.emit("OLEADA LIMPIA  +%d" % BONUS_OLEADA_LIMPIA, UI.EXITO)
	if precision >= 0.70:
		extra += BONUS_PRECISION
		evento.emit("PRECISION %d%%  +%d" % [int(precision * 100.0), BONUS_PRECISION], UI.ACENTO)
	dano_en_oleada = 0.0
	if extra > 0:
		puntos += extra
		puntos_cambiaron.emit(puntos)
	return extra


func _romper_combo() -> void:
	if combo >= 3:
		evento.emit("cadena perdida", UI.TENUE)
	combo = 0
	_ticks_combo = 0
	combo_cambio.emit(0, 1.0)


func reiniciar() -> void:
	puntos = 0
	combo = 0
	combo_maximo = 0
	bajas = 0
	dano_en_oleada = 0.0
	_ticks_combo = 0
