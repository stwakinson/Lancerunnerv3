extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func press_at(control: Control, local: Vector2, pressed: bool) -> void:
	var at := root.get_final_transform() * (control.get_global_transform_with_canvas() * local)
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	var scene: Control = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	while root.get_node("SceneFader").busy: await process_frame
	var world: Node3D = scene.space_world
	var market := LandingMarketState.new()
	market.save_path = "user://patron_clicks_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	world.combat.configure(world, market)
	world.ship.position = world.target_position("planet_dock") + Vector3(0, 0, 65)
	world.select_target("planet_dock")
	world.brake()
	await scene.toggle_docking()
	scene.enter_tavern()
	scene._sync_mouse_mode()
	for seed_value in range(1, 32):
		scene.tavern.begin_visit(scene.mission.board.contacts("planet_dock"), "fluellen", seed_value)
		if scene.tavern.contacts.size() == 4: break
	check(scene.tavern.contacts.size() == 4, "Fixture must exercise every faction patron")
	# Fix camera to isolate a normal multi-frame press from optional cinematic drift.
	scene.tavern.cinematic_motion = false
	scene.tavern.parallax_enabled = false
	scene.tavern.advance(0.1, Vector2.ZERO)
	scene._sync_shop_hotspots()
	var buttons: Array = [scene.contact_hotspot] + scene.faction_hotspots
	for button in buttons:
		if not button.visible: continue
		var id: String = button.get_meta("contact_id")
		await press_at(button, button.size * 0.5, true)
		for frame in 4:
			scene._process(1.0 / 60.0)
			await process_frame
		await press_at(button, button.size * 0.5, false)
		await process_frame
		check(scene.contract_panel.visible and scene.contract_panel.contact_id == id, "A multi-frame click must open the clicked patron's own contracts: " + id)
		scene.contract_panel.close_panel()
	# Marker clicks must work too, not just clicks in the body rectangle.
	var patron: Node2D
	for guest in scene.tavern.guests:
		if not guest.contact_id.is_empty():
			patron = guest
			break
	var marker := Vector2(0, -patron.dimensions.y - 6)
	check(patron.hit_rect.has_point(marker), "Contact marker must lie inside its clickable area")
	var target: Button
	for button in buttons:
		if str(button.get_meta("contact_id", "")) == patron.contact_id: target = button
	var marker_local: Vector2 = (marker - patron.hit_rect.position) * maxf(scene.size.x / 640, scene.size.y / 360)
	await press_at(target, marker_local, true)
	for frame in 3:
		scene._process(1.0 / 60.0)
		await process_frame
	await press_at(target, marker_local, false)
	await process_frame
	check(scene.contract_panel.visible and scene.contract_panel.contact_id == patron.contact_id, "Gold-marker click must open the matching patron")
	print("PATRON HELD CLICKS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
