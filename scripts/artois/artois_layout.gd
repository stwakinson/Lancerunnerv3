class_name ArtoisLayout
extends RefCounted

# Single source of truth for the 3D world and the navigation chart.
const SOURCE := "res://data/artois.json"
var locations: Array = []
var fields: Array = []
var highways: Array = []
var planet: Dictionary
var map_size: Vector2
var origin: Vector2
var scale_factor := 8.0


func _init() -> void:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	assert(document is Dictionary, "Artois layout must be a JSON object")
	locations = document.locations
	fields = document.fields
	highways = document.get("highways", [])
	planet = document.planet
	map_size = point(document.map_size)
	origin = point(document.map_origin)
	scale_factor = float(document.units_per_map_pixel)
	assert(scale_factor > 0)
	var seen := {}
	for entry in targets():
		assert(entry.id is String and not seen.has(entry.id), "Artois target IDs must be unique")
		assert(entry.map is Array and entry.map.size() == 2)
		seen[entry.id] = true
	for field in fields:
		assert(field.radii[0] > 0 and field.radii[1] > 0 and field.count > 0)


static func point(values: Array) -> Vector2:
	return Vector2(float(values[0]), float(values[1]))


func world(entry: Dictionary) -> Vector3:
	var flat := (point(entry.map) - origin) * scale_factor
	return Vector3(flat.x, float(entry.get("altitude", 0)), flat.y)


func to_map(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z) / scale_factor + origin


func targets() -> Array:
	var result := locations.duplicate()
	for field in fields:
		var entry: Dictionary = field.duplicate()
		entry.kind = "field"
		entry.notes = "Authored asteroid volume. Navigation tracks the centre of the field."
		result.append(entry)
	result.append_array(highway_targets())
	return result


func target(id: String) -> Dictionary:
	for entry in targets():
		if entry.id == id: return entry
	return {}


func highway_targets() -> Array:
	var result := []
	for lane in highways:
		for endpoint in ["a", "b"]:
			for entrance in [true, false]:
				var sign := (1.0 if endpoint == "a" else -1.0) * (1.0 if entrance else -1.0)
				result.append({"id": "highway_" + str(lane.id) + "_" + endpoint + ("" if entrance else "_exit"),
					"name": str(lane.name) + " / " + endpoint.to_upper() + (" Upper" if sign > 0 else " Lower") + (" Entrance" if entrance else " Exit"),
					"kind": "highway_gate", "map": lane["from" if endpoint == "a" else "to"],
					"altitude": sign * 40.0, "entrance": entrance, "chart_axis": point(lane.to) - point(lane.from),
					"notes": "ONE WAY / " + ("G: approach. W: enter. Tab + direction: break free." if entrance else "Outbound only. Use the other ring to enter.")})
	return result
