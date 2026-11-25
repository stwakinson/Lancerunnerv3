extends RefCounted
## Standard hulls; optional required_faction supports future faction licences.
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/artois_ships.json"))
static func profile(id: String) -> Dictionary:
	return catalog.get(id, catalog.fighter)
static func trade_in(id: String) -> int:
	return int(catalog[id].price) / 2 if catalog.has(id) else 0
