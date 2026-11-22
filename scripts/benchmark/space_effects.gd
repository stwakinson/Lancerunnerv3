class_name BenchmarkSpaceEffects
extends Node3D

# Short-lived world-space exhaust ribbons. They keep their shape on turns and
# stop advancing when the space coordinator pauses for docking.

var _samples: Array = [[], []]
var _ribbons: Array[MeshInstance3D] = []
var _sample_wait := 0.0
const LIFETIME := 0.65
const CAPACITY := 32


func _ready() -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/benchmark/exhaust.gdshader")
	for i in 2:
		var ribbon := MeshInstance3D.new()
		ribbon.material_override = material
		add_child(ribbon)
		_ribbons.append(ribbon)


func advance(delta: float, ship: Node3D, camera: Camera3D, boosting: bool, intensity: float = 1.0) -> void:
	_sample_wait -= delta
	for lane in 2:
		var history: Array = _samples[lane]
		for sample in history:
			sample.age += delta
			sample.position += ship.global_basis.z * delta * (22.0 if boosting else 9.0)
		while not history.is_empty() and (history.back().age > LIFETIME or history.size() >= CAPACITY):
			history.pop_back()
		if _sample_wait <= 0.0 and intensity > 0.01:
			var nozzle := ship.to_global(Vector3(-0.48 if lane == 0 else 0.48, 0, 3.12))
			history.push_front({"position": nozzle, "age": 0.0})
		_ribbons[lane].transparency = 1.0 - clampf(intensity, 0, 1)
		_rebuild(lane, camera, boosting)
	if _sample_wait <= 0.0:
		_sample_wait = 1.0 / 45.0


func _rebuild(lane: int, camera: Camera3D, boosting: bool) -> void:
	var history: Array = _samples[lane]
	if history.size() < 2:
		_ribbons[lane].mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := camera.global_basis.x * (0.42 if boosting else 0.26)
	for i in history.size() - 1:
		var a: Vector3 = history[i].position
		var b: Vector3 = history[i + 1].position
		var av: float = history[i].age / LIFETIME
		var bv: float = history[i + 1].age / LIFETIME
		for corner in [[a - side, Vector2(0, av)], [a + side, Vector2(1, av)], [b - side, Vector2(0, bv)],
				[b - side, Vector2(0, bv)], [a + side, Vector2(1, av)], [b + side, Vector2(1, bv)]]:
			surface.set_uv(corner[1])
			surface.add_vertex(to_local(corner[0]))
	_ribbons[lane].mesh = surface.commit()


func clear_trails() -> void:
	for history in _samples: history.clear()
	for ribbon in _ribbons: ribbon.mesh = null
	_sample_wait = 0.0
