class_name Trail
extends MeshInstance3D

# Camera-facing ribbon left behind the parent node, like Unity's TrailRenderer:
# points expire after `time` seconds; width and color run head -> tail along it.

const FX_TEXTURE := preload("res://assets/textures/SoftDot.png")
const FX_SHADER := preload("res://shaders/fx_trail.gdshader")

var time := 0.12
var min_vertex_distance := 0.05
var width := 0.2
var start_color := Color.WHITE
var end_color := Color.WHITE

var _points := PackedVector3Array()
var _stamps := PackedFloat32Array()
var _clock := 0.0
var _imesh := ImmediateMesh.new()
var _material: ShaderMaterial


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	_material = ShaderMaterial.new()
	_material.shader = FX_SHADER
	_material.set_shader_parameter("fx_texture", FX_TEXTURE)
	custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))


func _process(delta: float) -> void:
	_clock += delta
	var head := (get_parent() as Node3D).global_position

	while _stamps.size() > 0 and _clock - _stamps[0] > time:
		_points.remove_at(0)
		_stamps.remove_at(0)
	if _points.is_empty() or _points[_points.size() - 1].distance_to(head) >= min_vertex_distance:
		_points.append(head)
		_stamps.append(_clock)

	_rebuild(head)


func _rebuild(head: Vector3) -> void:
	_imesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or _points.size() < 1:
		return

	# Head first, then recorded points from newest to oldest.
	var pts := PackedVector3Array([head])
	for i in range(_points.size() - 1, -1, -1):
		if pts[pts.size() - 1].distance_squared_to(_points[i]) > 0.0000001:
			pts.append(_points[i])
	if pts.size() < 2:
		return

	var total := 0.0
	var dist := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
		dist.append(total)

	var cam_pos := cam.global_position
	var start_lin := start_color.srgb_to_linear()
	var end_lin := end_color.srgb_to_linear()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for i in pts.size():
		var t := dist[i] / total
		var along := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := along.cross(cam_pos - pts[i]).normalized() * width * (1.0 - t) * 0.5
		var c := start_lin.lerp(end_lin, t)
		c.a = 1.0 - t
		_imesh.surface_set_color(c)
		_imesh.surface_set_uv(Vector2(t, 0.0))
		_imesh.surface_add_vertex(pts[i] + side)
		_imesh.surface_set_color(c)
		_imesh.surface_set_uv(Vector2(t, 1.0))
		_imesh.surface_add_vertex(pts[i] - side)
	_imesh.surface_end()
