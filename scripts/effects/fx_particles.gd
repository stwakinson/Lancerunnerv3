class_name FxParticles
extends MultiMeshInstance3D

# Small world-space particle emitter that mirrors the Unity ParticleSystem setups
# used by the game (explosion bursts and engine thrusters): random lifetime,
# speed, size and start color, drag, a color/alpha gradient over lifetime and a
# linear shrink. Particles are soft additive billboards (see fx_billboard.gdshader).

enum Shape { SPHERE, CONE }

const FX_TEXTURE := preload("res://assets/textures/SoftDot.png")
const FX_SHADER := preload("res://shaders/fx_billboard.gdshader")
const FX_SHADER_MIX := preload("res://shaders/fx_billboard_mix.gdshader")
# Floats per instance in the MultiMesh buffer: transform (12), color (4), custom (4).
const STRIDE := 20

var emitting := true
var rate := 0.0
var burst := 0
var lifetime := Vector2(1.0, 1.0)
var speed := Vector2(1.0, 1.0)
var size := Vector2(1.0, 1.0)
# Start color is a random blend between these two (sRGB, like Unity's inspector colors).
var start_color_a := Color.WHITE
var start_color_b := Color.WHITE
# Color over lifetime, multiplied with the start color: [[time, Color], ...] and [[time, alpha], ...].
var color_keys: Array = [[0.0, Color.WHITE], [1.0, Color.WHITE]]
var alpha_keys: Array = [[0.0, 1.0], [1.0, 0.0]]
var size_end := 1.0
var drag := 0.0
# Constant push on every particle, in world space (flames rise, embers fall).
var acceleration := Vector3.ZERO
var shape := Shape.SPHERE
var shape_radius := 0.0
var cone_angle := 0.0
var max_particles := 100
var max_screen_size := 0.5
# Additive glow (sparks, flames) or ordinary alpha blending (dust).
var additive := true
# Farther than this from the camera the emitter stops (0 = always runs). Used
# for engine plumes, which would only be a pixel or two away out there.
var lod_distance := 0.0

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _color: Array[Color] = []
var _emit_accum := 0.0
var _buffer := PackedFloat32Array()
var _linear_color_keys: Array = []
var _started := false


# Configures the look shared by every emitter; call before adding to the tree.
func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	global_transform = Transform3D.IDENTITY
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = FX_SHADER if additive else FX_SHADER_MIX
	mat.set_shader_parameter("fx_texture", FX_TEXTURE)
	mat.set_shader_parameter("max_screen_size", max_screen_size)
	quad.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = max_particles
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	multimesh = mm
	_buffer.resize(max_particles * STRIDE)

	for key in color_keys:
		_linear_color_keys.append([key[0], (key[1] as Color).srgb_to_linear()])


# The emitter's transform lives on the parent (this node draws in world space).
func _emitter_transform() -> Transform3D:
	var parent := get_parent() as Node3D
	return parent.global_transform if parent != null else Transform3D.IDENTITY


func _process(delta: float) -> void:
	# Hidden like a deactivated Unity GameObject: particles vanish, emission stops.
	if not is_visible_in_tree():
		clear()
		return
	if lod_distance > 0.0:
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.global_position.distance_squared_to(_emitter_transform().origin) > lod_distance * lod_distance:
			clear()
			return

	if not _started:
		_started = true
		for i in burst:
			_spawn()

	if emitting and rate > 0.0:
		_emit_accum += rate * delta
		while _emit_accum >= 1.0:
			_emit_accum -= 1.0
			_spawn()

	var damping := maxf(0.0, 1.0 - drag * delta)
	var i := 0
	while i < _pos.size():
		_age[i] += delta
		if _age[i] >= _life[i]:
			_remove(i)
			continue
		if drag > 0.0:
			_vel[i] *= damping
		if acceleration != Vector3.ZERO:
			_vel[i] += acceleration * delta
		_pos[i] += _vel[i] * delta
		i += 1

	_upload()


func clear() -> void:
	_pos.clear()
	_vel.clear()
	_age.clear()
	_life.clear()
	_size.clear()
	_color.clear()
	_emit_accum = 0.0
	if multimesh != null:
		multimesh.visible_instance_count = 0


func particle_count() -> int:
	return _pos.size()


func _spawn() -> void:
	if _pos.size() >= max_particles:
		return
	var xf := _emitter_transform()
	var local_pos: Vector3
	var local_dir: Vector3

	match shape:
		Shape.SPHERE:
			local_pos = random_inside_unit_sphere() * shape_radius
			local_dir = local_pos.normalized() if local_pos.length_squared() > 0.000001 else random_on_unit_sphere()
		Shape.CONE:
			# Points on a disk, each heading outward in proportion to its distance from center.
			var r := sqrt(randf())
			var a := randf() * TAU
			var disk := Vector2(cos(a), sin(a)) * r
			local_pos = Vector3(disk.x, disk.y, 0.0) * shape_radius
			var tilt := deg_to_rad(cone_angle) * r
			local_dir = Vector3(cos(a) * sin(tilt), sin(a) * sin(tilt), -cos(tilt))

	_pos.append(xf * local_pos)
	_vel.append((xf.basis * local_dir).normalized() * randf_range(speed.x, speed.y))
	_age.append(0.0)
	_life.append(randf_range(lifetime.x, lifetime.y))
	_size.append(randf_range(size.x, size.y))
	_color.append(start_color_a.lerp(start_color_b, randf()).srgb_to_linear())


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	_pos[i] = _pos[last]
	_vel[i] = _vel[last]
	_age[i] = _age[last]
	_life[i] = _life[last]
	_size[i] = _size[last]
	_color[i] = _color[last]
	_pos.resize(last)
	_vel.resize(last)
	_age.resize(last)
	_life.resize(last)
	_size.resize(last)
	_color.resize(last)


func _upload() -> void:
	var n := _pos.size()
	for i in n:
		var t := _age[i] / _life[i]
		var s := _size[i] * lerpf(1.0, size_end, t)
		var c: Color = _color[i] * (sample_keys(_linear_color_keys, t) as Color)
		c.a = _color[i].a * float(sample_keys(alpha_keys, t))
		var p := _pos[i]
		var o := i * STRIDE
		_buffer[o] = 1.0; _buffer[o + 1] = 0.0; _buffer[o + 2] = 0.0; _buffer[o + 3] = p.x
		_buffer[o + 4] = 0.0; _buffer[o + 5] = 1.0; _buffer[o + 6] = 0.0; _buffer[o + 7] = p.y
		_buffer[o + 8] = 0.0; _buffer[o + 9] = 0.0; _buffer[o + 10] = 1.0; _buffer[o + 11] = p.z
		_buffer[o + 12] = c.r; _buffer[o + 13] = c.g; _buffer[o + 14] = c.b; _buffer[o + 15] = c.a
		_buffer[o + 16] = s
	multimesh.buffer = _buffer
	multimesh.visible_instance_count = n


# Piecewise-linear lookup in [[time, value], ...] keys (value is a float or Color).
static func sample_keys(keys: Array, t: float) -> Variant:
	if t <= keys[0][0]:
		return keys[0][1]
	for k in range(1, keys.size()):
		if t <= keys[k][0]:
			var t0: float = keys[k - 1][0]
			var t1: float = keys[k][0]
			var f := (t - t0) / maxf(t1 - t0, 0.00001)
			return lerp(keys[k - 1][1], keys[k][1], f)
	return keys[keys.size() - 1][1]


static func random_inside_unit_sphere() -> Vector3:
	return random_on_unit_sphere() * pow(randf(), 1.0 / 3.0)


static func random_on_unit_sphere() -> Vector3:
	var z := randf_range(-1.0, 1.0)
	var a := randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(a), r * sin(a), z)
