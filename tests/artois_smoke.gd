extends SceneTree

const Layout = preload("res://scripts/artois/artois_layout.gd")
var failures := 0
var capture_dir := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var scene: Control = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	var space := scene.space_world as ArtoisSpace
	var layout := space.layout
	check(layout.locations.size() == 19 and layout.fields.size() == 3, "All map landmarks, fields and the added port must be authored")
	var expected := ["calais_gate", "border_post", "renty", "embry", "asques_gate", "caulers", "agincourt", "arras", "fressin", "wrecked_shipyard", "merchant_guild", "maroeuil_wreck", "freebooter_base", "acheau", "southern_outpost", "southern_ship", "picardie_gate", "st_paul", "planet_dock"]
	for id in expected:
		check(space.landmarks.has(id), "World must contain " + id)
		check(space.landmarks[id].position.is_equal_approx(layout.world(layout.target(id))), "Chart and world coordinates must agree for " + id)
	check(space.asteroid_count == 780 and space.field_nodes.size() == 3, "All three asteroid volumes must be populated")
	for pair in [["embry", "embry_field"], ["arras", "central_field"], ["fressin", "central_field"], ["wrecked_shipyard", "central_field"], ["merchant_guild", "central_field"], ["maroeuil_wreck", "maroeuil_field"], ["freebooter_base", "maroeuil_field"]]:
		var zone := layout.target(pair[1])
		var relative := (Layout.point(layout.target(pair[0]).map) - Layout.point(zone.map)) / Layout.point(zone.radii)
		check(relative.length_squared() < 1, pair[0] + " must remain inside its map field")
	check(space.landmarks.calais_gate.position.z < space.landmarks.picardie_gate.position.z, "North/south map orientation must be preserved")
	check(space.landmarks.st_paul.position.x < space.landmarks.asques_gate.position.x, "Cathedral must remain in the southwest")
	await scene._capture(capture_dir, "artois-system.png")
	scene.toggle_chart()
	check(scene.chart.visible and scene.chart._picker.item_count == 22, "Chart must expose all 22 navigation targets")
	space.velocity = Vector3.FORWARD * 35
	var paused_position: Vector3 = space.ship.position
	scene.set_process(true)
	await create_timer(0.1).timeout
	scene.set_process(false)
	check(space.ship.position == paused_position, "Chart must pause flight")
	await scene._capture(capture_dir, "artois-chart.png")
	if DisplayServer.get_name() != "headless":
		await _click(scene.chart, scene.chart.map_point(Layout.point(layout.target("calais_gate").map)))
		check(space.selected_id == "calais_gate", "Clicking Calais on the chart must select it")
		for button in scene.chart.find_children("*", "Button", true, false):
			if button.text == "NAVIGATE":
				await _click(button, button.size * 0.5)
				break
		check(not scene.chart.visible and space.autopilot, "Navigate button must engage a real course and close the chart")
	else:
		scene.toggle_chart()
	space.prepare_launch()
	space.orbit(Vector2(-60, -10))
	var direction: Vector3 = -space.ship.basis.z
	var from: Vector3 = space.ship.position
	for i in 60: space.advance(0.1, Vector2.ZERO, 1.0, false, false)
	check((space.ship.position - from).dot(direction) > 150, "System flight must exceed the old benchmark bounds and follow heading")
	space.toggle_cruise()
	space.advance(1.0, Vector2.ZERO, 0.0, false, false)
	check(space.speed > 35, "Cruise must accelerate beyond normal flight")
	space.brake()
	check(space.velocity == Vector3.ZERO and not space.cruise, "Brake must cancel cruise and stop the ship")
	space.navigate_to("embry")
	for i in 600:
		space.advance(0.1, Vector2.ZERO, 0.0, false, false)
		if not space.autopilot: break
	check(not space.autopilot and space.ship.position.distance_to(space.target_position()) < 85, "Course following must reach and stop near a distant settlement")
	check(space.ship.position.distance_to(from) > 500, "Navigation must move through the expanded system")
	await scene.toggle_docking()
	check(not scene.landed and not scene.transitioning, "Landing must be rejected away from the planet port")
	space.navigate_to(space.DOCK_ID)
	for i in 600:
		space.advance(0.1, Vector2.ZERO, 0.0, false, false)
		if not space.autopilot: break
	check(not space.autopilot and space.docking_error().is_empty(), "Navigating to the planet port must stop within legal docking range and speed")
	space.ship.position = space.target_position(space.DOCK_ID) + Vector3(0, 0, 65)
	space.velocity = Vector3(30, 0, 0)
	await scene.toggle_docking()
	check(not scene.landed, "High-speed docking must be rejected")
	space.brake()
	space.ship.position = layout.world(layout.planet)
	space.advance(0.0, Vector2.ZERO, 0.0, false, false)
	check(space.ship.position.distance_to(layout.world(layout.planet)) >= float(layout.planet.radius) + 7.9, "Planet body must keep the ship above its surface")
	space.ship.position = space.target_position(space.DOCK_ID) + Vector3(0, 0, 65)
	space.ship.rotation = Vector3.ZERO
	space.reset_view()
	space.advance(0.1, Vector2.ZERO, 0.0, false, true)
	check(space.shots.size() > 0, "System flight must retain weapon visuals")
	await scene.toggle_docking()
	check(scene.landed and scene.landing_world.scene_file_path == "res://scenes/planet_landing.tscn", "Legal docking must transition to the separate planet landing scene")
	scene.open_shop("commodities")
	check(scene.shop_panel.visible, "The planet landing must retain market services")
	await scene.toggle_docking()
	check(scene.landed, "An open shop must block launch")
	scene.shop_panel.close_shop()
	await scene._capture(capture_dir, "artois-planet-landing.png")
	await scene.toggle_docking()
	check(not scene.landed and space.ship.position.is_equal_approx(space.launch_position()), "Launch must return to the planet port")
	check(space.velocity == Vector3.ZERO and space.shots.is_empty(), "Launch must clear old motion and projectiles")
	check(space.ship.position.distance_to(space.target_position(space.DOCK_ID)) > space.DOCK_RANGE, "Launch must leave docking range to prevent immediate re-entry")
	for samples in space._effects._samples:
		check(samples.is_empty(), "Launch must clear old exhaust history")
	scene._menu()
	await process_frame
	await process_frame
	var menu := current_scene
	var entry: Button
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "ARTOIS SYSTEM  /  EXPLORE": entry = button
	check(entry != null, "Main menu must expose the Artois system separately")
	entry.pressed.emit()
	await create_timer(1.5).timeout
	check(current_scene.scene_file_path == "res://scenes/artois.tscn", "Menu entry must open the new system scene")
	if failures == 0: print("PASS: Artois layout, navigation, chart, free flight, planet safety, gated docking, market, launch and menu entry")
	quit(0 if failures == 0 else 1)


func _click(control: Control, local: Vector2) -> void:
	var at := root.get_final_transform() * (control.get_global_transform_with_canvas() * local)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
