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
func click_held(button: Control, scene: Control) -> void:
	var at := root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
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
		for frame in 4:
			scene._process(1.0 / 60.0)
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
	market.save_path = "user://stories_smoke_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	world.combat.configure(world, market)
	var bar: Node2D = scene.tavern
	check(bar.guests.is_empty(), "Base room must remain people-free")
	var seen := {}
	var headlines := {}
	for seed_value in 32:
		bar.begin_visit(scene.mission.board.contacts("planet_dock"), "fluellen", seed_value, ["fluellen"])
		check(bar.stories.patrons.size() == 3 and bar.stories.news.size() == 4, "Three ordinary locals and four articles per visit")
		check(bar.guests.size() >= 6 and bar.guests.size() <= 8, "Room population stays bounded")
		check(bar.contacts.any(func(entry: Dictionary) -> bool: return entry.id == "fluellen"), "News must not displace pending mission issuer")
		var unique := {}
		for person in bar.stories.patrons:
			seen[person.id] = true
			unique[person.id] = true
			var topics: Array = bar.stories.topics(person.id, market)
			check(topics.size() == 3 and topics[2].kind == "VERIFIED TRADE TIP", "Every speaker has two authored topics and a real trade tip")
			check(bar.social_rect(person.id).has_area(), "Every local needs a parallax click rectangle")
			for guest in bar.guests:
				if guest.talk_id == person.id:
					check(guest.column == int(person.cell) % 4 and guest.row == int(int(person.cell) / 4), "Speaker must use the matching generated portrait cell")
		check(unique.size() == 3, "No duplicate local speakers")
		for article in bar.stories.news: headlines[article.id] = true
	check(seen.size() == 8 and headlines.size() == 8, "Repeated landings expose all eight people and all articles")
	var tip: Dictionary = bar.stories.trade_tip(market, "grain", "planet_dock", "border_post")
	check(tip.text.contains("40 cr") and tip.text.contains("45 cr") and tip.text.contains("5 cr"), "Trade margin must use buy at origin and sell at destination")
	check(bar.stories.trade_tip(market, "missing", "planet_dock", "border_post").is_empty(), "Unsupported route must not invent prices")
	world.ship.position = world.target_position("planet_dock") + Vector3(0, 0, 65)
	world.select_target("planet_dock")
	world.brake()
	await scene.toggle_docking()
	scene.enter_tavern()
	scene._sync_mouse_mode()
	bar.cinematic_motion = false
	bar.parallax_enabled = false
	bar.advance(0.1, Vector2.ZERO)
	scene._sync_shop_hotspots()
	var snapshot: String = JSON.stringify([bar.stories.patrons, bar.stories.news])
	var signature: String = bar.signature
	if not capture_dir.is_empty(): await scene._capture(capture_dir, "artois-tavern-locals.png")
	for button in scene.social_hotspots:
		check(button.visible, "Local, innkeeper and notice-board hotspots must be present")
		var id: String = button.get_meta("talk_id")
		if DisplayServer.get_name() == "headless": button.pressed.emit()
		else: await click_held(button, scene)
		check(scene.stories_panel.visible, "Held click opens local talk or news: " + id)
		if id not in ["news", "innkeeper"]:
			check(scene.stories_panel._heading.text.contains(bar.stories.patron(id).name), "Click opens this person's own dialogue")
			check(scene.stories_panel.entries.size() == 3, "Local discussion includes all three topics")
			scene.stories_panel._list.select(2)
			scene.stories_panel._list.item_selected.emit(2)
			check(scene.stories_panel._kind.text == "VERIFIED TRADE TIP", "Selecting a topic updates its category and body")
		else:
			check(scene.stories_panel.entries.size() == 5, "News includes actual personal docket and four selected reports")
		var camera: Vector2 = bar.camera_position
		scene._process(0.2)
		check(bar.camera_position == camera, "Reading freezes parallax camera")
		await key(KEY_ENTER)
		check(scene.landed and scene.stories_panel.visible, "Enter must not launch while reading")
		await key(KEY_I)
		check(scene.character_sheet.visible, "Character sheet can overlay local talk")
		await key(KEY_ESCAPE)
		check(scene.stories_panel.visible and not scene.character_sheet.visible, "Closing sheet preserves conversation")
		await key(KEY_ESCAPE)
		check(not scene.stories_panel.visible and not scene.pause_menu.visible, "Escape closes reading before pause")
		scene._sync_shop_hotspots()
	market.credits = 12345
	market.reputation.valois = 11
	await key(KEY_6)
	check(scene.stories_panel.visible and scene.stories_panel.entries[-1].text.contains("12345") and scene.stories_panel.entries[-1].text.contains("11"), "News shortcut includes actual current captain state")
	if not capture_dir.is_empty():
		scene.stories_panel._select(1)
		await scene._capture(capture_dir, "artois-tavern-gazette.png")
	await key(KEY_ESCAPE)
	scene.open_local_talk(bar.stories.patrons[0].id)
	if not capture_dir.is_empty(): await scene._capture(capture_dir, "artois-tavern-rumours.png")
	var credits: int = market.credits
	var reputation: Dictionary = market.reputation.duplicate(true)
	scene.stories_panel.close_panel()
	scene.leave_tavern()
	scene.enter_tavern()
	check(bar.signature == signature and JSON.stringify([bar.stories.patrons, bar.stories.news]) == snapshot, "Market re-entry preserves visit's people, topics and news")
	check(market.credits == credits and market.reputation == reputation, "Conversations must not change money or reputation")
	scene.open_local_talk("not_present")
	check(not scene.stories_panel.visible, "Absent local cannot be addressed remotely")
	scene.leave_tavern()
	await key(KEY_6)
	check(not scene.stories_panel.visible and not scene.news_button.visible, "Gazette is a tavern service")
	print("TAVERN RUMOURS AND NEWS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
