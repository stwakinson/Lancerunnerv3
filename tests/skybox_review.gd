extends SceneTree

# Render all six cardinal directions to inspect the panorama's wrap and poles.
# godot --path . --script res://tests/skybox_review.gd -- --capture-dir=/path

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var panorama := load("res://assets/benchmark/artois_nebula.png") as Texture2D
	assert(panorama.get_width() == panorama.get_height() * 2, "Panorama must remain 2:1")
	if DisplayServer.get_name() == "headless":
		print("PASS: panorama aspect ratio; six-direction render requires a display")
		quit()
		return
	var scene := Control.new()
	root.add_child(scene)
	current_scene = scene
	var directions := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.UP, Vector3.DOWN]
	var names := ["FORWARD", "RIGHT / WRAP REGION", "BACK", "LEFT", "NORTH POLE", "SOUTH POLE"]
	for i in directions.size():
		var view := SubViewport.new()
		view.size = Vector2i(426, 330)
		view.own_world_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		scene.add_child(view)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/benchmark/nebula.gdshader")
		material.set_shader_parameter("panorama", panorama)
		sky.sky_material = material
		environment.environment.sky = sky
		view.add_child(environment)
		var camera := Camera3D.new()
		camera.fov = 100
		view.add_child(camera)
		camera.look_at(directions[i], Vector3.FORWARD if i >= 4 else Vector3.UP)
		camera.current = true
		var image := TextureRect.new()
		image.texture = view.get_texture()
		image.position = Vector2((i % 3) * 426, (i / 3) * 360)
		image.size = Vector2(426, 330)
		scene.add_child(image)
		var label := Label.new()
		label.text = names[i]
		label.position = image.position + Vector2(12, 333)
		scene.add_child(label)
	while root.get_node("SceneFader").busy:
		await process_frame
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			var directory := arg.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(directory)
			var error := root.get_texture().get_image().save_png(directory.path_join("skybox-six-directions.png"))
			assert(error == OK)
	print("PASS: six-direction skybox render complete")
	quit()
