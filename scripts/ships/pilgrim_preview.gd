extends Node3D
## Standalone asset viewer. F6 scenes/ships/pilgrim_preview.tscn.
const MODEL = preload("res://assets/models/pilgrim/pilgrim.glb")
const LOD = preload("res://assets/models/pilgrim/pilgrim_lod1.glb")
var visual: Node3D
var camera: Camera3D
var stats: Label
var mode := 1
var yaw := -0.65
var pitch := 0.34
var distance := 35.0
var _clay := false

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101a2c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a4b2cb")
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	_light(Vector3(-20, 25, -18), Color("ffe2b8"), 1.2)
	_light(Vector3(18, 10, 10), Color("a6c6ed"), 0.45)
	_light(Vector3(-8, 10, 25), Color("ffd092"), 0.65)
	camera = Camera3D.new()
	camera.fov = 42
	camera.near = 0.1
	camera.far = 500
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	stats = Label.new()
	stats.position = Vector2(30, 24)
	stats.add_theme_font_size_override("font_size", 22)
	canvas.add_child(stats)
	var hint := Label.new()
	hint.text = "LMB drag: orbit   ·   Wheel: zoom   ·   1: full model   ·   2: distance model   ·   3: clay   ·   R: reset   ·   Esc: menu"
	hint.position = Vector2(30, 670)
	hint.add_theme_font_size_override("font_size", 14)
	canvas.add_child(hint)
	show_model(1)
	update_camera()

func _light(at: Vector3, colour: Color, strength: float) -> void:
	var light := DirectionalLight3D.new()
	add_child(light)
	light.position = at
	light.look_at(Vector3.ZERO)
	light.light_color = colour
	light.light_energy = strength

func show_model(which: int) -> void:
	mode = which
	if visual != null: visual.free()
	visual = (MODEL if mode == 1 else LOD).instantiate()
	add_child(visual)
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		# Preserve the nearest-filter sampling from glTF.
		if _clay: mesh.material_override = clay_material()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/pilgrim/pilgrim_manifest.json"))
	stats.text = "PILGRIM / LIGHT TRADER\n%s · %d triangles · 1 material · 512px atlas" % ["LOD 0" if mode == 1 else "LOD 1", manifest.lod0_triangles if mode == 1 else manifest.lod1_triangles]

func clay_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b7bbc3")
	material.roughness = 0.85
	return material

func toggle_clay() -> void:
	_clay = not _clay
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = clay_material() if _clay else null

func update_camera() -> void:
	var focus := Vector3(0, 1.5, 0)
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * distance
	camera.look_at(focus)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.006, -1.2, 1.2)
		update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(16, distance - 2)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(85, distance + 2)
		update_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: show_model(1)
			KEY_2: show_model(2)
			KEY_3: toggle_clay()
			KEY_R:
				yaw = -0.65
				pitch = 0.34
				distance = 35
				update_camera()
			KEY_ESCAPE: get_tree().change_scene_to_file("res://scenes/menu.tscn")
