class_name WaveDirector
extends RefCounted
## Dirige las oleadas de la partida jugable: que aparece, cuando y cuanto.
##
## DISENO DE LA CURVA. Las cinco primeras oleadas estan escritas a mano porque
## son las que ensenan el juego, y cada una introduce exactamente UN concepto:
##   1  solo perseguidores        -> aprender a moverse y golpear
##   2  aparece la torreta        -> aprender a usar las paredes como cobertura
##   3  aparece el kiter          -> aprender a acorralar en vez de perseguir
##   4  aparece el sanador        -> aprender a priorizar objetivos
##   5  todos juntos              -> examen de lo anterior
## De la sexta en adelante la composicion se calcula con una formula, para que el
## modo no tenga final artificial. Meter al sanador en la oleada 1 seria mas
## "dificil" y peor: el jugador no tendria como saber por que no muere nadie.
##
## Avanza por TICKS de simulacion, como todo lo demas.

signal oleada_empezo(numero: int, composicion: Dictionary)
signal oleada_limpiada(numero: int)
signal cuenta_atras(ticks_restantes: int)

## Pausa entre oleadas, para leer los bonus y recolocarse.
const DESCANSO_TICKS := 210              # 3.5 s
## Techo de enemigos vivos a la vez. Por encima de ~12 el nivel deja de tener
## huecos por los que moverse y la dificultad viene del amontonamiento, no del
## diseno.
const MAX_SIMULTANEOS := 12

const OLEADAS_DISENADAS := [
	{"A": 3},
	{"A": 3, "B": 1},
	{"A": 2, "B": 1, "C": 2},
	{"A": 2, "C": 2, "D": 1},
	{"A": 3, "B": 2, "C": 2, "D": 1},
]

var arena: Arena
var oleada: int = 0
var activa: bool = false

var _ticks_descanso: int = 0
var _vivos_de_la_oleada: Array = []


func _init(p_arena: Arena) -> void:
	arena = p_arena


## Composicion de una oleada (1-indexada). Las disenadas salen de la tabla; a
## partir de ahi, formula.
static func composicion(numero: int) -> Dictionary:
	if numero <= OLEADAS_DISENADAS.size():
		return (OLEADAS_DISENADAS[numero - 1] as Dictionary).duplicate()
	var n := numero
	var out := {
		"A": 2 + int(n / 2),
		"B": maxi(1, int(n / 3)),
		"C": 1 + int(n / 4),
		"D": mini(3, 1 + int(n / 5)),
	}
	# Recorte al techo, quitando primero de los mas abundantes para no borrar la
	# variedad: una oleada de doce perseguidores es mas facil y menos
	# interesante que una de seis tipos mezclados.
	while _total(out) > MAX_SIMULTANEOS:
		var mayor := "A"
		for k in out:
			if int(out[k]) > int(out[mayor]):
				mayor = k
		out[mayor] = int(out[mayor]) - 1
		if int(out[mayor]) <= 0:
			out.erase(mayor)
	return out


static func _total(comp: Dictionary) -> int:
	var n := 0
	for k in comp:
		n += int(comp[k])
	return n


func total_de_la_oleada() -> int:
	return _total(composicion(maxi(1, oleada)))


func vivos() -> int:
	var n := 0
	for e in _vivos_de_la_oleada:
		if e != null and is_instance_valid(e) and (e as Actor).alive:
			n += 1
	return n


func empezar() -> void:
	activa = true
	oleada = 0
	_ticks_descanso = 0
	_lanzar_siguiente()


## Un tick de simulacion. Devuelve true si acaba de limpiarse una oleada.
func tick(posicion_jugador: Vector2) -> bool:
	if not activa:
		return false

	if _ticks_descanso > 0:
		_ticks_descanso -= 1
		cuenta_atras.emit(_ticks_descanso)
		if _ticks_descanso == 0:
			_lanzar_siguiente(posicion_jugador)
		return false

	if vivos() > 0:
		return false

	# Oleada limpia: se anuncia y empieza el descanso.
	oleada_limpiada.emit(oleada)
	_ticks_descanso = DESCANSO_TICKS
	return true


func _lanzar_siguiente(posicion_jugador: Vector2 = Vector2.ZERO) -> void:
	oleada += 1
	_vivos_de_la_oleada.clear()
	var comp := composicion(oleada)
	for type_id in comp:
		for _i in int(comp[type_id]):
			var e := arena.spawn_wave_enemy(str(type_id), posicion_jugador)
			if e != null:
				_vivos_de_la_oleada.append(e)
	oleada_empezo.emit(oleada, comp)


func detener() -> void:
	activa = false
	_vivos_de_la_oleada.clear()


## Descripcion corta de la composicion, para el cartel de la oleada.
static func describir(comp: Dictionary) -> String:
	var partes: Array = []
	for k in ["A", "B", "C", "D"]:
		if comp.has(k) and int(comp[k]) > 0:
			partes.append("%dx %s" % [int(comp[k]), k])
	return "  ".join(partes)
