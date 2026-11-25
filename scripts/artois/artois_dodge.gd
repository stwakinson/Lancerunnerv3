extends RefCounted
## Analytically integrated thrust/slide/counter-thrust, with cosmetic hull attitude.
var ship: Node3D
var direction := Vector3.ZERO
var velocity := Vector3.ZERO
var age := 0.0
var peak := 110.0
var kick := 0.10
var slide := 0.12
var recovery := 0.34
var active := false
var bank := Vector3.ZERO
var _bodies: Array[Dictionary] = []
var _kick_jet: CPUParticles3D
var _counter_jet: CPUParticles3D

func configure(body: Node3D) -> void:
	ship = body
	_bodies.clear()
	var meshes: Array = ship.get_meta("original_hull_meshes", []).duplicate()
	meshes.append_array(ship.engines)
	for name in ["PurchasedHull", "FittedHardpoints"]:
		var node: Node3D = ship.get_node_or_null(name)
		if node != null: meshes.append(node)
	for node in meshes: _bodies.append({"node": node, "transform": node.transform})
	if _kick_jet == null:
		_kick_jet = _jet("DodgeKick", Color("ffd48a"))
		_counter_jet = _jet("DodgeCounterThrust", Color("8cddff"))

func start(world_direction: Vector3, profile: Dictionary) -> void:
	reset()
	direction = world_direction.normalized()
	peak = float(profile.speed)
	kick = float(profile.kick)
	slide = float(profile.slide)
	recovery = float(profile.recovery)
	active = true
	velocity = direction * peak * 0.2
	visualise(0.0)

func duration() -> float:
	return kick + slide + recovery

func phase() -> String:
	if not active: return "IDLE"
	if age < kick: return "KICK"
	if age < kick + slide: return "SLIDE"
	return "RECOVERY"

func _distance(time: float) -> float:
	var t := clampf(time, 0, duration())
	var a := minf(t, kick)
	var distance := peak * (0.2 * a + 0.4 * a * a / kick)
	t = maxf(0, t - kick)
	distance += peak * minf(t, slide)
	var c := clampf(t - slide, 0, recovery)
	return distance + peak * (c - c * c / (2 * recovery))

func advance(delta: float) -> Vector3:
	if not active: return Vector3.ZERO
	var before := _distance(age)
	age = minf(duration(), age + maxf(0, delta))
	var speed := peak
	if age < kick: speed *= 0.2 + 0.8 * age / kick
	elif age >= kick + slide: speed *= maxf(0, 1.0 - (age - kick - slide) / recovery)
	velocity = direction * speed
	if age >= duration():
		active = false
		velocity = Vector3.ZERO
	return direction * (_distance(age) - before)

func visualise(delta: float) -> void:
	if ship == null: return
	var local := ship.global_basis.inverse() * direction
	var strength := velocity.length() / peak if active else 0.0
	var target := Vector3(local.z * 0.12 + local.y * 0.08, 0, -local.x * 0.35) * strength
	bank = bank.lerp(target, 1.0 - exp(-delta * 18.0))
	if not active and bank.length_squared() < 0.000001: bank = Vector3.ZERO
	for body in _bodies:
		if is_instance_valid(body.node): body.node.transform = Transform3D(Basis.from_euler(bank), Vector3.ZERO) * body.transform
	for pair in [[_kick_jet, -local, phase() == "KICK"], [_counter_jet, local, phase() == "RECOVERY"]]:
		var jet: CPUParticles3D = pair[0]
		jet.visible = active
		jet.position = pair[1] * Vector3(1.5, 0.45, 2.5)
		jet.direction = pair[1]
		jet.emitting = pair[2]

func reset() -> void:
	active = false
	velocity = Vector3.ZERO
	direction = Vector3.ZERO
	age = 0
	bank = Vector3.ZERO
	for body in _bodies:
		if is_instance_valid(body.node): body.node.transform = body.transform
	for jet in [_kick_jet, _counter_jet]:
		if is_instance_valid(jet):
			jet.emitting = false
			jet.visible = false

func _jet(label: String, colour: Color) -> CPUParticles3D:
	var jet := CPUParticles3D.new()
	jet.name = label
	jet.amount = 24
	jet.lifetime = 0.18
	jet.local_coords = false
	jet.gravity = Vector3.ZERO
	jet.spread = 12
	jet.initial_velocity_min = 6
	jet.initial_velocity_max = 13
	jet.scale_amount_min = 0.4
	jet.scale_amount_max = 1
	jet.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	jet.emission_sphere_radius = 0.12
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.2, 0.3)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 3
	mesh.material = material
	jet.mesh = mesh
	jet.emitting = false
	jet.visible = false
	ship.add_child(jet)
	return jet
