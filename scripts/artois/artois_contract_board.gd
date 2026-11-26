extends RefCounted
## Authored templates plus bounded random offers. Cached until a contract resolves.
const BASIC_FALLBACK := {"id": "clearance", "title": "Freebooter clearance", "tier": "Basic", "enemy_faction": "freebooter", "minimum_reputation": 0, "minimum_ships": 2, "maximum_ships": 3, "base_pay": 500, "per_ship": 200, "reputation": 7, "hull_scale": 0.85, "brief": "Freebooters are threatening local traffic. Destroy the entire marked patrol."}
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/artois_contracts.json"))
var _random := RandomNumberGenerator.new()
var _cache := {}
var _serial := 0

func _init() -> void:
	_random.randomize()

func contacts(port: String) -> Array:
	return config.contacts.filter(func(issuer: Dictionary) -> bool: return issuer.port == port)

func contact(id: String) -> Dictionary:
	for entry in config.contacts:
		if entry.id == id: return entry
	return {}

func invalidate(id: String) -> void:
	_cache.erase(id)

func offers(id: String, world: Node3D) -> Array:
	if _cache.has(id): return _cache[id].duplicate(true)
	var issuer := contact(id)
	if issuer.is_empty(): return []
	var result := []
	var templates: Array = config.templates.duplicate(true)
	# Every board must retain an entry-level contract, independent of template edits.
	if not templates.any(func(entry: Dictionary) -> bool: return int(entry.get("minimum_reputation", 0)) == 0): templates.append(BASIC_FALLBACK.duplicate(true))
	templates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.minimum_reputation) < int(b.minimum_reputation))
	for template in templates:
		_serial += 1
		var count := clampi(_random.randi_range(int(template.minimum_ships), int(template.maximum_ships)), 1, 6)
		var position := _site(world, str(issuer.port))
		var distance: float = position.distance_to(world.target_position(issuer.port))
		var captain := "%s %s" % [config.first[_random.randi_range(0, config.first.size() - 1)], config.last[_random.randi_range(0, config.last.size() - 1)]]
		var offer: Dictionary = template.duplicate(true)
		offer.merge({"id": "contract_%d" % _serial, "contact": id, "issuer": issuer.name, "faction": issuer.faction, "port": issuer.port,
			"count": count, "captain": captain, "site": world.layout.to_map(position), "altitude": position.y,
			"reward": int(template.base_pay) + int(template.per_ship) * count + roundi(distance / 500) * 50,
			"distance": distance, "objective": 1 if template.id == "bounty" else count, "template": template.id}, true)
		if template.id == "bounty": offer.title = "Bounty: " + captain
		result.append(offer)
	_cache[id] = result
	return result.duplicate(true)

func _site(world: Node3D, port: String) -> Vector3:
	var origin: Vector3 = world.target_position(port)
	for attempt in 128:
		var angle := _random.randf_range(0, TAU)
		var radius := _random.randf_range(1800, 4200)
		var candidate := origin + Vector3(cos(angle) * radius, _random.randf_range(40, 160), sin(angle) * radius)
		var map: Vector2 = world.layout.to_map(candidate)
		if map.x < 20 or map.y < 20 or map.x > world.layout.map_size.x - 20 or map.y > world.layout.map_size.y - 20: continue
		var clear := true
		for entry in world.layout.locations:
			if entry.kind == "mission": continue
			if candidate.distance_to(world.layout.world(entry)) < 650: clear = false
		if candidate.distance_to(world.layout.world(world.layout.planet)) < float(world.layout.planet.radius) + 1000: clear = false
		for route in world.highways.routes:
			var near := Geometry3D.get_closest_point_to_segment(candidate, route.start, route.end)
			if near.distance_to(candidate) < 250: clear = false
		if clear: return candidate
	# A deterministic in-system fallback, still checked against authored geometry.
	return world.layout.world({"map": [680, 495], "altitude": 80})
