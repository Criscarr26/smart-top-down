class_name AssetLibrary
extends RefCounted
## Acceso cacheado a los sprites y sonidos.
##
## Los assets se cargan BAJO DEMANDA y solo cuando hay algo que mostrar. El
## benchmark corre decenas de miles de episodios sin ventana: cargar texturas y
## audio ahi seria trabajo puro de descarte. Por eso el Arena solo llama a estas
## funciones cuando `interactive` es true.
##
## Todos los archivos los generan tools/generate_sprites.py y
## tools/generate_sfx.py. Son originales, no descargados.

const SPRITE_DIR := "res://assets/"
const AUDIO_DIR := "res://assets/"

static var _textures: Dictionary = {}
static var _streams: Dictionary = {}


## Textura del actor segun el tipo de perfil ("A", "B", "C", "AGENT") o
## "player". Devuelve null si el archivo no existe todavia, y el actor cae al
## dibujado por primitivas.
static func actor_texture(kind: String) -> Texture2D:
	return texture("actor_%s" % kind.to_lower())


static func texture(name: String) -> Texture2D:
	if _textures.has(name):
		return _textures[name]
	var path := SPRITE_DIR + name + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_textures[name] = tex
	return tex


static func sound(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path := AUDIO_DIR + name + ".wav"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	_streams[name] = stream
	return stream


## True si el arte generado esta presente. Si no, el juego sigue funcionando
## con las primitivas de _draw; solo se ve mas pobre.
static func has_art() -> bool:
	return ResourceLoader.exists(SPRITE_DIR + "actor_player.png")


static func clear_cache() -> void:
	_textures.clear()
	_streams.clear()
