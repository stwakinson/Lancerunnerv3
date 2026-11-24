extends RefCounted
## Public allegiances only; disguised raiders do not expose their sponsors.
static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/artois_factions.json"))

static func defaults() -> Dictionary:
	var result := {}
	for id in data.factions: result[id] = int(data.factions[id].initial)
	return result

static func valid(scores: Variant) -> bool:
	if not scores is Dictionary: return false
	for id in scores:
		if not data.factions.has(id): return false
		var value: Variant = scores[id]
		if not typeof(value) in [TYPE_INT, TYPE_FLOAT]: return false
		if not is_finite(float(value)) or absf(float(value)) > 100 or float(value) != floorf(float(value)): return false
	return true
