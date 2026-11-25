extends SceneTree
var failures := 0
var capture_dir := ""
var save_path := "user://station_markets_%d.json" % OS.get_process_id()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _trade_run(state: LandingMarketState, from: String, to: String, id: String, expected: int) -> void:
	state.set_market(from)
	var credits := state.credits
	check(state.trade(id, 1, true).is_empty(), "Source must sell " + id)
	state.set_market(to)
	check(state.trade(id, 1, false).is_empty(), "Destination must buy " + id)
	check(state.credits == credits + expected, "Route must yield a modest predictable profit for " + id)


func _run() -> void:
	var state := LandingMarketState.new()
	state.save_path = save_path
	check(state.markets.ports().size() == 14, "Planet and thirteen station/camp ports must have market profiles")
	_trade_run(state, "planet_dock", "embry", "grain", 5)
	_trade_run(state, "planet_dock", "embry", "oxygen", 3)
	_trade_run(state, "embry", "planet_dock", "argent_ore", 16)
	_trade_run(state, "wrecked_shipyard", "planet_dock", "alloy", 10)
	_trade_run(state, "renty", "acheau", "wool", 5)
	_trade_run(state, "acheau", "border_post", "textiles", 9)
	_trade_run(state, "caulers", "southern_ship", "ale", 4)
	_trade_run(state, "st_paul", "agincourt", "medicine", 17)
	_trade_run(state, "planet_dock", "agincourt", "lamp_oil", 5)
	var stocks := state.market_stocks.duplicate(true)
	for port in state.markets.ports():
		state.set_market(port)
		for id in state.ITEMS:
			var quote := state.quote(id)
			check(int(quote.buy) > int(quote.sell) and int(quote.sell) >= 0, "Local quotes must never create same-market arbitrage")
			if quote.kind != "commodity": check(quote.buy == state.ITEMS[id].buy, "Outfitter prices must stay consistent")
			if quote.kind == "commodity" and not state.trades_good(id):
				check(not state.trade_error(id, 1, true).is_empty(), "Unavailable goods must not be purchasable")
	for port in stocks:
		check(stocks[port] == state.market_stocks[port], "Changing venue must not reset dealer stock")
	check(state.save_state(), "Multi-venue stock must save")
	var loaded := LandingMarketState.new()
	loaded.save_path = save_path
	check(loaded.load_state() and loaded.credits == state.credits and loaded.market_stocks == state.market_stocks, "Save must preserve every visited market and player balances")
	state.set_market("planet_dock")
	state.save_state()
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	legacy.erase("market_id")
	legacy.erase("market_stocks")
	for id in state.ITEMS:
		if id not in state.LEGACY_IDS: legacy.stock.erase(id)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	check(loaded.load_state() and loaded.market_id == "planet_dock" and loaded.stock.has("oxygen") and loaded.credits == state.credits, "Old single-market saves must migrate without losing player state")

	state.cargo["argent_ore"] = 1
	var scene: Control = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	scene.market_state = state
	scene.shop_panel.configure(state)
	scene.contract_panel.market = state
	var world := scene.space_world as ArtoisSpace
	# Exercise interiors with docking permission, including the outlaw port.
	state.reputation.freebooter = 0
	world.combat.configure(world, state)
	var population := world.traffic
	for id in state.markets.ports():
		world.highways.reset()
		world.brake()
		world.ship.position = world.target_position(id) + Vector3(0, 15, 60)
		world.select_target(id)
		check(world.docking_error().is_empty(), "Approach must enable docking at " + id)
		await scene.toggle_docking()
		check(scene.landed and scene.docked_id == id and state.market_id == id, "Docking must choose the matching interior and market")
		check(scene.landing_world.scene_file_path == state.markets.scene_path(id), "Each station must use its own scene resource")
		check(scene.landing_world.layers.size() == 6, "Landing must have six parallax layers")
		check(scene.contact_button.visible == (id == "planet_dock"), "Fluellen must remain on the planet only")
		scene.open_shop("commodities")
		check(scene.shop_panel.visible and scene.shop_panel._venue.text.contains(state.markets.profile(id).name.to_upper()), "Commodity shop must show the local venue")
		if id == "border_post":
			scene.shop_panel.selected_id = "argent_ore"
			scene.shop_panel._refresh()
			check(scene.shop_panel._buy.disabled and scene.shop_panel._sell.disabled and scene.shop_panel._totals.text.contains("NOT TRADED"), "Owned unsupported cargo must be visible without misleading local quotes")
		await scene.toggle_docking()
		check(scene.landed, "Open shops must block launch")
		scene.shop_panel.close_shop()
		scene.open_shop("equipment")
		check(scene.shop_panel.visible and scene.shop_panel.shop_kind == "equipment", "Every port must have an outfitter")
		scene.shop_panel.close_shop()
		if id in ["embry", "acheau", "st_paul"]:
			scene.landing_world.advance(0.3, Vector2(0.6, 0.1))
			scene._sync_shop_hotspots()
			await scene._capture(capture_dir, id + "-market-deck.png")
			if id == "embry" and DisplayServer.get_name() != "headless":
				await click(scene.shop_hotspots.buttons[0])
				check(scene.shop_panel.visible, "Clicking the station commodity counter must open the shop")
				var credits := state.credits
				await click(scene.shop_panel._buy)
				check(state.credits == credits - int(state.quote("grain").buy), "Station GUI purchase must use its local quote")
				await scene._capture(capture_dir, "embry-local-prices.png")
				scene.shop_panel.close_shop()
		if id == "st_paul": scene.mission.phase = "return"
		await scene.toggle_docking()
		if id == "st_paul": check(world.selected_id == world.DOCK_ID, "Launch must retain the mission return waypoint")
		check(not scene.landed and world.ship.position.is_equal_approx(world.launch_position()), "Launch must return outside the same port")
		check(world.active_port == id and world.traffic == population, "Station visits must preserve world/population identity")
	for id in ["calais_gate", "east_gate", "picardie_gate", "asques_gate", "arras", "maroeuil_wreck"]:
		world.ship.position = world.target_position(id) + Vector3(0, 0, 20)
		world.select_target(id)
		check(not world.docking_error().is_empty(), "Gate or bare wreck must not be treated as a station interior")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if failures == 0: print("PASS: local price routes, stock isolation, legacy saves, fourteen docks, both shops, parallax scenes, GUI trading and local launch")
	quit(0 if failures == 0 else 1)


func click(control: Control) -> void:
	var at := root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
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
