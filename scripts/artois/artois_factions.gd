extends RefCounted
## Public allegiances only; disguised raiders do not expose their sponsors.
static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/artois_factions.json"))

static func access_error(scores: Dictionary, port: String) -> String:
	var faction: String = str(data.owners.get(port, ""))
	# St Paul's chapter provides neutral humanitarian recovery and refuge.
	if faction.is_empty(): return ""
	var score := int(scores.get(faction, data.factions[faction].initial))
	if score < int(data.docking_minimum):
		return "DOCKING REFUSED / %s / REPUTATION %d / NEED %d" % [data.factions[faction].name.to_upper(), score, int(data.docking_minimum)]
	return ""

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
