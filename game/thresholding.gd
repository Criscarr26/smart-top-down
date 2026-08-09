class_name Thresholding
extends RefCounted
## Convierte la salida cruda de la red en UNA accion.
##
## Es la variable (viii) del benchmark cuantitativo del PDF: "tecnica de
## thresholding de la red neuronal para activar las acciones". Estan
## implementadas tres para poder compararlas, no una sola.

enum Mode {
	SOFTMAX_ARGMAX,   ## determinista: la accion de mayor probabilidad
	FIXED_THRESHOLD,  ## solo activa si supera un umbral; si no, no hace nada
	STOCHASTIC,       ## muestrea de la distribucion softmax
}

const MODE_NAMES := {
	Mode.SOFTMAX_ARGMAX: "softmax_argmax",
	Mode.FIXED_THRESHOLD: "umbral_fijo",
	Mode.STOCHASTIC: "muestreo_softmax",
}

## Accion devuelta cuando ninguna neurona supera el umbral en FIXED_THRESHOLD.
const NO_ACTION := -1


static func mode_name(mode: int) -> String:
	return MODE_NAMES.get(mode, "desconocido")


static func mode_from_name(text: String) -> int:
	for k in MODE_NAMES:
		if MODE_NAMES[k] == text:
			return k
	return Mode.SOFTMAX_ARGMAX


## Softmax numericamente estable (resta el maximo antes de exponenciar; sin eso,
## salidas de magnitud alta desbordan exp() y devuelven NaN, que en un GA se
## propaga silenciosamente y envenena la poblacion entera).
static func softmax(values: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size())
	if values.is_empty():
		return out
	var max_v := values[0]
	for v in values:
		max_v = maxf(max_v, v)
	var total := 0.0
	for i in values.size():
		var e: float = exp(values[i] - max_v)
		out[i] = e
		total += e
	if total <= 0.0:
		return out
	for i in out.size():
		out[i] = out[i] / total
	return out


## Aplica la tecnica indicada. `threshold` solo se usa en FIXED_THRESHOLD.
static func select(values: PackedFloat32Array, mode: int, threshold: float = 0.25,
		rng: RandomNumberGenerator = null) -> int:
	if values.is_empty():
		return NO_ACTION
	match mode:
		Mode.FIXED_THRESHOLD:
			return _fixed_threshold(values, threshold)
		Mode.STOCHASTIC:
			return _stochastic(values, rng)
		_:
			return _argmax(softmax(values))


static func _argmax(values: PackedFloat32Array) -> int:
	var best := 0
	for i in range(1, values.size()):
		if values[i] > values[best]:
			best = i
	return best


## Umbral fijo sobre la probabilidad softmax: la accion mas fuerte solo se
## dispara si la red esta razonablemente segura. Si ninguna llega, el agente se
## queda quieto ese ciclo. Produce agentes mas cautos que argmax puro, que
## siempre elige algo aunque las seis salidas esten empatadas.
static func _fixed_threshold(values: PackedFloat32Array, threshold: float) -> int:
	var probs := softmax(values)
	var best := _argmax(probs)
	return best if probs[best] >= threshold else NO_ACTION


## Muestreo de la distribucion softmax. Introduce exploracion en el
## comportamiento; usa el generador de la arena para no romper la
## reproducibilidad cuando se corren episodios en paralelo.
static func _stochastic(values: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var probs := softmax(values)
	var r: float = rng.randf() if rng != null else Rng.randf()
	var acc := 0.0
	for i in probs.size():
		acc += probs[i]
		if r <= acc:
			return i
	return probs.size() - 1
