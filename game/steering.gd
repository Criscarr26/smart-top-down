class_name Steering
extends RefCounted
## Utilidades de direccion compartidas por los enemigos FSM y el agente
## entrenado. Ambos necesitan exactamente la misma logica de huida, y duplicarla
## haria que el agente y el Tipo C huyeran distinto por accidente en vez de por
## diseno.


## Punto transitable alejandose de la amenaza.
##
## Prueba la direccion opuesta y va abriendo el angulo. Sin esto, un actor que
## huye contra una pared se queda vibrando pegado al muro: la direccion "lejos"
## apunta a la pared, el movimiento se cancela, y no se recupera nunca.
static func flee_point(from: Vector2, threat: Vector2, nav: NavGrid,
		rng: RandomNumberGenerator = null) -> Vector2:
	var away := from - threat
	if away.length_squared() < 0.0001:
		# Amenaza exactamente encima: hace falta una direccion arbitraria.
		var angle: float = rng.randf() * TAU if rng != null else Rng.randf() * TAU
		away = Vector2.RIGHT.rotated(angle)
	away = away.normalized()
	const DISTANCES := [5.0, 3.5, 2.0]
	const ANGLES := [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.2, -2.2]
	for d in DISTANCES:
		for a in ANGLES:
			var candidate: Vector2 = from + away.rotated(a) * (GameConfig.CELL_SIZE * float(d))
			if nav.is_walkable_world(candidate):
				return candidate
	return from


## Pocion disponible mas cercana en linea recta, o null.
static func nearest_potion(from: Vector2, potions: Array) -> Potion:
	var best: Potion = null
	var best_d := INF
	for p in potions:
		var potion := p as Potion
		if potion == null or not potion.available:
			continue
		var d := from.distance_squared_to(potion.global_position)
		if d < best_d:
			best_d = d
			best = potion
	return best
