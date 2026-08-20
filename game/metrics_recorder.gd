class_name MetricsRecorder
extends RefCounted
## Acumula filas de resultados y las escribe a CSV y JSON.
##
## Regla del harness: NADA se registra
## solo por consola. Cada corrida acaba en un archivo estructurado con su
## escenario, su configuracion completa y sus 4 metricas, listo para pandas o
## Excel sin post-proceso manual.

var rows: Array = []
## Orden de columnas: primera aparicion. Mantiene el CSV legible en vez de
## alfabetico, que separaria las metricas de su contexto.
var _columns: Array = []


func add(row: Dictionary) -> void:
	for key in row.keys():
		if not _columns.has(key):
			_columns.append(key)
	rows.append(row)


func size() -> int:
	return rows.size()


func clear() -> void:
	rows.clear()
	_columns.clear()


## Sustituye las filas por otras ya transformadas, recalculando las columnas.
## Lo usa el runner para repartir la mezcla de acciones en columnas sueltas
## antes de escribir, de modo que CSV, JSON y Excel salgan con la misma forma.
func replace_rows(new_rows: Array) -> void:
	clear()
	for r in new_rows:
		add(r)


func save_csv(path: String) -> bool:
	_ensure_dir(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MetricsRecorder: no se pudo escribir %s (%s)"
				% [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_line(",".join(_columns.map(func(c: String) -> String: return _escape(c))))
	for r in rows:
		var cells: Array = []
		for col in _columns:
			cells.append(_escape(_stringify((r as Dictionary).get(col, ""))))
		f.store_line(",".join(cells))
	f.close()
	return true


func save_json(path: String) -> bool:
	_ensure_dir(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MetricsRecorder: no se pudo escribir %s" % path)
		return false
	f.store_string(JSON.stringify(rows, "  "))
	f.close()
	return true


## Guarda un array de diccionarios arbitrario (curvas de convergencia, resumen
## por etapa, genoma...).
static func save_rows(path: String, data: Variant) -> bool:
	_ensure_dir_static(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MetricsRecorder: no se pudo escribir %s" % path)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


static func save_text(path: String, text: String) -> bool:
	_ensure_dir_static(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MetricsRecorder: no se pudo escribir %s" % path)
		return false
	f.store_string(text)
	f.close()
	return true


func _ensure_dir(path: String) -> void:
	_ensure_dir_static(path)


static func _ensure_dir_static(path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


static func _stringify(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT:
			# 4 decimales: suficiente para las metricas y evita que el CSV se
			# llene de ruido de coma flotante.
			return "%.4f" % (value as float)
		TYPE_DICTIONARY, TYPE_ARRAY:
			return JSON.stringify(value)
		TYPE_BOOL:
			return "true" if value else "false"
		_:
			return str(value)


static func _escape(text: String) -> String:
	if text.contains(",") or text.contains("\"") or text.contains("\n"):
		return "\"%s\"" % text.replace("\"", "\"\"")
	return text
