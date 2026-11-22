class_name ArtoisShipDefence
extends RefCounted
## Player power and physical plating. Cruise and dodge do not consume power.
const ENERGY_MAX := 100.0
const ARMOUR_MAX := 80.0
const GUARD_COS := 0.5 # 120 degree forward arc.
var energy := ENERGY_MAX
var armour := ARMOUR_MAX
var guard_active := false
var guard_direction := Vector3.ZERO
var _quiet := 0.0
var _broken := 0.0
var _boost_exhausted := false
var _guard: Node3D
var _particles: Array[CPUParticles3D] = []

func configure(ship: Node3D) -> void:
	if _guard != null: return
	_guard = Node3D.new()
	_guard.name = "KnightShield"
	ship.add_child(_guard)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-2.8, 2.2, -4), Vector3(2.8, 2.2, -4), Vector3(3, 0, -4), Vector3(0, -3, -4), Vector3(-3, 0, -4)]
	for i in points.size():
		for vertex in [Vector3(0, 0, -5.2), points[i], points[(i + 1) % points.size()]]: surface.add_vertex(vertex)
	surface.generate_normals()
	var plate := MeshInstance3D.new()
	plate.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.3, 0.75, 1.0, 0.32)
	material.emission_enabled = true
	material.emission = Color(0.3, 0.65, 0.9)
	plate.material_override = material
	_guard.add_child(plate)
	for i in points.size():
		var edge := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % points.size()]
		mesh.size = Vector3(0.14, 0.14, a.distance_to(b))
		edge.mesh = mesh
		edge.position = (a + b) * 0.5
		_guard.add_child(edge)
		edge.look_at_from_position(edge.position, b, Vector3.FORWARD)
		var rim := StandardMaterial3D.new()
		rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rim.albedo_color = Color("ffd992")
		rim.emission_enabled = true
		rim.emission = Color("ffd992")
		edge.material_override = rim
	for x in [-0.48, 0.48]:
		var particles := CPUParticles3D.new()
		particles.name = "CruiseSpool"
		particles.position = Vector3(x, 0, 3.12)
		particles.amount = 32
		particles.lifetime = 0.65
		particles.local_coords = true
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		particles.emission_sphere_radius = 0.25
		particles.direction = Vector3.BACK
		particles.spread = 28.0
		particles.gravity = Vector3.ZERO
		particles.initial_velocity_min = 2.0
		particles.initial_velocity_max = 5.0
		var dot := SphereMesh.new()
		dot.radius = 0.065
		dot.height = 0.13
		particles.mesh = dot
		particles.material_override = material.duplicate()
		particles.color = Color("b9efff")
		ship.add_child(particles)
		particles.emitting = false
		_particles.append(particles)
	update_visual(0)

func repair() -> void:
	energy = ENERGY_MAX
	armour = ARMOUR_MAX
	guard_active = false
	_quiet = 1.0
	_broken = 0.0
	_boost_exhausted = false
	update_visual(0)

func spend(amount: float) -> bool:
	if energy + 0.00001 < amount: return false
	energy = maxf(0, energy - amount)
	_quiet = 0
	return true

func advance(delta: float, requested: bool, dead: bool) -> void:
	_quiet += delta
	_broken = maxf(0, _broken - delta)
	guard_active = requested and not dead and _broken == 0 and energy >= 8.0
	if guard_active:
		if not spend(14.0 * delta):
			guard_active = false
			_broken = 1.0
	elif not dead and _quiet > 0.75:
		energy = minf(ENERGY_MAX, energy + 18.0 * minf(delta, _quiet - 0.75))

func afterburner(delta: float, requested: bool) -> bool:
	if not requested:
		_boost_exhausted = false
		return false
	if _boost_exhausted: return false
	if not spend(25.0 * delta):
		energy = 0
		_quiet = 0
		_boost_exhausted = true
		return false
	return true

func block(amount: float, source: Vector3, ship: Node3D) -> float:
	if not guard_active or not source.is_finite(): return amount
	var incoming := ship.global_position.direction_to(source)
	if incoming.dot(guard_direction.normalized() if guard_direction.length_squared() > 0.01 else -ship.global_basis.z) < GUARD_COS: return amount
	var blocked := minf(amount * 0.95, energy / 0.45)
	spend(blocked * 0.45)
	if energy < 0.01:
		guard_active = false
		_broken = 1.0
	return amount - blocked

func update_visual(spool_fraction: float) -> void:
	if _guard != null:
		_guard.visible = guard_active
		if guard_direction.length_squared() > 0.01:
			_guard.global_basis = Basis.looking_at(guard_direction, Vector3.RIGHT if absf(guard_direction.y) > 0.98 else Vector3.UP)
	for particles in _particles:
		particles.emitting = spool_fraction > 0
		particles.speed_scale = 1.0 + (1.0 - spool_fraction) * 2.0
