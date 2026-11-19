extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var found: Button
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "ARTOIS  /  VISUAL BENCHMARK":
			found = button
	assert(found != null, "Menu must expose the benchmark")
	while root.get_node("SceneFader").busy:
		await process_frame
	found.pressed.emit()
	await create_timer(1.5).timeout
	assert(current_scene.name == "ArtoisVisualBenchmark", "Menu entry must open the benchmark")
	current_scene._menu()
	await create_timer(0.5).timeout
	assert(current_scene.scene_file_path == "res://scenes/menu.tscn", "Escape action must return to the menu")
	print("PASS: original menu entry and return navigation")
	quit()
