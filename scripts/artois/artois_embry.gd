class_name ArtoisEmbry
extends RefCounted
## Seeded column canyon and a batched industrial station, local to Embry.
var column_bounds: Array[AABB] = []
var approach_lines: Array = []
var _parts := {}


func make_field(world: Node3D, field: Dictionary) -> MultiMeshInstance3D:
	var random := RandomNumberGenerator.new()
	random.seed = int(field.seed)
	var centre: Vector3 = world.layout.world(field)
	var station: Vector3 = world.layout.world(world.layout.target("embry"))
	var harbour := station + Vector3(0, 20, 95)
	# Reserve actual last-leg approaches used by local route planning.
	approach_lines.clear()
	for id in ["planet_dock", "caulers", "acheau", "renty", "border_post", "southern_outpost"]:
		approach_lines.append([world.layout.world(world.layout.target(id)) + Vector3(0, 20, 95), harbour])
	for route in world.layout.highways:
		approach_lines.append([world.layout.world({"map": route.from}), harbour])
		approach_lines.append([world.layout.world({"map": route.to}), harbour])
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = _column_mesh()
	instances.instance_count = int(field.count)
	var node := MultiMeshInstance3D.new()
	node.name = field.id
	node.multimesh = instances
	node.position = centre
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/artois/embry_stone.gdshader")
	node.material_override = material
	column_bounds.clear()
	var anchors := [Vector3(0, 0, -170), Vector3(-175, 5, -80), Vector3(180, -30, -165)]
	var sizes := [Vector3(135, 490, 110), Vector3(105, 570, 100), Vector3(110, 530, 100)]
	for i in instances.instance_count:
		var scale: Vector3 = sizes[i] if i < 3 else Vector3(random.randf_range(45, 110), random.randf_range(260, 620), random.randf_range(40, 105))
		if i >= int(field.get("major_columns", 64)):
			scale = Vector3(random.randf_range(8, 28), random.randf_range(28, 130), random.randf_range(8, 28))
		var position: Vector3 = station + anchors[i] if i < 3 else Vector3.ZERO
		var rotation := Basis.from_euler(Vector3(0, random.randf_range(-0.16, 0.16) + (i % 4) * PI / 2.0, 0))
		for attempt in 2048:
			if i >= 3 or attempt > 0:
				var flat := Vector2(random.randf_range(-1, 1), random.randf_range(-1, 1))
				if flat.length_squared() > 1: continue
				position = centre + Vector3(flat.x * float(field.radii[0]) * world.layout.scale_factor, random.randf_range(-90, 90), flat.y * float(field.radii[1]) * world.layout.scale_factor)
			var world_transform := Transform3D(rotation.scaled(scale), position)
			var bounds: AABB = world_transform * instances.mesh.get_aabb()
			if _clear(bounds, world, station): break
		# Keep transforms field-local; stored bounds remain world-local for checks.
		var transform := Transform3D(rotation.scaled(scale), position - centre)
		instances.set_instance_transform(i, transform)
		column_bounds.append(Transform3D(rotation.scaled(scale), position) * instances.mesh.get_aabb())
	node.set_meta("profile", "column_canyon")
	return node


func _clear(bounds: AABB, world: Node3D, station: Vector3) -> bool:
	if bounds.grow(40).has_point(station): return false
	var centre := bounds.get_center()
	var radius := Vector2(bounds.size.x, bounds.size.z).length() * 0.5 + 30
	var point := Vector2(centre.x, centre.z)
	for line in approach_lines:
		var a := Vector2(line[0].x, line[0].z)
		var b := Vector2(line[1].x, line[1].z)
		if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) < radius: return false
	for entry in world.layout.locations:
		if entry.id == "embry": continue
		var target: Vector3 = world.layout.world(entry)
		if bounds.grow(85).has_point(target): return false
	return true


func _column_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var box := BoxMesh.new()
		var width: float = [0.82, 0.94, 0.86, 1.0, 0.9, 0.78, 0.85, 0.65, 0.49][i]
		box.size = Vector3(width, 0.125, 0.75 if i % 3 else 0.95)
		var at := Vector3(0.045 if i % 2 else -0.025, -0.5 + i * 0.11, 0.035 if i % 3 else -0.02)
		surface.append_from(box, 0, Transform3D(Basis.IDENTITY, at))
	for side in [-1.0, 1.0]:
		var finger := BoxMesh.new()
		finger.size = Vector3(0.19, 0.38, 0.23)
		surface.append_from(finger, 0, Transform3D(Basis.IDENTITY, Vector3(side * 0.29, 0.28 + side * 0.04, 0.24)))
	return surface.commit()


func _box(at: Vector3, size: Vector3, colour: String) -> void:
	if not _parts.has(colour): _parts[colour] = []
	_parts[colour].append({"position": at, "size": size})


func make_station() -> Node3D:
	_parts.clear()
	_box(Vector3(0, 18, -5), Vector3(64, 172, 44), "b65d2e")
	for x in [-21.0, 0.0, 21.0]:
		_box(Vector3(x, 18, 17.5), Vector3(20, 166, 1), "d7782e" if x != 0 else "c36329")
	_box(Vector3(0, 107, -5), Vector3(70, 6, 50), "756859")
	var random := RandomNumberGenerator.new()
	random.seed = 1415
	for y in range(-60, 101, 10):
		for x in [-27.0, -9.0, 9.0, 27.0]:
			if random.randf() < 0.35:
				_box(Vector3(x, y, 18.3), Vector3(8, 7, 0.5), "597180" if random.randf() < 0.45 else "a45a32")
			if random.randf() < 0.28:
				_box(Vector3(x, y + 2, 18.7), Vector3(2, 3, 0.3), "263e53")
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 33, 15, -5), Vector3(2, 162, 42), "5d6d7a")
		_box(Vector3(side * 30, 18, 19), Vector3(1.4, 170, 1.4), "e69a45")
		_box(Vector3(side * 15, -115, -5), Vector3(1.5, 95, 1.5), "4b5666")
		_box(Vector3(side * 8, -128, -5), Vector3(2, 100, 2), "655b53")
	for y in [-30.0, 20.0, 72.0]:
		_box(Vector3(43, y, 1), Vector3(18, 3, 22), "415568")
		_box(Vector3(52, y + 3, 1), Vector3(1, 5, 22), "9b804c")
		_box(Vector3(43, y + 3, 12), Vector3(18, 5, 1), "9b804c")
	_box(Vector3(0, -80, -5), Vector3(30, 22, 25), "3c4f61")
	_box(Vector3(0, -106, -5), Vector3(18, 30, 15), "72685b")
	for y in [-90.0, -107.0, -123.0]: _box(Vector3(0, y, -5), Vector3(34, 2, 27), "394d60")
	# Back and side braces tuck the station against its neighbouring columns.
	_box(Vector3(0, 35, -75), Vector3(18, 5, 115), "536174")
	_box(Vector3(-65, 10, -35), Vector3(100, 5, 12), "58616a")
	# The existing traffic harbour stays at (0, 20, 95), above this pad.
	_box(Vector3(0, 3, 58), Vector3(62, 4, 100), "3d5268")
	for side in [-1.0, 1.0]:
		for z in [24.0, 44.0, 64.0, 84.0, 104.0]:
			_box(Vector3(side * 27, 5.4, z), Vector3(2, 0.6, 5), "f3c46c")
		_box(Vector3(side * 34, 27, 30), Vector3(2, 48, 2), "536375")
	_box(Vector3(0, 51, 30), Vector3(70, 2, 2), "536375")
	_box(Vector3(-26, 135, -10), Vector3(2, 63, 2), "687786")
	_box(Vector3(-26, 165, -10), Vector3(4, 2, 4), "f3c46c")
	var mesh := ArrayMesh.new()
	for colour in _parts:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in _parts[colour]:
			var box := BoxMesh.new()
			box.size = part.size
			surface.append_from(box, 0, Transform3D(Basis.IDENTITY, part.position))
		var part_material := StandardMaterial3D.new()
		part_material.albedo_color = Color.html(colour)
		part_material.roughness = 0.95
		if colour in ["f3c46c", "d7782e", "c36329", "b65d2e"]:
			part_material.emission_enabled = true
			part_material.emission = Color.html(colour)
			part_material.emission_energy_multiplier = 1.4 if colour == "f3c46c" else 0.35
		surface.set_material(part_material)
		surface.commit(mesh)
	var root := Node3D.new()
	root.name = "embry"
	var body := MeshInstance3D.new()
	body.name = "EmbryIndustrialTower"
	body.mesh = mesh
	root.add_child(body)
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 26
	sphere.height = 26
	sphere.is_hemisphere = true
	sphere.radial_segments = 16
	sphere.rings = 5
	dome.mesh = sphere
	dome.position = Vector3(0, 110, -5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b1a48b")
	material.roughness = 0.9
	dome.material_override = material
	root.add_child(dome)
	root.set_meta("profile", "embry_canyon_station")
	return root
