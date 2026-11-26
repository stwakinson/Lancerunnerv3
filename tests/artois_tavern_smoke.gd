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
	var scene: Control = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	var world: Node3D = scene.space_world
	var bar: Node2D = scene.tavern
	var market := LandingMarketState.new()
	market.save_path = "user://tavern_smoke_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	world.combat.configure(world, market)
	check(bar.layers.size() == 6 and bar.guests.is_empty(), "Standalone base scene must start with zero people and six separate depth layers")
	check(bar.ROOM.get_image().get_pixel(600, 300).a < 0.1, "Window opening must have actual alpha transparency")
	var profiles: Array = scene.mission.board.contacts("planet_dock")
	var signatures := {}
	for seed_value in 12:
		bar.begin_visit(profiles, "factor", seed_value)
		check(bar.contacts.size() >= 2 and bar.contacts.size() <= 4 and bar.guests.size() >= 6 and bar.guests.size() <= 8, "Bounded randomized contacts, three local speakers and separate staff")
		check(bar.contacts.any(func(entry: Dictionary) -> bool: return entry.id == "factor"), "Pending issuer must always be present")
		var ids := {}
		for entry in bar.contacts:
			check(not ids.has(entry.id), "No duplicate faction patrons")
			ids[entry.id] = true
			check(bar.contact_rect(entry.id).size.x > 0, "Every contact requires its own click rectangle")
		signatures[bar.signature] = true
	check(signatures.size() > 8, "Different landings should vary the guest list/placement/staff")
	bar.clear_people()
	check(bar.guests.is_empty() and bar.layers[2].get_child_count() == 0 and bar.layers[4].get_child_count() == 0, "All people can be removed without touching room artwork")
	world.ship.position = world.target_position("planet_dock") + Vector3(0, 0, 60)
	world.select_target("planet_dock")
	world.brake()
	await scene.toggle_docking()
	var visit: int = bar.visit
	check(scene.landed and bar.contacts.size() >= 2 and not scene.in_tavern, "Landing rolls patrons once but keeps market as arrival scene")
	scene.enter_tavern()
	scene._sync_mouse_mode()
	check(scene.in_tavern and scene.landing_world == bar and not scene.shop_hotspots.visible and not scene.dealer_hotspot.visible and scene.market_button.visible, "Tavern must have its own scene and disable market hotspots")
	var signature: String = bar.signature
	scene.leave_tavern()
	scene.enter_tavern()
	check(bar.visit == visit and bar.signature == signature, "Re-entering the tavern must not reroll this landing's guests")
	bar.cinematic_motion = false
	bar.advance(0.5, Vector2(1, 0.4), 0)
	check(bar.layers[0].position != bar.layers[1].position and bar.layers[1].position != bar.layers[5].position, "City, room and foreground must move independently")
	check(bar.layers[1].position == bar.layers[2].position and bar.layers[2].position == bar.layers[3].position and bar.layers[3].position == bar.layers[4].position, "Furniture and seated patrons must remain registered")
	var actor: Dictionary = bar.contacts[0]
	var rect_before: Rect2 = bar.contact_rect(actor.id)
	bar.advance(0.5, Vector2(-1, 0), 0)
	check(bar.contact_rect(actor.id).position != rect_before.position, "Patron click rectangles must follow parallax")
	scene._sync_shop_hotspots()
	var button: Button = scene.contact_hotspot
	check(button.get_meta("contact_id") == actor.id and button.visible, "Visible overlay must map to the current patron, not fixed street positions")
	if DisplayServer.get_name() == "headless": scene.open_contract(actor.id)
	else: await click(button)
	check(scene.contract_panel.visible and scene.contract_panel.contact_id == actor.id and scene.contract_panel._contacts.item_count == bar.contacts.size(), "Patron click must open only contacts present this visit")
	var camera: Vector2 = bar.camera_position
	scene._process(0.2)
	check(bar.camera_position == camera and bar.signature == signature, "Conversation freezes camera and retains guest roster")
	scene.contract_panel.close_panel()
	bar.reset_camera()
	if not capture_dir.is_empty():
		scene._process(0)
		await scene._capture(capture_dir, "artois-tavern-populated.png")
		bar.clear_people()
		scene._sync_shop_hotspots()
		check(not scene.contact_hotspot.visible, "Empty-room preview must have no ghost contact hotspots")
		await scene._capture(capture_dir, "artois-tavern-empty.png")
		bar.begin_visit(profiles, "fluellen", 38)
		visit = bar.visit
		actor = bar.contacts[0]
	# Accept a real contract, then ensure its giver cannot vanish on the next landing.
	scene.open_contract(actor.id)
	scene.contract_panel._act()
	check(scene.mission.phase == "active", "Tavern patron must offer working contracts")
	var issuer: String = scene.mission.active_offer.contact
	scene.contract_panel.close_panel()
	await scene.toggle_docking()
	check(not scene.landed and not scene.in_tavern and not world.docked, "Launch from tavern must restore the market scene offscreen")
	for enemy in world.combat.enemies.duplicate(): world.combat.damage_enemy(str(enemy.get_meta("id")), 100000, 100000)
	check(scene.mission.phase == "return", "Contract completes outside port")
	world.ship.position = world.target_position("planet_dock") + Vector3(0, 0, 60)
	world.brake()
	await scene.toggle_docking()
	check(bar.visit == visit + 1 and bar.contacts.any(func(entry: Dictionary) -> bool: return entry.id == issuer), "Fresh landing must reroll but pin the pending turn-in contact")
	scene.open_contract(issuer)
	check(scene.contract_panel.visible and not scene.contract_panel._action.disabled, "Returning patron must permit turn-in")
	scene.contract_panel._act()
	check(scene.mission.phase == "paid", "Patron must pay completed contract")
	scene.contract_panel.close_panel()
	var current_visit: int = bar.visit
	var current_signature: String = bar.signature
	scene.leave_tavern()
	scene.open_shop("commodities")
	check(scene.shop_panel.visible and not scene.in_tavern, "Market shops must remain available after leaving tavern")
	scene.shop_panel.close_shop()
	scene.enter_tavern()
	check(bar.visit == current_visit and bar.signature == current_signature, "Shopping must not reroll tavern guests")
	bar.parallax_enabled = false
	bar.advance(0.1, Vector2.ONE, 1)
	check(bar.camera_position == Vector2.ZERO and bar.layers[0].position == Vector2.ZERO and bar.layers[5].position == Vector2.ZERO, "Depth toggle must settle all layers to aligned zero position")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(market.save_path))
	print("PARALLAX TAVERN: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
func click(control: Control) -> void:
	var at := root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	Input.warp_mouse(at)
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
