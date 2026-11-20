class_name ArtoisSpace
extends BenchmarkSpace

const Highways = preload("res://scripts/artois/artois_highways.gd")
const Combat = preload("res://scripts/artois/artois_combat.gd")
const Layout = preload("res://scripts/artois/artois_layout.gd")
const Shapes = preload("res://scripts/artois/artois_placeholders.gd")
const NORMAL_SPEED := 35.0
const CRUISE_SPEED := NORMAL_SPEED * 5.0
const DOCK_RANGE := 90.0
const DOCK_SPEED := 20.0
const DOCK_ID := "planet_dock"

var highways: ArtoisHighways
var combat: ArtoisCombat
var dodge_velocity := Vector3.ZERO
var dodge_cooldown := 0.0
var _last_taps := {}
var layout := Layout.new()
var landmarks := {}
var field_nodes := {}
var selected_id := DOCK_ID
var velocity := Vector3.ZERO
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


func tap_direction(key: int, now: float) -> bool:
	const DIRECTIONS := {KEY_A: Vector3.LEFT, KEY_D: Vector3.RIGHT, KEY_W: Vector3.FORWARD, KEY_S: Vector3.BACK, KEY_Q: Vector3.DOWN, KEY_E: Vector3.UP}
	if not DIRECTIONS.has(key) or combat.dead: return false
	var previous := float(_last_taps.get(key, -10.0))
	_last_taps[key] = now
	if now - previous > 0.27 or now < previous or dodge_cooldown > 0: return false
	_last_taps.clear()
	cruise = false
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
		var node := _shapes.make(entry)
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
	var hostile := combat.enemy(resolved) if combat != null else null
	if hostile != null: return hostile.position
	var entry := layout.target(resolved)
	return layout.world(entry) if not entry.is_empty() else ship.position


func select_target(id: String) -> void:
	if layout.target(id).is_empty() and (combat == null or combat.enemy(id) == null): return
	selected_id = id
	autopilot = false
	arrival_message = ""


func navigate_to(id: String) -> void:
	if highways.attached(): return
	if layout.target(id).is_empty() and (combat == null or combat.enemy(id) == null): return
	select_target(id)
	autopilot = true
	cruise = false


func align_to_target() -> void:
	var direction := target_position() - ship.position
	if direction.length_squared() < 0.01: return
	var up := Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
	ship.basis = Basis.looking_at(direction.normalized(), up)
	_sync_angles()


func engage_cruise() -> void:
	if highways.attached():
		highways.escape(-ship.basis.z)
		return
	cruise = true
	autopilot = false


func toggle_cruise() -> void:
	if highways.attached(): return
	cruise = not cruise
	autopilot = false


func brake() -> void:
	if highways != null and highways.attached(): return
	cruise = false
	autopilot = false
	velocity = Vector3.ZERO
	speed = 0.0
	dodge_velocity = Vector3.ZERO
	reset_taps()


func launch_position() -> Vector3:
	return layout.world(layout.target(DOCK_ID)) + Vector3(0, 12, 140)


func prepare_launch() -> void:
	highways.reset()
	ship.position = launch_position()
	ship.rotation = Vector3.ZERO
	_yaw = 0
	_pitch = 0
	brake()
	dodge_cooldown = 0.0
	selected_id = DOCK_ID
	arrival_message = "LAUNCH COMPLETE"
	combat.clear_projectiles()
	# Old trails and shots must not connect across the landing transition.
	for shot in shots: shot.queue_free()
	shots.clear()
	_effects.clear_trails()
	_update_camera(0.0)


func docking_error() -> String:
	if highways != null and highways.attached(): return "BREAK FREE OF THE FILAMENT BEFORE DOCKING"
	if ship.position.distance_to(target_position(DOCK_ID)) > DOCK_RANGE:
		return "APPROACH AGINCOURT PLANET PORT  /  WITHIN 90 m TO LAND"
	if (velocity + dodge_velocity).length() > DOCK_SPEED:
		return "SLOW BELOW 20 m/s TO DOCK  /  X TO BRAKE"
	return ""


func advance(delta: float, steering: Vector2, thrust: float, boosting: bool, firing: bool) -> void:
	if combat.dead: return
	elapsed += delta
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
		ship.engines[i].scale.z = 1.0 + (0.6 if boosting or cruise or autopilot or highways.attached() else 0.12) * (1.0 + sin(elapsed * 23))
	combat.advance(delta)
	if firing and not cruise: _fire_shot()
	camera.fov = lerpf(camera.fov, 66.0 if highways.attached() else (60.0 if cruise or autopilot else (58.0 if boosting else 54.0)), 1.0 - exp(-delta * 3.0))
	_update_camera(delta)
	_effects.advance(delta, ship, camera, boosting or cruise or autopilot or highways.attached())


func _advance_manual(delta: float, steering: Vector2, thrust: float, boosting: bool) -> void:
	if steering != Vector2.ZERO or thrust != 0:
		autopilot = false
	var forward := -ship.basis.z
	var desired := Vector3.ZERO
	if autopilot:
		var destination := highways.approach_position(selected_id) if highways.gates.has(selected_id) else target_position()
		var to_target := destination - ship.position
		var distance := to_target.length()
		var stopping_distance := 12.0 if highways.gates.has(selected_id) else (55.0 if selected_id == DOCK_ID else 75.0)
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
	_yaw -= relative.x * 0.004
	_pitch = clampf(_pitch - relative.y * 0.003, -1.35, 1.35)
	ship.rotation = Vector3(_pitch, _yaw, 0)


func reset_view() -> void:
	_update_camera(0.0)


func target_entry() -> Dictionary:
	var hostile := combat.enemy(selected_id) if combat != null else null
	if hostile != null:
		return {"id": selected_id, "name": "Freebooter " + selected_id.trim_prefix("patrol_"), "kind": "hostile", "notes": "Hull %d / Shield %d" % [roundi(hostile.get_meta("hull")), roundi(hostile.get_meta("shield"))]}
	return layout.target(selected_id)
