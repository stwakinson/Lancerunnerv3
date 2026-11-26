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
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	while root.get_node("SceneFader").busy: await process_frame
	var world: Node3D = scene.space_world
	var market := LandingMarketState.new()
	market.save_path = "user://character_smoke_%d.json" % OS.get_process_id()
	market.credits = 27000
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	world.combat.configure(world, market)
	await key(KEY_I)
	check(scene.character_sheet.visible and scene.character_sheet.rows.size() == 6, "I opens complete faction sheet in flight")
	check(scene.character_sheet.rows.britannian.score.text == "0" and scene.character_sheet.rows.britannian.access.text == "Basic", "Neutral standing must show basic contracts unlocked")
	check(scene.character_sheet._ship.text.contains("27000") and scene.character_sheet._ship.text.contains("Warden"), "Sheet must show actual wallet and ship")
	var before: float = world.elapsed
	var traffic_before: float = world.traffic.elapsed
	scene._process(0.5)
	check(world.elapsed == before and world.traffic.elapsed == traffic_before and world.process_mode == Node.PROCESS_MODE_DISABLED, "Inspecting sheet pauses flight and living traffic")
	await key(KEY_ESCAPE)
	check(not scene.character_sheet.visible and not scene.pause_menu.visible and world.process_mode == Node.PROCESS_MODE_INHERIT, "Closing direct sheet resumes the game")
	await key(KEY_F2)
	check(scene.character_sheet.visible, "F2 also opens full sheet")
	await key(KEY_F2)
	await key(KEY_ESCAPE)
	check(scene.pause_menu.visible, "Escape opens pause menu")
	var menu_button: Button = scene.pause_menu.get_node("MenuOptions/Character")
	if DisplayServer.get_name() == "headless": menu_button.pressed.emit()
	else: await click(menu_button)
	check(scene.character_sheet.visible and not scene.pause_menu.visible, "Pause menu character button opens sheet")
	await key(KEY_ESCAPE)
	check(scene.pause_menu.visible and world.process_mode == Node.PROCESS_MODE_DISABLED, "Closing menu sheet returns to paused menu")
	await key(KEY_ESCAPE)
	# Every contact, including both carriers, must have an acceptable basic job at zero.
	for port in ["planet_dock", "britannian_carrier", "valois_carrier"]:
		if scene.landed: await scene.toggle_docking()
		world.highways.reset()
		world.ship.position = world.target_position(port) + Vector3(0, 0, 65)
		world.select_target(port)
		world.brake()
		await scene.toggle_docking()
		for contact in scene.mission.board.contacts(port):
			var offers: Array = scene.mission.board.offers(contact.id, world)
			check(offers.size() == 3 and int(offers[0].minimum_reputation) == 0 and offers[0].tier == "Basic", "Each contact must show basic job first")
			check(scene.mission.accept_error(contact.id, offers[0].id, market).is_empty(), "Zero standing must accept basic mission at " + str(contact.id))
			check(scene.mission.accept_error(contact.id, offers[1].id, market).contains("10") and scene.mission.accept_error(contact.id, offers[2].id, market).contains("25"), "Higher ranks must gate veteran and elite jobs")
			check(int(offers[0].reward) < int(offers[1].reward) and int(offers[1].reward) < int(offers[2].reward) and int(offers[0].count) < int(offers[2].count), "Ranked missions must pay more and field stronger/larger wings")
			market.reputation[contact.faction] = 10
			check(scene.mission.accept_error(contact.id, offers[1].id, market).is_empty(), "Ten standing unlocks veteran work")
			market.reputation[contact.faction] = 25
			check(scene.mission.accept_error(contact.id, offers[2].id, market).is_empty(), "Twenty-five standing unlocks elite work")
			market.reputation[contact.faction] = 0
	# Basic fallback survives template omissions, instead of returning all locked offers.
	var saved_templates: Array = scene.mission.board.config.templates.duplicate(true)
	scene.mission.board.config.templates = [saved_templates[1], saved_templates[2]]
	scene.mission.board.invalidate("british_marshal")
	var fallback: Array = scene.mission.board.offers("british_marshal", world)
	check(fallback.any(func(offer: Dictionary) -> bool: return int(offer.minimum_reputation) == 0), "A missing basic template must not remove entry-level work")
	scene.mission.board.config.templates = saved_templates
	scene.mission.board.invalidate("british_marshal")
	# A random planet visit must retain a neutral giver even when others dislike you.
	market.reputation.britannian = -8
	market.reputation.valois = -8
	market.reputation.hanseatic = -8
	market.reputation.borderlander = 0
	for seed_value in 16:
		scene.tavern.begin_visit(scene.mission.board.contacts("planet_dock"), "fluellen", seed_value, scene._tavern_eligible_ids())
		check(scene.tavern.contacts.any(func(entry: Dictionary) -> bool: return entry.id == "reeve") and scene.tavern.contacts.any(func(entry: Dictionary) -> bool: return entry.id == "fluellen"), "Tavern must retain both an eligible giver and pending issuer")
	# Footer button works while docked and displays meaningful locked scores.
	scene._sync_mouse_mode() # Normal frame update is disabled by this fixture.
	var footer: Button = scene.get_node("Interface/CharacterSheetButton")
	if DisplayServer.get_name() == "headless": footer.pressed.emit()
	else: await click(footer)
	check(scene.character_sheet.visible and scene.character_sheet.rows.britannian.score.text == "-8", "Footer button shows current negative reputation")
	check(scene.character_sheet.rows.britannian.access.text.contains("Need 0"), "Sheet must explain why a negative score cannot take basic jobs")
	market.reputation.britannian = 25
	scene.character_sheet.open_sheet()
	check(scene.character_sheet.rows.britannian.access.text.contains("Elite") and scene.character_sheet.rows.britannian.status.text == "TRUSTED", "Trusted standings show elite access")
	if not capture_dir.is_empty(): await scene._capture(capture_dir, "artois-character-sheet.png")
	scene.character_sheet.close_sheet()
	scene.open_contract()
	var was_visible: bool = scene.contract_panel.visible
	await key(KEY_I)
	check(scene.character_sheet.visible, "Sheet accessible from conversations")
	await key(KEY_ESCAPE)
	check(scene.contract_panel.visible == was_visible, "Closing sheet preserves underlying conversation")
	print("CHARACTER AND MISSION TIERS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
