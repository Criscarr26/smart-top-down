class_name NeuralNetwork
extends RefCounted
## Red feedforward densa. Los pesos NO se entrenan por retropropagacion: son el
## genoma que optimiza el algoritmo genetico, asi que la red solo necesita saber
## hacer forward.
##
## Todos los parametros (pesos + sesgos) viven en un unico PackedFloat32Array
## plano. Eso hace que cruce y mutacion sean operaciones sobre un vector, sin
## tener que recorrer estructuras anidadas.

## Tamanos de capa, de entrada a salida. Ej: [7, 10, 6].
var layer_sizes: Array = []
var params := PackedFloat32Array()

## Indice inicial de cada capa dentro de `params`, precalculado.
var _layer_offsets: Array = []
var _param_count: int = 0


func _init(sizes: Array) -> void:
	set_topology(sizes)


func set_topology(sizes: Array) -> void:
	assert(sizes.size() >= 2, "La red necesita al menos capa de entrada y de salida")
	layer_sizes = sizes.duplicate()
	_layer_offsets.clear()
	_param_count = 0
	for i in range(sizes.size() - 1):
		_layer_offsets.append(_param_count)
		var n_in: int = int(sizes[i])
		var n_out: int = int(sizes[i + 1])
		_param_count += n_in * n_out + n_out   # pesos + sesgos
	params.resize(_param_count)


func param_count() -> int:
	return _param_count


func input_size() -> int:
	return int(layer_sizes[0])


func output_size() -> int:
	return int(layer_sizes[layer_sizes.size() - 1])


func set_params(values: PackedFloat32Array) -> void:
	if values.size() != _param_count:
		push_error("NeuralNetwork: se esperaban %d parametros, llegaron %d"
				% [_param_count, values.size()])
		return
	params = values


## Propagacion hacia adelante.
##
## Activacion oculta: tanh. Se eligio sobre ReLU porque acota la salida en
## [-1, 1] y mantiene las magnitudes comparables entre capas, que es justo lo
## que pide la normalizacion de salidas ("normalizar las salidas de las
## neuronas para que las ponderaciones tengan sentido"). Con ReLU las
## activaciones pueden crecer sin techo y el algoritmo genetico acaba premiando
## genomas con pesos enormes en vez de mejores politicas.
##
## Capa de salida: lineal. La conversion a accion la hace Thresholding, que es
## una variable del benchmark y por eso no se cablea aqui.
func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
	if inputs.size() != input_size():
		push_error("NeuralNetwork: se esperaban %d entradas, llegaron %d"
				% [input_size(), inputs.size()])
		return PackedFloat32Array()

	var activations := inputs
	for layer in range(layer_sizes.size() - 1):
		var n_in: int = int(layer_sizes[layer])
		var n_out: int = int(layer_sizes[layer + 1])
		var offset: int = _layer_offsets[layer]
		var is_last: bool = layer == layer_sizes.size() - 2

		var next := PackedFloat32Array()
		next.resize(n_out)
		for j in n_out:
			var sum := 0.0
			var base := offset + j * n_in
			for i in n_in:
				sum += activations[i] * params[base + i]
			sum += params[offset + n_in * n_out + j]   # sesgo
			next[j] = sum if is_last else tanh(sum)
		activations = next
	return activations


## Indices dentro de `params` de los pesos que salen de una neurona de ENTRADA
## concreta. Los usa la mascara de congelacion que implementa la recomendacion
## la congelacion de sensores irrelevantes ("frisar la optimizacion de los sensores relacionados a
## mecanicas no relacionadas con el nivel").
func input_weight_indices(input_index: int) -> Array:
	var out: Array = []
	if layer_sizes.size() < 2 or input_index < 0 or input_index >= input_size():
		return out
	var n_in := input_size()
	var n_out: int = int(layer_sizes[1])
	var offset: int = _layer_offsets[0]
	for j in n_out:
		out.append(offset + j * n_in + input_index)
	return out


func describe() -> String:
	return "NN%s (%d params)" % [str(layer_sizes), _param_count]
