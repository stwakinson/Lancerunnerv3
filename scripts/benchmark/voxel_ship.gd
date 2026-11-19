class_name BenchmarkShip
extends Node3D

# Original blockout inspired by the supplied red-and-white ship reference.
# Replace this node with an authored model; its forward axis is Godot -Z.

var engines: Array[MeshInstance3D] = []
var _materials := {}


func _ready() -> void:
	_box(Vector3(0, 0, 0), Vector3(1.35, 0.5, 5.8), "d8d9e6")
	_box(Vector3(0, -0.25, 0.2), Vector3(1.15, 0.16, 5.2), "434856")
	_box(Vector3(0, 0.02, -0.3), Vector3(1.42, 0.22, 5.4), "bd311f")
	_box(Vector3(0, 0.27, -0.3), Vector3(0.38, 0.08, 5.0), "e54a24")
	_box(Vector3(0, 0.32, -1.55), Vector3(0.82, 0.22, 1.2), "8ea8bc")
	_box(Vector3(0, 0.45, -1.55), Vector3(0.64, 0.08, 0.85), "27485d")
	_box(Vector3(0, 0.5, -1.8), Vector3(0.45, 0.03, 0.18), "91e1e4", true)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 1.0, -0.09, 0.65), Vector3(0.8, 0.14, 2.8), "c8c8d6")
		_box(Vector3(side * 1.05, 0, 0.9), Vector3(0.72, 0.09, 0.65), "b72d20")
		_box(Vector3(side * 1.36, -0.04, 1.6), Vector3(0.16, 0.35, 1.6), "e14726")
		_box(Vector3(side * 0.48, 0, 2.8), Vector3(0.48, 0.45, 0.55), "303843")
		var engine := _box(Vector3(side * 0.48, 0, 3.12), Vector3(0.3, 0.27, 0.08), "63dcf4", true)
		engines.append(engine)
		var plume := _box(Vector3(side * 0.48, 0, 3.5), Vector3(0.18, 0.16, 0.7), "3484b4", true)
		engines.append(plume)
		# Stepped panel details keep the texture-free placeholder visibly pixel-like.
		for i in 7:
			_box(Vector3(side * 0.686, 0.14, -2.2 + i * 0.65), Vector3(0.025, 0.12, 0.4), "f0edf3" if i % 3 else "a5a7bc")


func _box(at: Vector3, dimensions: Vector3, colour: String, emission := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	var key := colour + str(emission)
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.html(colour)
		mat.roughness = 0.85
		if emission:
			mat.emission_enabled = true
			mat.emission = Color.html(colour)
			mat.emission_energy_multiplier = 2.0
		_materials[key] = mat
	mesh.material_override = _materials[key]
	mesh.position = at
	add_child(mesh)
	return mesh
