extends SceneTree
var failures := 0
var capture_dir := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/pilgrim/pilgrim_manifest.json"))
	for pair in [["pilgrim.glb", "lod0_triangles"], ["pilgrim_lod1.glb", "lod1_triangles"]]:
		var source: PackedScene = load("res://assets/models/pilgrim/" + pair[0])
		var ship := source.instantiate()
		root.add_child(ship)
		var meshes := ship.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() == 1, "Each game LOD must be one combined mesh")
		var triangles := 0
		for node in meshes:
			var mesh: Mesh = node.mesh
			check(mesh.get_surface_count() == 1, "Each LOD must use one material surface")
			var arrays := mesh.surface_get_arrays(0)
			triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var material: StandardMaterial3D = node.get_active_material(0)
			check(material.albedo_texture != null and material.emission_enabled and material.emission_texture != null, "Model must include textured albedo and emission")
			check(material.texture_filter in [0, 2, 4], "Pixel atlas must use nearest texture filtering")
			check(material.resource_path == "res://assets/models/pilgrim/pilgrim_material.tres", "Both LODs must use the same shared Godot material")
			var bounds := mesh.get_aabb()
			check(bounds.size.z > bounds.size.x and bounds.size.y > 8, "Ship must have longitudinal Z hull and raised cupola")
			if pair[0] == "pilgrim.glb":
				var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var exhaust_vertices := 0
				for i in positions.size():
					if positions[i].z > 10.5 and uvs[i].x > 0.75 and uvs[i].y > 0.625 and uvs[i].y < 0.875:
						exhaust_vertices += 1
						check(normals[i].z > 0.99, "Engine emitter faces must point outward toward +Z")
				check(exhaust_vertices >= 12, "Both real exhaust surfaces must exist")
				var sizes: Array = manifest.dimensions_godot
				check(bounds.size.is_equal_approx(Vector3(sizes[0], sizes[1], sizes[2])), "Manifest dimensions must match exported model")
		check(triangles == int(manifest[pair[1]]), "Manifest triangle count must match real GLB geometry")
		check(triangles <= 1500, "Pilgrim must stay inside its low-poly budget")
		var dock: Node3D = ship.find_child("Docking_Collar", true, false)
		var engine: Node3D = ship.find_child("Engine_Port", true, false)
		check(dock != null and engine != null and dock.position.z < 0 and engine.position.z > 0, "Godot front must be -Z, with engines at +Z")
		ship.free()
	var scene: Node3D = load("res://scenes/ships/pilgrim_preview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	while root.get_node("SceneFader").busy: await process_frame
	await capture(scene, "pilgrim-front-quarter.png")
	scene.yaw = 2.45
	scene.update_camera()
	await capture(scene, "pilgrim-rear-quarter.png")
	scene.yaw = -0.65
	scene.show_model(2)
	check(scene.mode == 2, "Preview must switch to cheaper LOD")
	scene.update_camera()
	await capture(scene, "pilgrim-lod1.png")
	scene.show_model(1)
	scene.toggle_clay()
	check(scene.visual.find_children("*", "MeshInstance3D", true, false)[0].material_override != null, "Clay mode must reveal actual silhouette")
	await capture(scene, "pilgrim-clay.png")
	scene.toggle_clay()
	check(scene.visual.find_children("*", "MeshInstance3D", true, false)[0].material_override == null, "Texture mode must restore imported material")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	scene._unhandled_input(escape)
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/menu.tscn", "Preview must return to main menu")
	var preview_button := current_scene.find_child("PilgrimPreviewButton", true, false) as Button
	check(preview_button != null, "Main menu must expose the model viewer")
	preview_button.pressed.emit()
	while root.get_node("SceneFader").busy: await process_frame
	check(current_scene.scene_file_path == "res://scenes/ships/pilgrim_preview.tscn", "Main-menu button must launch the actual model viewer")
	print("PILGRIM MODEL: %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)
func capture(scene: Node3D, filename: String) -> void:
	await process_frame
	await process_frame
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_dir)
	check(root.get_texture().get_image().save_png(capture_dir.path_join(filename)) == OK, "Preview capture must save")
