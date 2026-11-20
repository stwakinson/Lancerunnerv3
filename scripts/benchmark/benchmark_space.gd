class_name BenchmarkSpace
extends Node3D

# A bounded art test, not the Artois system simulation. Small local coordinates
# and seeded rocks make compositions and capture runs reproducible.

const Ship = preload("res://scripts/benchmark/voxel_ship.gd")
const Effects = preload("res://scripts/benchmark/space_effects.gd")
var ship: Node3D
var camera: Camera3D
var station: Node3D
var speed := 0.0
var elapsed := 0.0
var shots: Array[MeshInstance3D] = []
var _fire_wait := 0.0
var _rng := RandomNumberGenerator.new()
var _materials := {}
var _effects: BenchmarkSpaceEffects
var _sun: MeshInstance3D
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var asteroid_count := 0
var sky_material: ShaderMaterial


func _ready() -> void:
	_rng.seed = 1415
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/benchmark/nebula.gdshader")
	material.set_shader_parameter("panorama", preload("res://assets/benchmark/artois_nebula.png"))
	sky_material = material
	sky.sky_material = material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8da9e5")
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Compatibility keeps the depth-tested corona and additive trails; optional
	# HDR bloom is only enabled on renderers that support it.
	environment.glow_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	environment.glow_intensity = 0.45
	environment.glow_hdr_threshold = 1.1
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.position = Vector3(310, 70, -700)
	light.light_color = Color("ffd3b5")
	light.light_energy = 1.25
	light.shadow_enabled = true
	add_child(light)
	light.look_at(Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 25, 0)
	rim.light_color = Color("809be6")
	rim.light_energy = 0.55
	add_child(rim)
	ship = Ship.new()
	ship.name = "ReferenceShipPlaceholder"
	add_child(ship)
	camera = Camera3D.new()
	camera.fov = 54
	camera.far = 1800
	add_child(camera)
	camera.current = true
	_build_world()
	_effects = Effects.new()
	_effects.name = "EngineTrails"
	add_child(_effects)
	_update_camera(0.0)


func _build_world() -> void:
	_make_station()
	_make_rocks()
	_make_planet()
	_make_sun()


func _make_planet() -> void:
	var planet := MeshInstance3D.new()
	planet.name = "ArtoisPlanet"
	var sphere := SphereMesh.new()
	sphere.radius = 290
	sphere.height = 580
	sphere.radial_segments = 128
	sphere.rings = 64
	planet.mesh = sphere
	var planet_material := ShaderMaterial.new()
	planet_material.shader = preload("res://shaders/benchmark/planet.gdshader")
	planet_material.set_shader_parameter("surface_map", preload("res://assets/textures/planet/Planet_Jupiter_4k.jpg"))
	planet.material_override = planet_material
	planet.position = Vector3(-260, -265, -610)
	add_child(planet)
	var atmosphere := MeshInstance3D.new()
	atmosphere.name = "Atmosphere"
	atmosphere.mesh = sphere
	atmosphere.scale = Vector3.ONE * 1.014
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/benchmark/atmosphere.gdshader")
	atmosphere.material_override = material
	planet.add_child(atmosphere)


func _make_sun() -> void:
	_sun = MeshInstance3D.new()
	_sun.name = "DepthTestedSunCorona"
	var quad := QuadMesh.new()
	quad.size = Vector2(170, 170)
	_sun.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/benchmark/sun.gdshader")
	_sun.material_override = material
	_sun.position = Vector3(310, 70, -700)
	add_child(_sun)


func _material(hex: String, glow := false) -> StandardMaterial3D:
	var key := hex + str(glow)
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.html(hex)
		mat.roughness = 0.9
		if glow:
			mat.emission_enabled = true
			mat.emission = Color.html(hex)
			mat.emission_energy_multiplier = 1.7
		_materials[key] = mat
	return _materials[key]


func _block(parent: Node3D, at: Vector3, dimensions: Vector3, colour: String, glow := false) -> void:
	var object := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	object.mesh = box
	object.material_override = _material(colour, glow)
	object.position = at
	parent.add_child(object)


func _make_station() -> void:
	station = Node3D.new()
	station.name = "AgincourtCastlePlaceholder"
	station.position = Vector3(19, 1, -110)
	add_child(station)
	_block(station, Vector3(0, -4, 0), Vector3(23, 3, 17), "273b49")
	_block(station, Vector3(0, 0, 0), Vector3(19, 6, 12), "57616a")
	_block(station, Vector3(0, 5, 2), Vector3(8, 9, 7), "6f7478")
	for x in [-10.0, 10.0]:
		for z in [-6.0, 6.0]:
			_block(station, Vector3(x, 3, z), Vector3(4, 14, 4), "65707b")
			_block(station, Vector3(x, 10, z), Vector3(5, 1.2, 5), "283f50")
			for dx in [-1.6, 1.6]:
				_block(station, Vector3(x + dx, 11, z), Vector3(1, 1, 5), "7a8084")
			_block(station, Vector3(x, 7, z + 2.04), Vector3(0.65, 1.8, 0.04), "f2ba6a", true)
	for x in [-6.0, 6.0]:
		_block(station, Vector3(x, 0.5, 6.25), Vector3(1.2, 3.0, 0.2), "883b49")
		_block(station, Vector3(x, 0.8, 6.37), Vector3(0.2, 2.0, 0.04), "e2b974")
	for x in range(-8, 9, 4):
		_block(station, Vector3(x, -1.5, 6.18), Vector3(0.6, 3, 0.2), "343c52")
	# A dark docking mouth with a warm illuminated frame.
	_block(station, Vector3(0, -0.5, 6.1), Vector3(7, 4.8, 0.3), "07141d")
	for x in [-4.0, 4.0]:
		_block(station, Vector3(x, -0.5, 6.4), Vector3(0.3, 5, 0.3), "e9af66", true)
	_block(station, Vector3(0, 2, 6.4), Vector3(8, 0.3, 0.3), "e9af66", true)
	for x in range(-8, 9, 2):
		_block(station, Vector3(x, 1.5, 6.15), Vector3(0.45, 0.6, 0.1), "e7b47a", true)
	for z in range(10, 38, 5):
		_block(station, Vector3(-3, -3, z), Vector3(0.2, 0.12, 0.6), "69cddc", true)
		_block(station, Vector3(3, -3, z), Vector3(0.2, 0.12, 0.6), "69cddc", true)


func _rock_material(colour: String) -> ShaderMaterial:
	var key := "rock:" + colour
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/benchmark/asteroid.gdshader")
		material.set_shader_parameter("stone", Color.html(colour))
		_materials[key] = material
	return _materials[key]


func _make_rocks() -> void:
	var source := SphereMesh.new()
	source.radius = 1.0
	source.height = 2.0
	source.radial_segments = 9
	source.rings = 5
	var rock_mesh := _faceted(source)
	for i in 55:
		var rock := MeshInstance3D.new()
		rock.mesh = rock_mesh
		rock.material_override = _rock_material(["61525a", "45435b", "72636b"][i % 3])
		var side := -1.0 if i % 2 else 1.0
		rock.position = Vector3(side * _rng.randf_range(13, 105), _rng.randf_range(-35, 42), _rng.randf_range(-300, -20))
		rock.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		rock.scale = Vector3(_rng.randf_range(1.4, 6), _rng.randf_range(1.2, 5), _rng.randf_range(1.5, 6))
		add_child(rock)
		asteroid_count += 1
	# One instanced draw for distant field depth, instead of hundreds of Nodes.
	var distant := MultiMeshInstance3D.new()
	distant.name = "DistantAsteroidField"
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = rock_mesh
	instances.instance_count = 300
	distant.multimesh = instances
	distant.material_override = _rock_material("514254")
	for i in instances.instance_count:
		var side := -1.0 if i % 2 else 1.0
		var position := Vector3(side * _rng.randf_range(30, 380), _rng.randf_range(-150, 180), _rng.randf_range(-1000, -220))
		var rotation := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		var radius := _rng.randf_range(0.5, 4.0)
		instances.set_instance_transform(i, Transform3D(rotation.scaled(Vector3.ONE * radius), position))
		asteroid_count += 1
	add_child(distant)


func _faceted(source: SphereMesh) -> ArrayMesh:
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, indices.size(), 3):
		var triangle: Array[Vector3] = []
		for j in 3:
			var v := vertices[indices[i + j]]
			v *= 1.0 + sin(v.x * 7.0 + v.y * 11.0 + v.z * 5.0) * 0.13
			triangle.append(v)
		var normal := (triangle[0] - triangle[2]).cross(triangle[0] - triangle[1]).normalized()
		for v in triangle:
			surface.set_normal(normal)
			surface.add_vertex(v)
	return surface.commit()


func advance(delta: float, steering: Vector2, thrust: float, boosting: bool, firing: bool) -> void:
	elapsed += delta
	speed = move_toward(speed, thrust * (24.0 if boosting else 10.0), delta * 12.0)
	ship.position.x = clampf(ship.position.x + steering.x * delta * 7, -16, 16)
	ship.position.y = clampf(ship.position.y + steering.y * delta * 5, -9, 9)
	ship.position.z = clampf(ship.position.z - speed * delta, -65, 12)
	ship.rotation.z = lerp_angle(ship.rotation.z, -steering.x * 0.25, 1.0 - exp(-delta * 8))
	for i in ship.engines.size():
		ship.engines[i].scale.z = 1.0 + (0.6 if boosting else 0.15) * (1.0 + sin(elapsed * 23))
	_fire_wait -= delta
	if firing and _fire_wait <= 0.0:
		_fire_wait = 0.16
		var shot := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.07, 0.07, 1.8)
		shot.mesh = mesh
		shot.material_override = _material("8ae5ed", true)
		shot.position = ship.position + Vector3(0, 0.1, -3.2)
		add_child(shot)
		shots.append(shot)
	for i in range(shots.size() - 1, -1, -1):
		shots[i].position.z -= delta * 90
		if shots[i].position.z < -260:
			shots[i].queue_free()
			shots.remove_at(i)
	camera.fov = lerpf(camera.fov, 59.0 if boosting and absf(speed) > 1.0 else 54.0, 1.0 - exp(-delta * 3.0))
	_update_camera(delta)
	_effects.advance(delta, ship, camera, boosting)


func _update_camera(delta: float) -> void:
	var offset := Basis(Vector3.UP, _orbit_yaw) * Basis(Vector3.RIGHT, _orbit_pitch) * Vector3(4.8, 3.7, 11.7)
	var target := ship.position + offset
	camera.position = camera.position.lerp(target, 1.0 - exp(-delta * 5)) if delta > 0 else target
	camera.look_at(ship.position + Vector3(0, 0.3, -16), Vector3.UP)
	if _sun != null:
		_sun.look_at(camera.global_position, Vector3.UP)


func orbit(relative: Vector2) -> void:
	_orbit_yaw -= relative.x * 0.004
	_orbit_pitch = clampf(_orbit_pitch - relative.y * 0.003, -0.55, 0.55)


func reset_view() -> void:
	_orbit_yaw = 0.0
	_orbit_pitch = 0.0
	_update_camera(0.0)
