class_name ArtoisSpace
extends BenchmarkSpace

const Holds = preload("res://scripts/artois/artois_ship_holds.gd")
const Loot = preload("res://scripts/artois/artois_cargo_loot.gd")
const Markets = preload("res://scripts/artois/artois_markets.gd")
const Embry = preload("res://scripts/artois/artois_embry.gd")
const Traffic = preload("res://scripts/artois/artois_traffic.gd")
const Highways = preload("res://scripts/artois/artois_highways.gd")
const Combat = preload("res://scripts/artois/artois_combat.gd")
const Layout = preload("res://scripts/artois/artois_layout.gd")
const Shapes = preload("res://scripts/artois/artois_placeholders.gd")
const NORMAL_SPEED := 35.0
const CRUISE_SPEED := NORMAL_SPEED * 5.0
const DOCK_RANGE := 90.0
const DOCK_SPEED := 20.0
const DOCK_ID := "planet_dock"

var port_catalog := Markets.new()
var active_port := DOCK_ID
var embry_art := Embry.new()
var loot: Node3D
var law: Node
var traffic: ArtoisTraffic
var highways: ArtoisHighways
var combat: ArtoisCombat
var disruption_remaining := 0.0
var dodge_velocity := Vector3.ZERO
var dodge_cooldown := 0.0
var _last_taps := {}
var layout := Layout.new()
var landmarks := {}
var field_nodes := {}
var selected_id := DOCK_ID
var velocity := Vector3.ZERO
const CRUISE_SPOOL_TIME := 1.8
var cruise_spool := 0.0
var cruise := false
var autopilot := false
var arrival_message := ""
var _yaw := 0.0
var _pitch := 0.0
var _shapes := Shapes.new()


func _ready() -> void:
	super._ready()
	combat = Combat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.configure(self, LandingMarketState.new())
	highways = Highways.new()
	highways.name = "GoldenHighways"
	add_child(highways)
	highways.configure(self)
	loot = Loot.new()
	loot.name = "CargoCanisters"
	add_child(loot)
	loot.configure(self)
	law = preload("res://scripts/artois/artois_law.gd").new()
	law.name = "FactionLaw"
	law.world = self
	add_child(law)
	traffic = Traffic.new()
	traffic.name = "LocalTraffic"
	add_child(traffic)
	traffic.configure(self)


func tap_direction(key: int, now: float) -> bool:
	const DIRECTIONS := {KEY_A: Vector3.LEFT, KEY_D: Vector3.RIGHT, KEY_W: Vector3.FORWARD, KEY_S: Vector3.BACK, KEY_Q: Vector3.DOWN, KEY_E: Vector3.UP}
	if not DIRECTIONS.has(key) or combat.dead or disruption_remaining > 0: return false
	var previous := float(_last_taps.get(key, -10.0))
	_last_taps[key] = now
	if now - previous > 0.27 or now < previous or dodge_cooldown > 0: return false
	_last_taps.clear()
	cancel_cruise()
	autopilot = false
	if highways.attached():
		highways.escape(ship.basis * DIRECTIONS[key])
		dodge_velocity = Vector3.ZERO
	else:
		dodge_velocity = ship.basis * DIRECTIONS[key] * 135.0
	dodge_cooldown = 0.65
	return true


func reset_taps() -> void:
	_last_taps.clear()


func _build_world() -> void:
	camera.near = 0.3
	camera.far = 40000
	for entry in layout.locations:
		var node := embry_art.make_station() if entry.id == "embry" else _shapes.make(entry)
		node.position = layout.world(entry)
		add_child(node)
		landmarks[entry.id] = node
	station = landmarks.agincourt
	for field in layout.fields:
		_build_field(field)
	super._make_planet()
	var planet_node := get_node("ArtoisPlanet") as MeshInstance3D
	planet_node.position = layout.world(layout.planet)
	planet_node.scale = Vector3.ONE * (float(layout.planet.radius) / 290.0)
	super._make_sun()
	_sun.position *= 20.0
	_sun.scale = Vector3.ONE * 20.0
	ship.name = "ArtoisPlayer"
	ship.position = launch_position()


func _build_field(field: Dictionary) -> void:
	if field.get("visual_profile", "") == "column_canyon":
		var node := embry_art.make_field(self, field)
		add_child(node)
		field_nodes[field.id] = node
		asteroid_count += node.multimesh.instance_count
		return
	var random := RandomNumberGenerator.new()
	random.seed = int(field.seed)
	var source := SphereMesh.new()
	source.radius = 1
	source.height = 2
	source.radial_segments = 7
	source.rings = 3
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = _faceted(source)
	instances.instance_count = int(field.count)
	var node := MultiMeshInstance3D.new()
	node.name = field.id
	node.multimesh = instances
	node.material_override = _rock_material("685369" if field.id == "central_field" else "534b65")
	node.position = layout.world(field)
	var radii := Layout.point(field.radii) * layout.scale_factor
	for i in instances.instance_count:
		var local := Vector3.ZERO
		for attempt in 64:
			var flat := Vector2(random.randf_range(-1, 1), random.randf_range(-1, 1))
			if flat.length_squared() > 1: continue
			local = Vector3(flat.x * radii.x, random.randf_range(-1, 1) * float(field.height) * sqrt(1.0 - flat.length_squared()), flat.y * radii.y)
			var clear := true
			for landmark in landmarks.values():
				if (node.position + local).distance_to(landmark.position) < 85:
					clear = false
					break
			if clear: break
		var rotation := Basis.from_euler(Vector3(random.randf() * TAU, random.randf() * TAU, random.randf() * TAU))
		var size := random.randf_range(2.0, 8.0)
		instances.set_instance_transform(i, Transform3D(rotation.scaled(Vector3(size, size * 0.75, size * 1.2)), local))
		asteroid_count += 1
	add_child(node)
	field_nodes[field.id] = node


func target_position(id: String = "") -> Vector3:
	var resolved := selected_id if id.is_empty() else id
	if loot != null and loot.has(resolved): return loot.canisters[resolved].node.position
	if traffic != null:
		var local := traffic.get_actor(resolved)
		if not local.is_empty(): return local.node.position
	var hostile := combat.enemy(resolved) if combat != null else null
	if hostile != null: return hostile.position
	var entry := layout.target(resolved)
	return layout.world(entry) if not entry.is_empty() else ship.position


func select_target(id: String) -> void:
	if layout.target(id).is_empty() and (combat == null or combat.enemy(id) == null) and (traffic == null or traffic.get_actor(id).is_empty()) and (loot == null or not loot.has(id)): return
	if selected_id != id and combat != null: combat.ordnance.reset_lock()
	selected_id = id
	autopilot = false
	arrival_message = ""


func navigate_to(id: String) -> void:
	if highways.attached(): return
	if layout.target(id).is_empty() and (combat == null or combat.enemy(id) == null) and (traffic == null or traffic.get_actor(id).is_empty()) and (loot == null or not loot.has(id)): return
	select_target(id)
	autopilot = true
	cancel_cruise()


func align_to_target() -> void:
	cancel_cruise()
	var direction := target_position() - ship.position
	if direction.length_squared() < 0.01: return
	var up := Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
	ship.basis = Basis.looking_at(direction.normalized(), up)
	_sync_angles()


func engage_cruise() -> void:
	if disruption_remaining > 0:
		combat.ordnance.notify("FETTERED / CRUISE DISABLED")
		return
	if highways.attached():
		highways.escape(-ship.basis.z)
		return
	if cruise or cruise_spool > 0: return
	cruise_spool = CRUISE_SPOOL_TIME
	autopilot = false


func toggle_cruise() -> void:
	if disruption_remaining > 0: return
	if highways.attached(): return
	if cruise or cruise_spool > 0: cancel_cruise()
	else: engage_cruise()


func cancel_cruise() -> void:
	cruise = false
	cruise_spool = 0.0


func brake() -> void:
	if highways != null and highways.attached(): return
	cancel_cruise()
	autopilot = false
	velocity = Vector3.ZERO
	speed = 0.0
	dodge_velocity = Vector3.ZERO
	reset_taps()


func launch_position() -> Vector3:
	return layout.world(layout.target(active_port)) + Vector3(0, 12, 140)


func prepare_launch() -> void:
	disruption_remaining = 0.0
	highways.reset()
	ship.position = launch_position()
	ship.rotation = Vector3(0, 0 if active_port == DOCK_ID else PI, 0)
	_yaw = ship.rotation.y
	_pitch = 0
	brake()
	dodge_cooldown = 0.0
	selected_id = active_port
	arrival_message = "LAUNCH COMPLETE"
	combat.clear_projectiles()
	# Old trails and shots must not connect across the landing transition.
	for shot in shots: shot.queue_free()
	shots.clear()
	_effects.clear_trails()
	_update_camera(0.0)


func docking_error() -> String:
	for entry in layout.locations:
		if entry.kind == "hyper_gate" and ship.position.distance_to(layout.world(entry)) < 160:
			return "HYPER GATE OFFLINE / NO DESTINATION LINK / ARTOIS DEMO"
	if highways != null and highways.attached(): return "BREAK FREE OF THE FILAMENT BEFORE DOCKING"
	var port := docking_port()
	if ship.position.distance_to(target_position(port)) > DOCK_RANGE:
		return "APPROACH %s / WITHIN 90 m TO DOCK" % str(port_catalog.profile(port).name).to_upper()
	if (velocity + dodge_velocity).length() > DOCK_SPEED:
		return "SLOW BELOW 20 m/s TO DOCK  /  X TO BRAKE"
	return ""


func advance(delta: float, steering: Vector2, thrust: float, boosting: bool, firing: bool) -> void:
	if combat.dead: return
	if thrust < 0: cancel_cruise()
	if cruise_spool > 0:
		cruise_spool = maxf(0.0, cruise_spool - delta)
		if cruise_spool == 0: cruise = true
	combat.ordnance.update_aim()
	combat.defence.guard_direction = combat.ordnance.pointer_direction if combat.ordnance.cursor_enabled else -ship.global_basis.z
	combat.defence.advance(delta, combat.guard_requested and not (cruise or cruise_spool > 0 or highways.attached()), combat.dead)
	boosting = combat.defence.afterburner(delta, boosting and not cruise and cruise_spool == 0 and disruption_remaining <= 0)
	if boosting: autopilot = false
	combat.defence.update_visual(cruise_spool / CRUISE_SPOOL_TIME)
	elapsed += delta
	disruption_remaining = maxf(0.0, disruption_remaining - delta)
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	highways.tick(delta)
	var previous := ship.position
	var input := Vector3(steering.x, steering.y, -thrust)
	if highways.attached() and boosting and input.length_squared() > 0:
		highways.escape(ship.basis * input)
	if highways.attached():
		highways.advance(delta, steering)
	else:
		_advance_manual(delta, steering, thrust, boosting)
		highways.try_enter(previous, ship.position)
	_avoid_planet()
	speed = (velocity + dodge_velocity).length()
	for i in ship.engines.size():
		ship.engines[i].visible = speed > 0.5
		ship.engines[i].scale.z = clampf(speed / NORMAL_SPEED, 0, 2) * (1.0 + (0.6 if boosting or cruise or autopilot or highways.attached() else 0.12) * (1.0 + sin(elapsed * 23)))
	traffic.advance(delta)
	combat.advance(delta)
	loot.advance(delta)
	if firing and not cruise: _fire_shot()
	camera.fov = lerpf(camera.fov, 66.0 if highways.attached() else (60.0 if cruise or autopilot else (58.0 if boosting else 54.0)), 1.0 - exp(-delta * 3.0))
	_update_camera(delta)
	_effects.advance(delta, ship, camera, boosting or cruise or autopilot or highways.attached(), clampf(speed / NORMAL_SPEED, 0, 1))


func _advance_manual(delta: float, steering: Vector2, thrust: float, boosting: bool) -> void:
	if steering != Vector2.ZERO or thrust != 0:
		autopilot = false
	var forward := -ship.basis.z
	var desired := Vector3.ZERO
	if autopilot:
		var destination := highways.approach_position(selected_id) if highways.gates.has(selected_id) else target_position()
		var to_target := destination - ship.position
		var distance := to_target.length()
		var stopping_distance := 12.0 if highways.gates.has(selected_id) else (15.0 if loot.has(selected_id) else (55.0 if selected_id == DOCK_ID else 75.0))
		if distance > 0.01:
			var direction := to_target / distance
			var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
			ship.basis = Basis(ship.basis.get_rotation_quaternion().slerp(Basis.looking_at(direction, up).get_rotation_quaternion(), 1.0 - exp(-delta * 3.0)))
			desired = direction * minf(280.0, sqrt(2.0 * 70.0 * maxf(0.0, distance - stopping_distance)))
		if distance <= stopping_distance + 4 and velocity.length() < 4:
			autopilot = false
			desired = Vector3.ZERO
			if highways.gates.has(selected_id):
				ship.basis = Basis.looking_at(highways.gates[selected_id].axis, Vector3.UP)
			arrival_message = "ARRIVED  /  " + str(target_entry().name).to_upper()
		_sync_angles()
	else:
		var top_speed := CRUISE_SPEED if cruise else (105.0 if boosting else NORMAL_SPEED)
		desired = forward * (1.0 if cruise else thrust) * top_speed
		desired += (ship.basis.x * steering.x + ship.basis.y * steering.y) * (40.0 if boosting else 25.0)
	if cruise: desired = desired.limit_length(CRUISE_SPEED)
	if disruption_remaining > 0: desired = desired.limit_length(12.0)
	velocity = velocity.move_toward(desired, (110.0 if autopilot or cruise else 85.0) * delta)
	# Integrate exponential dodge decay independently of normal thrust.
	ship.position += velocity * delta + dodge_velocity * ((1.0 - exp(-delta * 6.0)) / 6.0)
	dodge_velocity *= exp(-delta * 6.0)


func _fire_shot() -> void:
	combat.fire()


func _avoid_planet() -> void:
	var centre := layout.world(layout.planet)
	var offset := ship.position - centre
	var radius := float(layout.planet.radius) + 8
	if offset.length() < radius:
		var up := offset.normalized() if offset.length_squared() > 0.001 else Vector3.UP
		ship.position = centre + up * radius
		if velocity.dot(up) < 0: velocity -= up * velocity.dot(up)


func _update_camera(delta: float) -> void:
	var target := ship.position + ship.basis * Vector3(4.8, 3.7, 11.7)
	camera.position = camera.position.lerp(target, 1.0 - exp(-delta * 7.0)) if delta > 0 else target
	camera.look_at(ship.position - ship.basis.z * 16, ship.basis.y)
	if _sun != null: _sun.look_at(camera.position, Vector3.UP)


func _sync_angles() -> void:
	var forward := -ship.basis.z
	_yaw = atan2(-forward.x, -forward.z)
	_pitch = asin(clampf(forward.y, -1, 1))


func orbit(relative: Vector2) -> void:
	autopilot = false
	var turn_scale := 0.18 if cruise else 1.0
	_yaw -= relative.x * 0.004 * turn_scale
	_pitch = clampf(_pitch - relative.y * 0.003 * turn_scale, -1.35, 1.35)
	ship.rotation = Vector3(_pitch, _yaw, 0)


func reset_view() -> void:
	_update_camera(0.0)


func target_entry() -> Dictionary:
	if loot != null and loot.has(selected_id): return loot.entry(selected_id)
	if traffic != null:
		var entry := traffic.target_entry(selected_id)
		if not entry.is_empty(): return entry
	var hostile := combat.enemy(selected_id) if combat != null else null
	if hostile != null:
		return {"id": selected_id, "name": "Freebooter " + selected_id.trim_prefix("patrol_"), "kind": "hostile", "notes": "%s / Hull %d / Shield %d / HOLD %d/%d" % [str(hostile.get_meta("tactic", "WAITING")), roundi(hostile.get_meta("hull")), roundi(hostile.get_meta("shield")), Holds.used(hostile.get_meta("cargo_hold", {})), int(hostile.get_meta("cargo_capacity", 0))]}
	var entry: Dictionary = layout.target(selected_id).duplicate()
	var owner: String = law.territory_owner(selected_id)
	if not owner.is_empty(): entry["notes"] = str(entry.get("notes", "")) + " / " + law.description(owner)
	return entry


func apply_disruption(duration: float) -> void:
	disruption_remaining = maxf(disruption_remaining, duration)
	highways.reset()
	cancel_cruise()
	autopilot = false
	dodge_velocity = Vector3.ZERO
	velocity = velocity.limit_length(12.0)
	reset_taps()
	combat.ordnance.reset_lock()
	combat.ordnance.notify("FETTER HIT / CRUISE CANCELLED / SPEED LIMITED FOR 6s")


func docking_port() -> String:
	var chosen := selected_id if port_catalog.has_port(selected_id) else DOCK_ID
	var nearest := DOCK_RANGE
	for id in port_catalog.ports():
		var distance := ship.position.distance_to(target_position(id))
		if distance <= nearest:
			nearest = distance
			chosen = id
	return chosen
