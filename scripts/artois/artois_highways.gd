class_name ArtoisHighways
extends Node3D
## Bidirectional filament routes, swept gate capture and a damped magnetic pull.
const SPEED := 350.0 # Ten times standard 35 m/s thrust.
const ENTRY_RADIUS := 18.0
const REENTRY_DELAY := 1.4
var world: Node3D
var routes: Array[Dictionary] = []
var gates := {}
var active_route := -1
var travel_sign := 1.0
var lockout := 0.0
var _sparks: Array[MultiMeshInstance3D] = []
var _time := 0.0
var _filament_materials: Array[ShaderMaterial] = []


func configure(space: Node3D) -> void:
	world = space
	for entry in world.layout.highways:
		var start: Vector3 = world.layout.world({"map": entry.from})
		var end: Vector3 = world.layout.world({"map": entry.to})
		var axis := start.direction_to(end)
		var route := {"id": entry.id, "name": entry.name, "start": start, "end": end, "axis": axis, "length": start.distance_to(end)}
		routes.append(route)
		for endpoint in ["a", "b"]:
			var id: String = "highway_" + str(entry.id) + "_" + endpoint
			var at := start if endpoint == "a" else end
			var inward := axis if endpoint == "a" else -axis
			gates[id] = {"position": at, "axis": inward, "route": routes.size() - 1, "sign": 1.0 if endpoint == "a" else -1.0}
			var gate := _gate(id, at, inward)
			world.landmarks[id] = gate
		_build_filament(route)


func attached() -> bool:
	return active_route >= 0


func direction() -> Vector3:
	return routes[active_route].axis * travel_sign if attached() else Vector3.ZERO


func approach_position(id: String) -> Vector3:
	var gate: Dictionary = gates[id]
	return gate.position - gate.axis * 90.0


func tick(delta: float) -> void:
	lockout = maxf(0.0, lockout - delta)
	_time += delta
	for material in _filament_materials: material.set_shader_parameter("ship_position", world.ship.position)
	for i in _sparks.size():
		var route := routes[i]
		var basis := _axis_basis(route.axis)
		for j in _sparks[i].multimesh.instance_count:
			var phase := fposmod(float(j) / 28.0 + _time * (0.14 if j % 2 == 0 else -0.14), 1.0)
			var offset := basis.x * sin(j * 2.4 + _time) * 3 + basis.z * cos(j * 1.7 + _time) * 3
			var at: Vector3 = route.start.lerp(route.end, phase) + offset
			_sparks[i].multimesh.set_instance_transform(j, Transform3D(Basis.IDENTITY, at))


func try_enter(from: Vector3, to: Vector3) -> bool:
	if attached() or lockout > 0 or world.combat.dead or world.disruption_remaining > 0: return false
	var movement := to - from
	var best := INF
	var chosen := ""
	for id in gates:
		var gate: Dictionary = gates[id]
		var towards: float = movement.dot(gate.axis)
		if towards <= 0.00001: continue
		var before: float = (from - gate.position).dot(gate.axis)
		var after: float = (to - gate.position).dot(gate.axis)
		if before > 0 or after < 0: continue
		if (-world.ship.basis.z).dot(gate.axis) < 0.2: continue
		var fraction := -before / towards
		var crossing := from.lerp(to, fraction)
		if crossing.distance_to(gate.position) > ENTRY_RADIUS: continue
		if fraction < best:
			best = fraction
			chosen = id
	if chosen.is_empty(): return false
	var gate: Dictionary = gates[chosen]
	active_route = gate.route
	travel_sign = gate.sign
	world.cruise = false
	world.autopilot = false
	world.dodge_velocity = Vector3.ZERO
	world.reset_taps()
	var destination := "highway_" + str(routes[active_route].id) + ("_b" if travel_sign > 0 else "_a")
	world.select_target(destination)
	world.arrival_message = "FILAMENT CAPTURE / SHIFT + DIRECTION TO BREAK FREE"
	return true


func advance(delta: float, steering: Vector2) -> void:
	if not attached(): return
	var route := routes[active_route]
	var axis := direction()
	# Small integration steps keep the spring stable during a slow frame.
	var steps := maxi(1, ceili(delta / (1.0 / 60.0)))
	var step := delta / steps
	for i in steps:
		var along: float = (world.ship.position - route.start).dot(route.axis)
		var centre: Vector3 = route.start + route.axis * along
		var offset: Vector3 = world.ship.position - centre
		var forward_speed: float = world.velocity.dot(axis)
		var lateral: Vector3 = world.velocity - axis * forward_speed
		var input: Vector3 = world.ship.basis.x * steering.x + world.ship.basis.y * steering.y
		input -= axis * input.dot(axis)
		lateral += (-offset * 22.0 - lateral * 8.0 + input * 45.0) * step
		forward_speed = move_toward(forward_speed, SPEED, 210.0 * step)
		world.velocity = axis * forward_speed + lateral
		world.ship.position += world.velocity * step
		var progress: float = (world.ship.position - route.start).dot(route.axis)
		if (travel_sign > 0 and progress >= float(route.length)) or (travel_sign < 0 and progress <= 0):
			world.ship.position = (route.end if travel_sign > 0 else route.start) + axis * 25.0
			world.velocity = axis * world.NORMAL_SPEED
			world.arrival_message = "FILAMENT ARRIVAL / MANUAL FLIGHT"
			reset()
			break
	var up := Vector3.RIGHT if absf(axis.y) > 0.98 else Vector3.UP
	world.ship.basis = Basis(world.ship.basis.get_rotation_quaternion().slerp(Basis.looking_at(axis, up).get_rotation_quaternion(), 1.0 - exp(-delta * 2.0)))
	world._sync_angles()


func escape(push: Vector3) -> void:
	if not attached(): return
	var axis := direction()
	reset()
	world.cruise = false
	world.autopilot = false
	world.velocity = axis * 55.0 + push.normalized() * 125.0
	world.arrival_message = "FILAMENT BREAKOUT / MANUAL FLIGHT"


func reset() -> void:
	active_route = -1
	lockout = REENTRY_DELAY


func status() -> String:
	if not attached(): return ""
	var route := routes[active_route]
	var end: Vector3 = route.end if travel_sign > 0 else route.start
	return "FILAMENT 10x / %s / %d m TO EXIT / SHIFT + DIRECTION TO BREAK FREE" % [route.name, roundi(world.ship.position.distance_to(end))]


func _axis_basis(axis: Vector3) -> Basis:
	var helper := Vector3.UP if absf(axis.y) < 0.98 else Vector3.RIGHT
	var right := helper.cross(axis).normalized()
	return Basis(right, axis, right.cross(axis)).orthonormalized()


func _gate(id: String, at: Vector3, axis: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = id
	add_child(root)
	root.position = at
	root.basis = _axis_basis(axis)
	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 19.5 if i == 0 else 23.5
		torus.outer_radius = 21.0 if i == 0 else 24.5
		torus.rings = 48
		torus.ring_segments = 10
		ring.mesh = torus
		ring.material_override = world._material("f6b84f" if i == 0 else "756043", i == 0)
		ring.position.y = -2 if i == 0 else 2
		root.add_child(ring)
	for i in 4:
		var brace := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(6, 5, 2.5)
		brace.mesh = box
		brace.position = Vector3(cos(i * PI / 2), 0, sin(i * PI / 2)) * 22
		brace.rotation.y = -i * PI / 2
		brace.material_override = world._material("a78a53", false)
		root.add_child(brace)
	return root


func _build_filament(route: Dictionary) -> void:
	var basis := _axis_basis(route.axis)
	var centre: Vector3 = (route.start + route.end) * 0.5
	for radius in [0.65, 2.8, 7.0]:
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = route.length
		mesh.radial_segments = 12
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = centre
		node.basis = basis
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/artois/filament.gdshader")
		material.set_shader_parameter("span", route.length)
		material.set_shader_parameter("density", 0.85 if radius < 1 else (0.16 if radius < 3 else 0.07))
		node.material_override = material
		_filament_materials.append(material)
		add_child(node)
	# Deterministic moving motes in both directions, instanced per route.
	var motes := MultiMeshInstance3D.new()
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	var spark := SphereMesh.new()
	spark.radius = 0.55
	spark.height = 1.1
	spark.radial_segments = 6
	spark.rings = 3
	instances.mesh = spark
	instances.instance_count = 28
	motes.multimesh = instances
	motes.material_override = world._material("ffe0a1", true)
	add_child(motes)
	_sparks.append(motes)
