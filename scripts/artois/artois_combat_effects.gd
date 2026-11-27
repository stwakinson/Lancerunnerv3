extends Node3D
## Bounded, instanced visual debris: no physics bodies, collisions or shadow lights.
const LIMIT := 32
var bursts: Array[Dictionary] = []
var _random := RandomNumberGenerator.new()

func _init() -> void:
	_random.randomize()

func emit_burst(at: Vector3, kind := "destruction", radius := 5.5, drift := Vector3.ZERO) -> void:
	if bursts.size() >= LIMIT: _remove(0)
	var major := kind in ["destruction", "missile", "ward_missile", "disruptor"]
	var cool := kind in ["shield", "ward_missile", "disruptor"]
	var colour := Color("8cecff") if cool else Color("ffae52")
	var lifetime := 2.8 if kind == "destruction" else (1.1 if major else 0.45)
	var root := Node3D.new()
	add_child(root)
	root.position = at
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 4
	core.mesh = sphere
	var flash := _material(Color("e6faff") if cool else Color("fff0c5"))
	core.material_override = flash
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	var halo := _material(colour)
	ring.material_override = halo
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var particles := MultiMeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = 36 if major else 10
	particles.multimesh = multimesh
	var debris := _material(colour)
	particles.material_override = debris
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.custom_aabb = AABB(Vector3.ONE * -radius * 15, Vector3.ONE * radius * 30)
	root.add_child(particles)
	var vectors: Array[Vector3] = []
	var sizes: Array[float] = []
	for i in multimesh.instance_count:
		var direction := Vector3(_random.randf_range(-1, 1), _random.randf_range(-1, 1), _random.randf_range(-1, 1)).normalized()
		vectors.append(direction * radius * _random.randf_range(2.0, 5.0))
		sizes.append(radius * _random.randf_range(0.035, 0.12))
		multimesh.set_instance_color(i, colour.lerp(Color("fff4dc"), _random.randf() * 0.8))
	bursts.append({"node": root, "core": core, "ring": ring, "particles": particles, "flash": flash, "halo": halo, "debris": debris, "vectors": vectors, "sizes": sizes, "age": 0.0, "life": lifetime, "radius": radius, "kind": kind, "drift": drift})
	_update(bursts.back())

func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 2.0
	material.vertex_color_use_as_albedo = true
	return material

func advance(delta: float) -> void:
	for i in range(bursts.size() - 1, -1, -1):
		var burst := bursts[i]
		burst.age += delta
		if burst.age >= burst.life:
			_remove(i)
			continue
		burst.node.position += burst.drift * delta
		_update(burst)

func _update(burst: Dictionary) -> void:
	var age: float = burst.age
	var progress: float = age / burst.life
	var radius: float = burst.radius
	burst.core.scale = Vector3.ONE * maxf(0.01, radius * (0.35 + age * 4.5))
	burst.flash.albedo_color.a = pow(maxf(0.0, 1.0 - age / 0.28), 2)
	burst.ring.scale = Vector3.ONE * radius * (0.4 + age * 6.0)
	burst.halo.albedo_color.a = maxf(0.0, 1.0 - age / 0.65) * 0.65
	burst.debris.albedo_color.a = pow(1.0 - progress, 1.5)
	var mesh: MultiMesh = burst.particles.multimesh
	for i in mesh.instance_count:
		var size: float = burst.sizes[i] * maxf(0.05, 1.0 - progress)
		var orientation := Basis.from_euler(Vector3(age * (i + 1), age * 2.0, age * 0.7)).scaled(Vector3(size, size, size * 2.5))
		mesh.set_instance_transform(i, Transform3D(orientation, burst.vectors[i] * age))

func _remove(index: int) -> void:
	bursts[index].node.hide()
	bursts[index].node.queue_free()
	bursts.remove_at(index)
