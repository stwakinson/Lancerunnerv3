class_name Blast
extends Node3D

# A big fiery explosion for anything that gets destroyed (fighters, walking
# robots, the player): a white-hot flash, a rolling fireball that rises and
# darkens, thick smoke that lingers and climbs, sparks that arc back down,
# and burning chunks of wreckage that fly off trailing fire and smoke and come
# to rest on the ground. Built in code; frees itself when it's all burnt out.

const LIFETIME := 4.5

static var _chunk_material: StandardMaterial3D

var _flash: OmniLight3D
var _flash_energy := 10.0
var _smoke: FxParticles
var _age := 0.0
var _size := 1.0
var _chunks: Array[Dictionary] = []


# `size` 1 is a fighter; the player's ship and robots go a bit bigger.
static func spawn(at: Vector3, size: float = 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var up := Planet.instance.up_at(at) if Planet.instance != null else Vector3.UP

	var blast := Blast.new()
	blast.name = "Blast"
	blast._size = size
	blast.position = at

	# White-hot flash at the heart of it.
	var core := _emitter(blast, true)
	core.burst = 10
	core.lifetime = Vector2(0.12, 0.22)
	core.speed = Vector2(0.5 * size, 1.5 * size)
	core.size = Vector2(2.2 * size, 3.4 * size)
	core.start_color_a = Color(1.0, 0.97, 0.85)
	core.start_color_b = Color(1.0, 0.85, 0.5)
	core.size_end = 1.4
	core.alpha_keys = [[0.0, 1.0], [1.0, 0.0]]

	# Fireball: yellow-white to orange to deep red to soot, swelling as it rises.
	var fire := _emitter(blast, true)
	fire.burst = 40
	fire.max_particles = 40
	fire.lifetime = Vector2(0.55, 1.2)
	fire.speed = Vector2(1.5 * size, 6.0 * size)
	fire.size = Vector2(0.9 * size, 2.0 * size)
	fire.shape_radius = 0.5 * size
	fire.drag = 3.0
	fire.acceleration = up * 2.5 * size
	fire.start_color_a = Color(1.0, 0.75, 0.35)
	fire.start_color_b = Color(1.0, 0.5, 0.15)
	fire.color_keys = [[0.0, Color(1.0, 0.95, 0.8)], [0.25, Color(1.0, 0.55, 0.15)],
		[0.6, Color(0.85, 0.18, 0.04)], [1.0, Color(0.25, 0.06, 0.02)]]
	fire.alpha_keys = [[0.0, 1.0], [0.55, 0.85], [1.0, 0.0]]
	fire.size_end = 1.9

	# Smoke: dark, thick and slow, pouring out for the first moments then drifting up.
	var smoke := _emitter(blast, false)
	smoke.rate = 55.0
	smoke.max_particles = 60
	smoke.lifetime = Vector2(1.6, 3.0)
	smoke.speed = Vector2(0.8 * size, 3.0 * size)
	smoke.size = Vector2(1.3 * size, 2.4 * size)
	smoke.shape_radius = 0.6 * size
	smoke.drag = 1.6
	smoke.acceleration = up * 1.4 * size
	smoke.start_color_a = Color(0.16, 0.14, 0.13)
	smoke.start_color_b = Color(0.28, 0.25, 0.23)
	smoke.alpha_keys = [[0.0, 0.0], [0.12, 0.8], [0.6, 0.45], [1.0, 0.0]]
	smoke.size_end = 2.6
	blast._smoke = smoke

	# Sparks and embers that fly out fast and arc back down.
	var sparks := _emitter(blast, true)
	sparks.burst = 36
	sparks.max_particles = 36
	sparks.lifetime = Vector2(0.6, 1.4)
	sparks.speed = Vector2(7.0 * size, 18.0 * size)
	sparks.size = Vector2(0.08 * size, 0.2 * size)
	sparks.shape_radius = 0.3 * size
	sparks.drag = 1.2
	sparks.acceleration = -up * 7.0
	sparks.start_color_a = Color(1.0, 0.9, 0.5)
	sparks.start_color_b = Color(1.0, 0.55, 0.15)
	sparks.color_keys = [[0.0, Color.WHITE], [1.0, Color(1.0, 0.35, 0.1)]]
	sparks.alpha_keys = [[0.0, 1.0], [0.7, 0.9], [1.0, 0.0]]
	sparks.size_end = 0.3

	# Orange light that lights up everything nearby, then dies away.
	blast._flash = OmniLight3D.new()
	blast._flash.light_color = Color(1.0, 0.55, 0.2)
	blast._flash.omni_range = 14.0 * size
	blast._flash.light_energy = blast._flash_energy
	blast.add_child(blast._flash)

	tree.current_scene.add_child(blast)
	blast._spawn_chunks(roundi(4 + 2 * size), up)
	_shake_camera(tree, at, size)


static func _emitter(parent: Node3D, additive: bool) -> FxParticles:
	var ps := FxParticles.new()
	ps.additive = additive
	ps.shape = FxParticles.Shape.SPHERE
	ps.max_screen_size = 0.8
	parent.add_child(ps)
	return ps


# Big blasts nearby shake the camera; far away ones barely do.
static func _shake_camera(tree: SceneTree, at: Vector3, size: float) -> void:
	var cam := tree.root.get_viewport().get_camera_3d() as CameraFollow
	if cam == null:
		return
	var falloff := clampf(1.0 - cam.global_position.distance_to(at) / (60.0 * size), 0.0, 1.0)
	if falloff > 0.0:
		cam.shake(0.5 * size * falloff)


# Burning chunks of wreckage, each trailing fire and smoke.
func _spawn_chunks(count: int, up: Vector3) -> void:
	if _chunk_material == null:
		_chunk_material = StandardMaterial3D.new()
		# Charred metal with a faint ember glow (the fire trail does the burning).
		_chunk_material.albedo_color = Color(0.09, 0.08, 0.08)
		_chunk_material.metallic = 0.5
		_chunk_material.roughness = 0.75
		_chunk_material.emission_enabled = true
		_chunk_material.emission = Color(1.0, 0.3, 0.05)
		_chunk_material.emission_energy_multiplier = 0.15
	for i in count:
		var chunk := Node3D.new()
		chunk.top_level = true
		add_child(chunk)
		chunk.global_position = global_position
		# Jagged wedges and flat plates, a bit bigger for bigger blasts.
		var mesh := MeshInstance3D.new()
		var dims := Vector3(randf_range(0.12, 0.35), randf_range(0.05, 0.18), randf_range(0.15, 0.4)) * sqrt(_size)
		if randf() < 0.6:
			var wedge := PrismMesh.new()
			wedge.left_to_right = randf()
			wedge.size = dims
			mesh.mesh = wedge
		else:
			var plate := BoxMesh.new()
			plate.size = dims
			mesh.mesh = plate
		mesh.material_override = _chunk_material
		chunk.add_child(mesh)

		var trail := FxParticles.new()
		trail.rate = 30.0
		trail.max_particles = 30
		trail.lifetime = Vector2(0.3, 0.7)
		trail.speed = Vector2(0.2, 0.8)
		trail.size = Vector2(0.3, 0.6) * sqrt(_size)
		trail.start_color_a = Color(1.0, 0.6, 0.2)
		trail.start_color_b = Color(1.0, 0.35, 0.1)
		trail.color_keys = [[0.0, Color.WHITE], [0.5, Color(0.9, 0.3, 0.08)], [1.0, Color(0.2, 0.05, 0.02)]]
		trail.alpha_keys = [[0.0, 0.9], [1.0, 0.0]]
		trail.size_end = 1.8
		chunk.add_child(trail)

		var smoke := FxParticles.new()
		smoke.additive = false
		smoke.rate = 14.0
		smoke.max_particles = 26
		smoke.lifetime = Vector2(0.9, 1.8)
		smoke.speed = Vector2(0.1, 0.5)
		smoke.size = Vector2(0.5, 0.9) * sqrt(_size)
		smoke.acceleration = up * 0.8
		smoke.start_color_a = Color(0.18, 0.16, 0.15)
		smoke.start_color_b = Color(0.3, 0.27, 0.25)
		smoke.alpha_keys = [[0.0, 0.0], [0.15, 0.6], [1.0, 0.0]]
		smoke.size_end = 2.2
		chunk.add_child(smoke)

		var dir := (FxParticles.random_on_unit_sphere() + up * 0.8).normalized()
		_chunks.append({
			"node": chunk,
			"velocity": dir * randf_range(6.0, 14.0) * _size,
			"spin": FxParticles.random_on_unit_sphere() * randf_range(4.0, 10.0),
			"burn": randf_range(1.2, 2.6),
			"fire": trail,
			"smoke": smoke,
			"landed": false,
		})


func _process(delta: float) -> void:
	_age += delta
	_flash.light_energy = _flash_energy * pow(clampf(1.0 - _age / 0.7, 0.0, 1.0), 2.0)
	# Smoke pours out only at first; what's out lingers and drifts.
	if _age > 0.45:
		_smoke.emitting = false

	var planet := Planet.instance
	for c in _chunks:
		var node := c.node as Node3D
		var age_left: float = c.burn - _age
		if age_left <= 0.0:
			(c.fire as FxParticles).emitting = false
			(c.smoke as FxParticles).emitting = false
			node.scale = node.scale.move_toward(Vector3.ZERO, delta * 1.5)
		if c.landed:
			continue
		var up := planet.up_at(node.global_position) if planet != null else Vector3.UP
		c.velocity = (c.velocity as Vector3) * maxf(0.0, 1.0 - 0.4 * delta) - up * 9.0 * delta
		node.global_position += (c.velocity as Vector3) * delta
		node.rotate((c.spin as Vector3).normalized(), (c.spin as Vector3).length() * delta)
		# Wreckage comes to rest on the ground and keeps smouldering.
		if planet != null and planet.altitude(node.global_position) < 0.1:
			node.global_position = planet.push_out(node.global_position, 0.1)
			c.landed = true

	if _age > LIFETIME:
		queue_free()
