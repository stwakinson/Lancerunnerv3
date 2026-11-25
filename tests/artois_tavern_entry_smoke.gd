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
func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
func click(control: Control) -> void:
	var at := root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	Input.warp_mouse(at)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
func run() -> void:
	var scene: Control = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	var world: Node3D = scene.space_world
	var market := LandingMarketState.new()
	market.save_path = "user://tavern_entry_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	world.combat.configure(world, market)
	world.ship.position = world.target_position("planet_dock") + Vector3(0, 0, 65)
	world.select_target("planet_dock")
	world.brake()
	await scene.toggle_docking()
	scene._sync_mouse_mode()
	var market_room: Node2D = scene.landing_world
	await key(KEY_3)
	check(scene.in_tavern and scene.landing_world != market_room and scene.landing_world.scene_file_path == "res://scenes/artois_tavern.tscn", "Key 3 must switch to the dedicated tavern scene")
	check(scene.tavern.visible and not market_room.visible and scene._heading.text == "THE HOLLOW CROWN", "Entry must update room visibility and heading together")
	await key(KEY_5)
	check(not scene.in_tavern and market_room.visible and not scene.tavern.visible, "Key 5 must restore the market")
	if DisplayServer.get_name() == "headless": scene.contact_button.pressed.emit()
	else: await click(scene.contact_button)
	check(scene.in_tavern and scene.landing_world.is_room_ready(), "The actual tavern service button must enter a ready room")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		var rendered: Image = scene.landing_view.get_texture().get_image()
		var colours := {}
		for y in range(50, 300, 20):
			for x in range(20, 620, 20): colours[rendered.get_pixel(x, y).to_html()] = true
		check(colours.size() > 50, "The tavern viewport must render actual artwork, not the reported flat grey view")
		if not capture_dir.is_empty(): await scene._capture(capture_dir, "tavern-key-and-button-entry.png")
	scene.leave_tavern()
	# Reproduce a partially loaded cached room: the original switch hid the market
	# and then called reset_camera on this invalid room, leaving the market UI grey.
	scene.tavern.free()
	var incomplete := Node2D.new()
	incomplete.visible = false
	scene.landing_view.add_child(incomplete)
	scene.tavern = incomplete
	await key(KEY_3)
	check(scene.in_tavern and scene.tavern != incomplete and scene.tavern.is_room_ready(), "Entry must replace an incomplete cached room before hiding the market")
	check(scene.tavern.layers.size() == 6 and scene.tavern.guests.size() >= 3, "Recovered dedicated scene must have layers and a visit roster")
	if DisplayServer.get_name() == "headless": scene.market_button.pressed.emit()
	else: await click(scene.market_button)
	check(market_room.visible and not scene.in_tavern, "Recovered room must still support return to market")
	print("TAVERN INPUT ENTRY: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
