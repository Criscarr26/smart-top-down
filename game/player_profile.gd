class_name PlayerProfile
extends RefCounted
## Records y estadisticas acumuladas del jugador, en user://perfil.json.
##
## Existe para que la partida tenga memoria: sin un record que batir, el modo
## oleadas es la misma partida repetida. Se guarda por nivel porque el nivel 3
## (corredores con puas) y el nivel 1 (arena abierta) no son comparables, y un
## unico record mezclaria dos cosas distintas.
##
## Se escribe al terminar cada partida, no continuamente: son cuatro campos y un
## archivo pequeno, pero escribir en cada baja seria tocar disco en pleno combate.

const RUTA := "user://perfil.json"

## {nivel: {puntos, oleada, bajas, combo, segundos}}
var records: Dictionary = {}
var partidas: int = 0
var bajas_totales: int = 0
var segundos_jugados: float = 0.0


static func cargar() -> PlayerProfile:
	var p := PlayerProfile.new()
	if not FileAccess.file_exists(RUTA):
		return p
	var f := FileAccess.open(RUTA, FileAccess.READ)
	if f == null:
		return p
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return p
	var d: Dictionary = parsed
	if d.get("records") is Dictionary:
		p.records = d["records"]
	p.partidas = int(d.get("partidas", 0))
	p.bajas_totales = int(d.get("bajas_totales", 0))
	p.segundos_jugados = float(d.get("segundos_jugados", 0.0))
	return p


func guardar() -> bool:
	var f := FileAccess.open(RUTA, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"records": records,
		"partidas": partidas,
		"bajas_totales": bajas_totales,
		"segundos_jugados": segundos_jugados,
	}, "\t"))
	f.close()
	return true


func record_de(nivel: String) -> Dictionary:
	var r = records.get(nivel, null)
	return r if r is Dictionary else {"puntos": 0, "oleada": 0, "bajas": 0,
			"combo": 0, "segundos": 0.0}


## Registra una partida. Devuelve true si batio el record de puntos del nivel.
func registrar_partida(nivel: String, puntos: int, oleada: int, bajas: int,
		combo: int, segundos: float) -> bool:
	partidas += 1
	bajas_totales += bajas
	segundos_jugados += segundos

	var previo := record_de(nivel)
	var mejoro: bool = puntos > int(previo.get("puntos", 0))
	# Cada campo guarda su propio maximo historico: batir el record de puntos no
	# deberia borrar la oleada mas lejana a la que se llego otro dia.
	records[nivel] = {
		"puntos": maxi(puntos, int(previo.get("puntos", 0))),
		"oleada": maxi(oleada, int(previo.get("oleada", 0))),
		"bajas": maxi(bajas, int(previo.get("bajas", 0))),
		"combo": maxi(combo, int(previo.get("combo", 0))),
		"segundos": maxf(segundos, float(previo.get("segundos", 0.0))),
	}
	guardar()
	return mejoro
