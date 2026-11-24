extends Node3D
## Session-local physical loot; inventory changes persist atomically before removal.
const Holds = preload("res://scripts/artois/artois_ship_holds.gd")
const RANGE := 25.0
const LIFETIME := 600.0
const MAX_CANISTERS := 128
const UNITS_PER_CANISTER := 25
var world: Node3D
var canisters := {}
var _random := RandomNumberGenerator.new()
var _serial := 0
var _mesh: ArrayMesh
var _material: StandardMaterial3D

func configure(space: Node3D) -> void:
	world = space
	_random.randomize()
	_make_mesh()

func has(id: String) -> bool:
	return canisters.has(id)

func survivors(amount: int) -> int:
	return _random.randi_range(0, mini(amount - 1, floori(amount * 0.75))) if amount > 1 else 0

func drop_ship(ship: Node3D, hold: Dictionary, velocity: Vector3) -> Dictionary:
	if ship.get_meta("cargo_dropped", false): return {}
	ship.set_meta("cargo_dropped", true)
	var report := {"survived": {}, "destroyed": {}}
	for id in hold:
		if not LandingMarketState.ITEMS.has(id) or LandingMarketState.ITEMS[id].kind != "commodity": continue
		var before := int(hold[id])
		if before < 1: continue
		var remainder := survivors(before)
		var emitted := 0
		while remainder > 0 and canisters.size() < MAX_CANISTERS:
			var amount := mini(UNITS_PER_CANISTER, remainder)
			spawn(id, amount, ship.global_position, velocity * 0.03)
			remainder -= amount
			emitted += amount
		if emitted > 0: report.survived[id] = emitted
		report.destroyed[id] = before - emitted
	hold.clear()
	return report

func drop_player() -> void:
	if world.ship.get_meta("cargo_dropped", false): return
	var market: LandingMarketState = world.combat.ordnance.market
	var before := market.cargo.duplicate(true)
	if before.is_empty(): return
	market.cargo.clear()
	if not market.save_state():
		market.cargo = before
		world.combat.ordnance.notify("CARGO LOSS COULD NOT BE SAVED / HOLD RETAINED")
		return
	drop_ship(world.ship, before, world.velocity)

func spawn(good: String, amount: int, at: Vector3, drift := Vector3.ZERO) -> String:
	if amount < 1 or not LandingMarketState.ITEMS.has(good) or LandingMarketState.ITEMS[good].kind != "commodity" or canisters.size() >= MAX_CANISTERS: return ""
	_serial += 1
	var id := "cargo_%d" % _serial
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = _mesh
	node.material_override = _material
	add_child(node)
	node.global_position = at + Vector3(_random.randf_range(-5, 5), _random.randf_range(-3, 3), _random.randf_range(-5, 5))
	node.rotation = Vector3(_random.randf() * PI, _random.randf() * TAU, _random.randf() * PI)
	var velocity := drift + Vector3(_random.randf_range(-0.8, 0.8), _random.randf_range(-0.5, 0.5), _random.randf_range(-0.8, 0.8))
	canisters[id] = {"id": id, "good": good, "quantity": amount, "node": node, "velocity": velocity, "age": 0.0}
	return id

func entry(id: String) -> Dictionary:
	if not has(id): return {}
	var crate: Dictionary = canisters[id]
	return {"id": id, "kind": "cargo", "name": str(LandingMarketState.ITEMS[crate.good].name) + " Canister", "notes": "%d units / H: collect within 25 m / free hold space required" % crate.quantity}

func nearby_ids(radius := 1800.0) -> Array:
	var ids := []
	for id in canisters:
		if world.ship.position.distance_to(canisters[id].node.position) <= radius: ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool: return world.ship.position.distance_squared_to(canisters[a].node.position) < world.ship.position.distance_squared_to(canisters[b].node.position))
	return ids

func pickup() -> Dictionary:
	if world.combat.dead or world.cruise or world.cruise_spool > 0 or world.highways.attached(): return {"taken": 0, "error": "LEAVE TRANSIT BEFORE COLLECTING CARGO"}
	var ids := nearby_ids(RANGE)
	if ids.is_empty(): return {"taken": 0, "error": "NO CARGO CANISTER WITHIN 25 m"}
	var id: String = world.selected_id if ids.has(world.selected_id) else ids[0]
	var crate: Dictionary = canisters[id]
	var result: Dictionary = world.combat.ordnance.market.acquire_cargo(crate.good, int(crate.quantity))
	if int(result.taken) > 0:
		crate.quantity -= int(result.taken)
		world.combat.ordnance.notify("CARGO RECOVERED / %s ×%d" % [LandingMarketState.ITEMS[crate.good].name, result.taken])
		if int(crate.quantity) == 0: _remove(id)
	else: world.combat.ordnance.notify(str(result.error))
	return result

func advance(delta: float) -> void:
	for id in canisters.keys():
		var crate: Dictionary = canisters[id]
		crate.age += delta
		crate.node.position += crate.velocity * ((1 - exp(-delta * 0.4)) / 0.4)
		crate.velocity *= exp(-delta * 0.4)
		crate.node.rotate_y(delta * 0.22)
		crate.node.rotate_z(delta * 0.1)
		var centre: Vector3 = world.layout.world(world.layout.planet)
		var offset: Vector3 = crate.node.position - centre
		var radius: float = world.layout.planet.radius + 3
		if offset.length() < radius: crate.node.position = centre + (offset.normalized() if offset.length_squared() > 0.01 else Vector3.UP) * radius
		if crate.age >= LIFETIME: _remove(id)

func _remove(id: String) -> void:
	if not has(id): return
	canisters[id].node.queue_free()
	canisters.erase(id)
	if world.selected_id == id: world.select_target(world.DOCK_ID)

func _make_mesh() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for band in [[-1.0, 1.0, 0.65, Color("647779")], [-0.85, -0.65, 0.69, Color("d2a85f")], [0.65, 0.85, 0.69, Color("d2a85f")]]:
		for i in 6:
			var a := Vector3(cos(i * TAU / 6), 0, sin(i * TAU / 6)) * float(band[2])
			var b := Vector3(cos((i + 1) * TAU / 6), 0, sin((i + 1) * TAU / 6)) * float(band[2])
			surface.set_color(band[3])
			for point in [a + Vector3.UP * band[0], a + Vector3.UP * band[1], b + Vector3.UP * band[1], a + Vector3.UP * band[0], b + Vector3.UP * band[1], b + Vector3.UP * band[0]]: surface.add_vertex(point)
	for sign in [-1.0, 1.0]:
		for i in 6:
			surface.set_color(Color("b99561"))
			var points := [Vector3.UP * sign, Vector3(cos(i * TAU / 6) * 0.65, sign, sin(i * TAU / 6) * 0.65), Vector3(cos((i + 1) * TAU / 6) * 0.65, sign, sin((i + 1) * TAU / 6) * 0.65)]
			if sign > 0: points.reverse()
			for point in points: surface.add_vertex(point)
	surface.generate_normals()
	_mesh = surface.commit()
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.8
