extends Node
## Constantes de simulacion y balance. Autoload: GameConfig.
##
## DECISION DE DISENO CENTRAL DEL PROYECTO:
## Toda la logica de juego avanza con SIM_DT fijo y con contadores de ticks
## enteros; nunca con el `delta` que entrega el motor ni con nodos Timer.
##
## Motivo: el benchmark necesita correr con `Engine.time_scale` alto para que
## las miles de partidas terminen en tiempo razonable, y `time_scale` escala el
## delta que recibe `_physics_process`. Si la logica dependiera de ese delta,
## una partida a x1 y la misma partida a x50 darian resultados distintos y el
## benchmark cuantitativo no valdria nada. Con SIM_DT fijo, la aceleracion solo
## cambia cuanto tiempo real toma, no el resultado.
##
## Corolario: los actores se mueven con move_and_collide(v * SIM_DT) y NO con
## move_and_slide(), porque move_and_slide() usa internamente el delta escalado
## del motor.

# --- Reloj de simulacion -----------------------------------------------------
const TICKS_PER_SECOND: int = 60
const SIM_DT: float = 1.0 / 60.0

## Convierte segundos a ticks de simulacion (redondeando arriba, minimo 1).
static func secs_to_ticks(seconds: float) -> int:
	return maxi(1, int(ceil(seconds * float(TICKS_PER_SECOND))))

# --- Capas de fisica (valores de mascara, no indices) ------------------------
const LAYER_WORLD: int = 1 << 0    # 1  - paredes
const LAYER_PLAYER: int = 1 << 1   # 2  - jugador (y bot sustituto)
const LAYER_ENEMY: int = 1 << 2    # 4  - enemigos y agente
const LAYER_HAZARD: int = 1 << 3   # 8  - puas
const LAYER_PICKUP: int = 1 << 4   # 16 - pociones

# --- Mundo -------------------------------------------------------------------
const CELL_SIZE: float = 32.0
const ACTOR_RADIUS: float = 11.0

# --- Inercia -----------------------------------------------------------------
## Aceleracion y frenado por defecto, en px/s^2.
##
## Calibrado sobre PLAYER_SPEED (165 px/s): a 1400 px/s^2 el jugador alcanza su
## velocidad maxima en 0.12 s y a 2200 se detiene en 0.075 s. Es la ventana en la
## que el movimiento tiene peso pero todavia responde; por encima de ~2500 la
## inercia deja de notarse y por debajo de ~900 el personaje patina.
const ACCEL_DEFAULT: float = 1400.0
const FRICTION_DEFAULT: float = 2200.0

# --- Jugador -----------------------------------------------------------------
const PLAYER_MAX_HEALTH: float = 100.0
const PLAYER_SPEED: float = 165.0
const PLAYER_MELEE_DAMAGE: float = 26.0
const PLAYER_RANGED_DAMAGE: float = 16.0

# --- Escudo (jugador y enemigos que pueden defender) -------------------------
const MAX_SHIELD: float = 100.0
## Fraccion del dano que ATRAVIESA el escudo mientras se defiende.
const SHIELD_DAMAGE_PASSTHROUGH: float = 0.2
## Escudo consumido por cada punto de dano bloqueado.
const SHIELD_COST_PER_DAMAGE: float = 1.4
## Escudo consumido por tick simplemente por mantener la guardia arriba.
const SHIELD_DRAIN_PER_TICK: float = 0.25
## Al romperse el escudo el actor queda vulnerable este tiempo y no puede defender.
const SHIELD_BREAK_TICKS: int = 90          # 1.5 s
## Regeneracion de escudo por tick cuando NO se esta defendiendo.
const SHIELD_REGEN_PER_TICK: float = 0.35
## Ticks sin defender antes de que empiece a regenerar.
const SHIELD_REGEN_DELAY_TICKS: int = 60    # 1.0 s

# --- Combate -----------------------------------------------------------------
const MELEE_RANGE: float = 34.0
## Semiangulo del arco de melee, en radianes (arco total de 120 grados).
const MELEE_ARC: float = deg_to_rad(60.0)
const MELEE_COOLDOWN_TICKS: int = 30        # 0.5 s
const RANGED_COOLDOWN_TICKS: int = 42       # 0.7 s
const PROJECTILE_SPEED: float = 420.0
const PROJECTILE_LIFETIME_TICKS: int = 90   # 1.5 s

# --- Pociones ----------------------------------------------------------------
const POTION_HEAL: float = 40.0
const POTION_PICKUP_RADIUS: float = 16.0
## Un actor busca pocion por debajo de esta fraccion de su salud maxima.
const LOW_HEALTH_FRACTION: float = 0.35

# --- Vision ------------------------------------------------------------------
const VISION_RANGE: float = 320.0
## Semiangulo del cono de vision, en radianes (cono total de 110 grados).
const VISION_HALF_ANGLE: float = deg_to_rad(55.0)
## Tras perder al objetivo, el enemigo lo "recuerda" durante estos ticks.
const VISION_MEMORY_TICKS: int = 90         # 1.5 s

# --- Limites de episodio (benchmark) -----------------------------------------
## Corte duro de un episodio de EVALUACION; evita que dos agentes pasivos
## cuelguen el barrido.
const MAX_EPISODE_TICKS: int = 60 * 60      # 60 s de tiempo de juego

## Corte de los episodios de ENTRENAMIENTO, mas corto a proposito.
##
## Un combate que no se ha resuelto en 30 s es un empate, y la senal de fitness
## que aporta el segundo medio minuto es practicamente nula. Como el
## entrenamiento son decenas de miles de episodios y la evaluacion solo cientos,
## recortar aqui es lo que decide si el barrido cabe en una noche.
const TRAINING_EPISODE_TICKS: int = 30 * 60  # 30 s de tiempo de juego
