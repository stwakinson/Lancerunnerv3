class_name ArtoisMarkets
extends RefCounted
static var _ports: Dictionary = {}


func _init() -> void:
	if _ports.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/artois_markets.json"))
		_ports = data.ports


func has_port(id: String) -> bool:
	return _ports.has(id)


func ports() -> Array:
	return _ports.keys()


func profile(id: String) -> Dictionary:
	return _ports.get(id, {})


func scene_path(id: String) -> String:
	return "res://scenes/planet_landing.tscn" if id == "planet_dock" else "res://scenes/stations/%s.tscn" % id
