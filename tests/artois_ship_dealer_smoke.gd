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
	var market := LandingMarketState.new()
	market.save_path = "user://dealer_smoke_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	world.combat.configure(world, market)
	check(market.Ships.catalog.size() == 3, "Exactly three starter/standard ships")
	check(market.ship_purchase_error("fighter").contains("already"), "Cannot rebuy current ship")
	check(market.purchase_ship("interceptor").is_empty() and market.credits == 5500 and market.capacity() == 8, "Kestrel purchase deducts net price and changes hold")
	scene._apply_loadout()
	check(world.combat.hull_max == 85 and world.combat.defence.armour_max == 45 and world.ship.has_node("PurchasedHull"), "Purchase must change playable stats and model")
	world._advance_manual(2.0, Vector2.ZERO, 1.0, false)
	check(is_equal_approx(world.velocity.length(), 45.0), "Interceptor must reach its advertised flight speed")
	world.brake()
	if not capture_dir.is_empty():
		world.reset_view()
		scene._process(0)
		await scene._capture(capture_dir, "artois-kestrel-flight.png")
	market.cargo = {"grain": 8}
	market.utility = "cargo_expander"
	market.credits = 50000
	check(market.purchase_ship("pilgrim").is_empty() and market.capacity() == 100 and market.owned("grain") == 8, "Trader gets larger hold and preserves cargo/equipment")
	scene._apply_loadout()
	check(world.combat.hull == 200 and world.combat.defence.armour == 110 and world.combat.shield_max == 75, "Trader hull/armour/ward must apply")
	world._advance_manual(2.0, Vector2.ZERO, 1.0, false)
	check(is_equal_approx(world.velocity.length(), 28.0), "Trader must have slower flight speed")
	world.cruise = true
	world._advance_manual(2.0, Vector2.ZERO, 0.0, false)
	check(is_equal_approx(world.velocity.length(), 140.0), "Cruise must remain five times this hull speed")
	world.brake()
	if not capture_dir.is_empty():
		world.reset_view()
		scene._process(0)
		await scene._capture(capture_dir, "artois-pilgrim-flight.png")
	market.cargo = {"grain": 30}
	var before: int = market.credits
	check(not market.purchase_ship("interceptor").is_empty() and market.ship_class == "pilgrim" and market.credits == before, "Downsizing must refuse excess cargo without losses")
	market.cargo = {"grain": 3}
	market.reputation.borderlander = -20
	check(market.ship_purchase_error("fighter").contains("REFUSED"), "Dealer requires normal standing")
	world.ship.position = world.target_position("planet_dock") + Vector3(0, 0, 50)
	world.select_target("planet_dock")
	world.brake()
	check(world.docking_error().contains("REFUSED"), "Planet landing must check reputation")
	market.reputation.borderlander = -19
	check(world.docking_error().is_empty(), "Neutral standing must permit landing")
	market.reputation.valois = -50
	world.ship.position = world.target_position("agincourt") + Vector3(0, 0, 50)
	world.select_target("agincourt")
	check(world.docking_error().contains("VALOIS"), "Castle must use Valois reputation")
	for port in market.markets.ports():
		var owner: String = world.law.territory_owner(port)
		if owner.is_empty(): continue
		var original: int = market.reputation[owner]
		market.reputation[owner] = -50
		check(not market.Factions.access_error(market.reputation, port).is_empty(), "Every owned port must refuse hostile factions: " + port)
		market.reputation[owner] = original
	market.reputation.borderlander = 0
	# Future faction hull requirements are independent of port reputation.
	market.Ships.catalog.fighter.required_faction = "britannian"
	market.Ships.catalog.fighter.minimum_reputation = 25
	check(market.ship_purchase_error("fighter").contains("25"), "Higher faction licence must block purchase")
	market.reputation.britannian = 25
	check(market.ship_purchase_error("fighter").is_empty(), "Required positive faction standing must unlock hull")
	market.Ships.catalog.fighter.erase("required_faction")
	market.Ships.catalog.fighter.minimum_reputation = -19
	# Failed save must roll back both the hull and payment.
	var good_path: String = market.save_path
	market.save_path = "user://missing_dealer_folder/save.json"
	before = market.credits
	check(market.purchase_ship("fighter").contains("saved") and market.ship_class == "pilgrim" and market.credits == before, "Failed persistence must not spend credits/change hull")
	market.save_path = good_path
	check(market.save_state(), "Save trader state")
	var loaded := LandingMarketState.new()
	loaded.save_path = market.save_path
	check(loaded.load_state() and loaded.ship_class == "pilgrim" and loaded.capacity() == 100, "Purchased ship must survive restart")
	market.reputation.borderlander = 0
	world.ship.position = world.target_position("planet_dock") + Vector3(0, 0, 50)
	world.select_target("planet_dock")
	await scene.toggle_docking()
	check(scene.landed and scene.dealer_button.visible, "Planet must expose dealer")
	scene._sync_shop_hotspots()
	scene._sync_mouse_mode()
	if DisplayServer.get_name() == "headless": scene.open_shop("ships")
	else: await click(scene.dealer_hotspot)
	check(scene.shop_panel.visible and scene.shop_panel.shop_kind == "ships" and scene.shop_panel._tree.get_root().get_child_count() == 3, "Dealer modal lists three hulls")
	scene.shop_panel.selected_id = "fighter"
	scene.shop_panel._details()
	if not capture_dir.is_empty(): await scene._capture(capture_dir, "artois-ship-dealer.png")
	if DisplayServer.get_name() == "headless": scene.shop_panel._buy.pressed.emit()
	else: await click(scene.shop_panel._buy)
	check(market.ship_class == "fighter" and world.combat.hull_max == 120 and not world.ship.has_node("PurchasedHull"), "GUI purchase must immediately apply new hull")
	scene.shop_panel.close_shop()
	await scene.toggle_docking()
	# Real emergency recovery must never strand a player barred from the planet.
	market.reputation.borderlander = -100
	world.combat.dead = true
	await scene._recover_from_defeat()
	check(scene.landed and scene.docked_id == "st_paul" and not world.combat.dead and market.reputation.borderlander == -100, "Defeat must recover at neutral chapter without erasing reputation")
	check(not scene.dealer_button.visible, "Station must not expose planet dealer")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(market.save_path))
	print("SHIP DEALER AND DOCKING LAW: %s" % ("PASS" if failures == 0 else "FAIL"))
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
