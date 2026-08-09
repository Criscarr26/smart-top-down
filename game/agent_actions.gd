class_name AgentActions
extends RefCounted
## Los 6 actuadores = las 6 neuronas de la capa de salida.
##
## La seccion 3.2 del PDF exige "tantos actuadores como acciones posibles tiene
## el enemigo". El agente es el enemigo con TODAS las acciones disponibles
## (requisito 3.d), asi que estas 6 cubren lo que saben hacer los tipos A, B y C
## juntos: perseguir y golpear (A), disparar y defender (B), huir (C), y
## curarse (A y C).

enum {
	CHASE = 0,        ## acercarse al objetivo por ruta A*
	MELEE = 1,        ## golpear cuerpo a cuerpo
	RANGED = 2,       ## disparar un proyectil
	FLEE = 3,         ## alejarse del objetivo
	SEEK_POTION = 4,  ## ir a por la pocion disponible mas cercana
	DEFEND = 5,       ## levantar la guardia (inmoviliza, gasta escudo)
}

const COUNT := 6

const NAMES := ["Perseguir", "Melee", "Distancia", "Huir", "BuscarPocion", "Defender"]


static func name_of(action: int) -> String:
	if action < 0 or action >= COUNT:
		return "Ninguna"
	return NAMES[action]
