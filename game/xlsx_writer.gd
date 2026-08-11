class_name XlsxWriter
extends RefCounted
## Escritor de archivos .xlsx (Excel) nativo, sin dependencias externas.
##
## Un .xlsx es un ZIP con varios XML dentro (Office Open XML, ECMA-376). Godot
## trae ZIPPacker, asi que el benchmark deja el Excel hecho sin pasar por Python.
##
## Genera estilos de verdad: cabecera fija y en color, anchos de columna
## calculados, formato numerico por columna, autofiltro y paneles congelados.
## Sin eso, 800 filas x 42 columnas son ilegibles.
##
## Uso:
##     var w := XlsxWriter.new()
##     w.add_sheet("Datos", columnas, filas, formatos)
##     w.save("res://results/benchmark.xlsx")

const MAX_SHEET_NAME := 31

# Estilos, en el mismo orden que se declaran en cellXfs (ver _styles_xml).
enum {
	FMT_TEXT = 0,     ## texto tal cual
	FMT_HEADER = 1,   ## solo para la fila de cabecera
	FMT_DECIMAL = 2,  ## 0.00
	FMT_PERCENT = 3,  ## 0.0 %  (el valor debe venir como fraccion 0..1)
	FMT_INT = 4,      ## 0
	FMT_WRAP = 5,     ## texto con ajuste de linea, para parrafos largos
}

## Cada hoja: name, columns, rows, formats (uno por columna), widths.
var _sheets: Array = []


## `formats` lleva un FMT_* por columna. Si se omite, se deduce del primer valor
## no vacio de cada columna.
func add_sheet(sheet_name: String, columns: Array, rows: Array,
		formats: Array = [], widths: Array = []) -> void:
	var fmts: Array = formats.duplicate()
	if fmts.size() != columns.size():
		fmts = _infer_formats(columns, rows)
	# Los anchos se pueden fijar a mano: el calculo automatico se topa a 46 para
	# que una celda larga no haga una columna gigante, pero una hoja de parrafos
	# necesita justo lo contrario.
	var w: Array = widths.duplicate()
	if w.size() != columns.size():
		w = _column_widths(columns, rows)
	_sheets.append({
		"name": _sanitize_name(sheet_name),
		"columns": columns.duplicate(),
		"rows": rows,
		"formats": fmts,
		"widths": w,
	})


func add_sheet_from_dicts(sheet_name: String, records: Array,
		columns: Array = [], formats: Array = []) -> void:
	var cols: Array = columns.duplicate()
	if cols.is_empty():
		for r in records:
			for k in (r as Dictionary).keys():
				if not cols.has(k):
					cols.append(k)
	var rows: Array = []
	for r in records:
		var row: Array = []
		for c in cols:
			row.append((r as Dictionary).get(c, ""))
		rows.append(row)
	add_sheet(sheet_name, cols, rows, formats)


func save(path: String) -> bool:
	if _sheets.is_empty():
		push_error("XlsxWriter: no hay hojas que escribir")
		return false
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var packer := ZIPPacker.new()
	var err := packer.open(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("XlsxWriter: no se pudo crear %s (error %d)" % [path, err])
		return false

	_write(packer, "[Content_Types].xml", _content_types())
	_write(packer, "_rels/.rels", _root_rels())
	_write(packer, "xl/workbook.xml", _workbook())
	_write(packer, "xl/_rels/workbook.xml.rels", _workbook_rels())
	_write(packer, "xl/styles.xml", _styles_xml())
	for i in _sheets.size():
		_write(packer, "xl/worksheets/sheet%d.xml" % (i + 1), _sheet_xml(_sheets[i]))
	packer.close()
	return true


func _write(packer: ZIPPacker, entry: String, content: String) -> void:
	packer.start_file(entry)
	packer.write_file(content.to_utf8_buffer())
	packer.close_file()


# =============================================================================
# Deduccion de formato y anchos
# =============================================================================

func _infer_formats(columns: Array, rows: Array) -> Array:
	var out: Array = []
	for c in columns.size():
		var fmt := FMT_TEXT
		for r in rows:
			var row: Array = r
			if c >= row.size():
				continue
			var v: Variant = row[c]
			if typeof(v) == TYPE_INT:
				fmt = FMT_INT
				break
			if typeof(v) == TYPE_FLOAT:
				fmt = FMT_DECIMAL
				break
			if typeof(v) == TYPE_STRING and str(v) != "":
				break
		out.append(fmt)
	return out


## Ancho por columna: el mas largo entre la cabecera y una muestra de los datos.
## Solo se miran 80 filas; con 800 el coste no compensa y el resultado apenas
## cambia.
func _column_widths(columns: Array, rows: Array) -> Array:
	var out: Array = []
	for c in columns.size():
		var longest: int = str(columns[c]).length()
		var sample: int = mini(rows.size(), 80)
		for i in sample:
			var row: Array = rows[i]
			if c >= row.size():
				continue
			longest = maxi(longest, _display_length(row[c]))
		# +3 de aire; acotado para que una celda larga no haga una columna gigante.
		out.append(clampf(float(longest) + 3.0, 9.0, 46.0))
	return out


func _display_length(value: Variant) -> int:
	match typeof(value):
		TYPE_FLOAT:
			return 8
		TYPE_INT:
			return str(value).length()
		_:
			return str(value).length()


# =============================================================================
# Piezas del formato Office Open XML
# =============================================================================

func _content_types() -> String:
	var overrides := ""
	for i in _sheets.size():
		overrides += '<Override PartName="/xl/worksheets/sheet%d.xml" ' % (i + 1) \
			+ 'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
		+ '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' \
		+ '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' \
		+ '<Default Extension="xml" ContentType="application/xml"/>' \
		+ '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' \
		+ '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' \
		+ overrides + '</Types>'


func _root_rels() -> String:
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
		+ '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
		+ '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' \
		+ '</Relationships>'


func _workbook() -> String:
	var sheets := ""
	for i in _sheets.size():
		sheets += '<sheet name="%s" sheetId="%d" r:id="rId%d"/>' \
			% [_escape(_sheets[i]["name"]), i + 1, i + 1]
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
		+ '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' \
		+ 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' \
		+ '<sheets>' + sheets + '</sheets></workbook>'


func _workbook_rels() -> String:
	var rels := ""
	for i in _sheets.size():
		rels += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>' \
			% [i + 1, i + 1]
	rels += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' \
		% (_sheets.size() + 1)
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
		+ '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
		+ rels + '</Relationships>'


## Los indices de cellXfs deben coincidir con el enum FMT_* de arriba.
func _styles_xml() -> String:
	return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
		+ '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
		+ '<numFmts count="2">' \
		+ '<numFmt numFmtId="164" formatCode="0.00"/>' \
		+ '<numFmt numFmtId="165" formatCode="0.0%"/>' \
		+ '</numFmts>' \
		+ '<fonts count="2">' \
		+ '<font><sz val="11"/><color theme="1"/><name val="Calibri"/></font>' \
		+ '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>' \
		+ '</fonts>' \
		+ '<fills count="3">' \
		+ '<fill><patternFill patternType="none"/></fill>' \
		+ '<fill><patternFill patternType="gray125"/></fill>' \
		+ '<fill><patternFill patternType="solid"><fgColor rgb="FF2F5D7C"/><bgColor indexed="64"/></patternFill></fill>' \
		+ '</fills>' \
		+ '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' \
		+ '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' \
		+ '<cellXfs count="6">' \
		+ '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' \
		+ '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1">' \
		+ '<alignment horizontal="center" vertical="center" wrapText="1"/></xf>' \
		+ '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' \
		+ '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' \
		+ '<xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' \
		+ '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1">' \
		+ '<alignment vertical="top" wrapText="1"/></xf>' \
		+ '</cellXfs>' \
		+ '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>' \
		+ '</styleSheet>'


func _sheet_xml(sheet: Dictionary) -> String:
	var columns: Array = sheet["columns"]
	var rows: Array = sheet["rows"]
	var formats: Array = sheet["formats"]
	var widths: Array = sheet["widths"]
	var last_col := _column_letter(columns.size() - 1)
	var last_row: int = rows.size() + 1

	var xml := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
		+ '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
		+ '<dimension ref="A1:%s%d"/>' % [last_col, last_row]

	# Cabecera congelada: con cientos de filas, sin esto pierdes de vista que
	# columna estas mirando en cuanto bajas.
	xml += '<sheetViews><sheetView workbookViewId="0">' \
		+ '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>' \
		+ '<selection pane="bottomLeft" activeCell="A2" sqref="A2"/>' \
		+ '</sheetView></sheetViews>'
	xml += '<sheetFormatPr defaultRowHeight="15"/>'

	xml += "<cols>"
	for c in widths.size():
		xml += '<col min="%d" max="%d" width="%s" customWidth="1"/>' \
			% [c + 1, c + 1, String.num(float(widths[c]), 2)]
	xml += "</cols>"

	xml += "<sheetData>"
	xml += '<row r="1" ht="30" customHeight="1">'
	for c in columns.size():
		xml += _cell(c, 1, str(columns[c]), FMT_HEADER)
	xml += "</row>"
	for r in rows.size():
		var row: Array = rows[r]
		xml += '<row r="%d">' % (r + 2)
		for c in row.size():
			var fmt: int = formats[c] if c < formats.size() else FMT_TEXT
			xml += _cell(c, r + 2, row[c], fmt)
		xml += "</row>"
	xml += "</sheetData>"

	# Autofiltro: sin esto no se puede aislar un escenario o una configuracion.
	xml += '<autoFilter ref="A1:%s%d"/>' % [last_col, last_row]
	xml += "</worksheet>"
	return xml


func _cell(col: int, row: int, value: Variant, fmt: int) -> String:
	var ref := "%s%d" % [_column_letter(col), row]
	if fmt != FMT_HEADER:
		match typeof(value):
			TYPE_INT:
				return '<c r="%s" s="%d"><v>%d</v></c>' % [ref, fmt, value]
			TYPE_FLOAT:
				return '<c r="%s" s="%d"><v>%s</v></c>' % [ref, fmt, String.num(value, 6)]
			TYPE_BOOL:
				return '<c r="%s" s="%d" t="b"><v>%d</v></c>' % [ref, fmt, 1 if value else 0]
	var text := str(value)
	if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
		text = JSON.stringify(value)
	return '<c r="%s" s="%d" t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' \
		% [ref, fmt, _escape(text)]


static func _column_letter(index: int) -> String:
	var out := ""
	var n := maxi(0, index)
	while true:
		out = char(65 + (n % 26)) + out
		n = n / 26 - 1
		if n < 0:
			break
	return out


static func _escape(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;") \
		.replace('"', "&quot;")


static func _sanitize_name(raw: String) -> String:
	var out := raw
	for bad in [":", "\\", "/", "?", "*", "[", "]"]:
		out = out.replace(bad, "-")
	if out.length() > MAX_SHEET_NAME:
		out = out.substr(0, MAX_SHEET_NAME)
	return out if out != "" else "Hoja"
