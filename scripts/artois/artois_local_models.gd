class_name ArtoisLocalModels
extends RefCounted
## Original low-poly silhouettes. One shared multi-surface mesh per faction.
var _cache := {}
var _parts := {}


func make(profile: String) -> MeshInstance3D:
	if not _cache.has(profile): _cache[profile] = _build(profile)
	var node := MeshInstance3D.new()
	node.mesh = _cache[profile]
	return node


func _box(at: Vector3, dimensions: Vector3, colour: String) -> void:
	if not _parts.has(colour): _parts[colour] = []
	_parts[colour].append({"position": at, "size": dimensions})


func _build(profile: String) -> ArrayMesh:
	_parts.clear()
	match profile.trim_suffix("_guard"):
		"cog":
			_box(Vector3.ZERO, Vector3(15, 7, 27), "c9bfa2")
			_box(Vector3(0, -3.8, 0), Vector3(14, 1.2, 25), "44464c")
			_box(Vector3(0, 5, 7), Vector3(12, 5, 9), "9b8b70")
			_box(Vector3(0, 7.8, 7), Vector3(10, 0.7, 8), "62503e")
			for x in [-4.5, 0.0, 4.5]:
				_box(Vector3(x, 4.2, -3), Vector3(4, 1.8, 13), "916c46")
			for side in [-1.0, 1.0]:
				_box(Vector3(side * 7.55, 0, 2), Vector3(0.2, 7, 4), "943c30")
				_box(Vector3(side * 7.7, 0.5, 2), Vector3(0.1, 4, 0.5), "eee0bd")
				_box(Vector3(side * 7.7, 1.1, 2), Vector3(0.1, 0.5, 2.2), "eee0bd")
				_box(Vector3(side * 5.1, 6, 2.4), Vector3(2, 1.5, 0.2), "e1bb72")
			# Bow framing and a league badge keep the cog recognisable head-on.
			for side in [-1.0, 1.0]:
				_box(Vector3(side * 6.8, 0, -13.6), Vector3(0.6, 6.5, 0.3), "44464c")
				_box(Vector3(side * 4.5, -1.5, -13.8), Vector3(1, 1, 0.3), "e1bb72")
			_box(Vector3(0, 0, -13.6), Vector3(3, 6.5, 0.25), "943c30")
			_box(Vector3(0, 0, -13.8), Vector3(0.5, 4, 0.1), "eee0bd")
			_box(Vector3(0, 1, -13.8), Vector3(2.2, 0.5, 0.1), "eee0bd")
			_box(Vector3(0, 11, 9), Vector3(0.35, 7, 0.35), "4b4843")
			_box(Vector3(2.2, 12.8, 9), Vector3(4.5, 3, 0.2), "943c30")
		"britannian":
			_box(Vector3.ZERO, Vector3(7, 4, 19), "e3e0de")
			_box(Vector3(0, -2.3, 1), Vector3(6.3, 1, 17), "484955")
			_box(Vector3(0, 0.3, 0), Vector3(7.2, 0.8, 19.2), "b62e25")
			_box(Vector3(0, 2.4, 0), Vector3(1, 0.7, 19), "b62e25")
			_box(Vector3(0, 2.5, 0), Vector3(7, 0.8, 2), "b62e25")
			_box(Vector3(0, 3, -5), Vector3(4, 1.4, 4), "739aab")
			_box(Vector3(0, 0.5, 10), Vector3(7.4, 5, 1.5), "9d3d28")
		"valois":
			_box(Vector3.ZERO, Vector3(8, 4, 18), "657fb0")
			_box(Vector3(0, -2.1, 1), Vector3(6, 1, 16), "343e57")
			_box(Vector3(0, 2.8, 3), Vector3(5, 2, 9), "a2b3c6")
			for side in [-1.0, 1.0]:
				_box(Vector3(side * 5, 0, 2), Vector3(2, 2, 12), "4b6091")
				_box(Vector3(side * 4.1, 0.2, -3), Vector3(0.2, 2.5, 0.7), "dbbb6e")
				_box(Vector3(side * 4.1, 0.8, -3), Vector3(0.2, 0.5, 2.1), "dbbb6e")
		"borderlander":
			_box(Vector3.ZERO, Vector3(7, 4, 14), "858d7c")
			_box(Vector3(-2.5, 2.5, 2), Vector3(2.5, 1.5, 8), "ad9974")
			_box(Vector3(2, -1.5, 0), Vector3(4, 2, 10), "6b5961")
			_box(Vector3(0, 2.8, -3), Vector3(3.5, 1.5, 3), "7fa0a6")
			_box(Vector3(4.3, 0, 1), Vector3(2, 2, 6), "545454")
		_:
			var body := "403b45" if profile == "freebooter" else "666574"
			_box(Vector3.ZERO, Vector3(3.2, 1.7, 8), body)
			_box(Vector3(0, 1.1, -1), Vector3(2, 1, 2.5), "7a9aab")
			for side in [-1.0, 1.0]:
				_box(Vector3(side * 3, -0.3, 1.5), Vector3(4, 0.6, 4), body)
				_box(Vector3(side * 4.5, 0, 1), Vector3(0.8, 1.7, 5), "9c4e35" if profile == "freebooter" else "8a8792")
	_box(Vector3(0, 0, 14.0 if profile == "cog" else (10.0 if profile == "britannian" else (9.5 if profile == "valois" else (7.5 if profile == "borderlander" else 4.3)))), Vector3(2.2, 1, 0.5), "76cee1")
	if profile.ends_with("_guard"):
		for side in [-1.0, 1.0]:
			_box(Vector3(side * 5, 0, -7), Vector3(1.4, 1.4, 8), "343e57")
	var result := ArrayMesh.new()
	for colour in _parts:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in _parts[colour]:
			var box := BoxMesh.new()
			box.size = part.size
			surface.append_from(box, 0, Transform3D(Basis.IDENTITY, part.position))
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.html(colour)
		material.roughness = 0.85
		surface.set_material(material)
		surface.commit(result)
	return result
