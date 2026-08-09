class_name SimPool
extends Node
## Ejecuta lotes de episodios en paralelo.
##
## Cada ranura es un SubViewport con su PROPIO World2D. Eso es lo que da a cada
## arena un espacio de fisica aislado: sin ello, los raycast y las consultas de
## forma de una arena verian los cuerpos de las otras y todos los combates se
## contaminarian entre si. Es el mecanismo que hace viable el barrido completo
## del benchmark: N combates avanzan por cada tick del motor en vez de uno.
##
## No usa hilos. Godot no permite tocar el arbol de escena desde hilos
## secundarios, asi que el paralelismo aqui es de simulacion (N mundos por
## tick), no de CPU. Para escalar mas alla se lanzan varios procesos de Godot.

signal batch_finished(results: Array)
signal episode_completed(index: int, result: Dictionary)

var max_parallel: int = 8

var _slots: Array = []
var _queue: Array = []
var _results: Array = []
var _next_index: int = 0
var _pending: int = 0
var _running: bool = false


func _init(p_max_parallel: int = 8) -> void:
	max_parallel = maxi(1, p_max_parallel)
	name = "SimPool"


## Corre todos los specs y devuelve los resultados EN EL MISMO ORDEN.
## Uso: `var results: Array = await pool.run_batch(specs)`
func run_batch(specs: Array) -> Array:
	if _running:
		push_error("SimPool: ya hay un lote en curso")
		return []
	_queue = specs.duplicate()
	_results.clear()
	_results.resize(specs.size())
	_next_index = 0
	_pending = specs.size()
	_running = true

	if specs.is_empty():
		_running = false
		# Emision diferida para que el await del llamante ya este enganchado.
		call_deferred("emit_signal", "batch_finished", [])
		return await batch_finished

	_ensure_slots(mini(max_parallel, specs.size()))
	for slot in _slots:
		_try_start(slot)
	return await batch_finished


func _ensure_slots(count: int) -> void:
	while _slots.size() < count:
		var vp := SubViewport.new()
		# World2D propio = espacio de fisica aislado.
		vp.world_2d = World2D.new()
		vp.size = Vector2i(1, 1)
		vp.disable_3d = true
		vp.physics_object_picking = false
		# Nada que renderizar: el benchmark solo necesita la simulacion.
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		_slots.append({"viewport": vp, "arena": null, "index": -1, "busy": false})


func _try_start(slot: Dictionary) -> void:
	if slot["busy"] or _queue.is_empty():
		return
	var spec: ArenaSpec = _queue.pop_front()
	var index: int = _next_index
	_next_index += 1

	var arena := Arena.new()
	arena.name = "Arena_%d" % index
	slot["viewport"].add_child(arena)
	slot["arena"] = arena
	slot["index"] = index
	slot["busy"] = true

	arena.episode_finished.connect(_on_episode_finished.bind(slot), CONNECT_ONE_SHOT)
	arena.setup(spec, false)


func _on_episode_finished(result: Dictionary, slot: Dictionary) -> void:
	var index: int = slot["index"]
	_results[index] = result
	episode_completed.emit(index, result)

	var arena: Arena = slot["arena"]
	slot["arena"] = null
	slot["busy"] = false
	if arena != null and is_instance_valid(arena):
		# remove_child INMEDIATO antes de liberar, no solo queue_free().
		#
		# queue_free() borra al final del frame, pero _try_start del siguiente
		# episodio corre antes (la cola de mensajes diferidos se vacia antes que
		# la de borrado). Con solo queue_free, la arena nueva se anadia al mismo
		# SubViewport mientras la vieja seguia dentro, y durante un tick los dos
		# combates compartian espacio de fisica: los raycast del episodio nuevo
		# golpeaban paredes y cuerpos del anterior. Sacarla del arbol ya la
		# desregistra del World2D.
		arena.dispose()
		slot["viewport"].remove_child(arena)
		arena.queue_free()

	_pending -= 1
	if _pending <= 0:
		_running = false
		# Diferido: dejar que el queue_free de la ultima arena se procese antes
		# de que el llamante monte el siguiente lote.
		call_deferred("emit_signal", "batch_finished", _results.duplicate())
		return
	# La ranura queda libre; arranca el siguiente spec en cuanto se limpie.
	call_deferred("_try_start", slot)


func shutdown() -> void:
	for slot in _slots:
		var arena = slot.get("arena")
		if arena != null and is_instance_valid(arena):
			arena.queue_free()
		var vp = slot.get("viewport")
		if vp != null and is_instance_valid(vp):
			vp.queue_free()
	_slots.clear()
