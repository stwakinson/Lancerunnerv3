extends MultiMeshInstance3D

# 3D stars around the camera so there's parallax in every direction. The box of
# stars wraps around the camera, so space looks equally dense anywhere in the map. Soft round glows, capped to a tiny on-screen size so stars the
# camera flies close to stay small points instead of big blobs.

const FX_TEXTURE := preload("res://assets/textures/SoftDot.png")
const FX_SHADER := preload("res://shaders/fx_billboard.gdshader")

@export var count := 4000
@export var box_size := Vector3(75.0, 66.0, 75.0)
@export var box_center := Vector3(0.0, 1.0, 0.0)
@export var size_range := Vector2(0.1, 0.3)
@export var tint := Color(0.7, 0.8, 1.0)
## Largest on-screen size, as a fraction of screen height.
@export var max_screen_size := 0.006


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = FX_SHADER
	mat.set_shader_parameter("fx_texture", FX_TEXTURE)
	mat.set_shader_parameter("max_screen_size", max_screen_size)
	mat.set_shader_parameter("wrap_size", box_size)
	quad.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	for i in count:
		var p := box_center + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * box_size
		var s := randf_range(size_range.x, size_range.y)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
		mm.set_instance_custom_data(i, Color(s, 0.0, 0.0, 0.0))
		mm.set_instance_color(i, Color.WHITE.lerp(tint, randf()).srgb_to_linear())
	multimesh = mm
	# Stars are placed around the camera in the shader, so never cull them.
	custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
