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
	var loot: Node3D = world.loot
	var market := LandingMarketState.new()
	market.save_path = "user://cargo_smoke_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	world.combat.configure(world, market)
	check(market.capacity() == 20, "Legacy player fighter must retain twenty cargo units")
	check(market.set_ship_class("cog").is_empty() and market.capacity() == 120, "Freighter must have a substantially bigger hold")
	market.cargo = {"grain": 110}
	check(market.save_state(), "Larger cargo stack must save")
	var loaded := LandingMarketState.new()
	loaded.save_path = market.save_path
	check(loaded.load_state() and loaded.capacity() == 120 and loaded.owned("grain") == 110, "Freighter class/large stacks must load")
	check(not market.set_ship_class("interceptor").is_empty() and market.capacity() == 120, "Cannot switch to a ship that cannot fit the cargo")
	market.cargo.clear()
	check(market.set_ship_class("fighter").is_empty(), "Ship change must work once cargo fits")
	# Legacy saves without the optional ship class remain loadable as fighter.
	market.save_state()
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(market.save_path))
	old.erase("ship_class")
	var file := FileAccess.open(market.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	check(loaded.load_state() and loaded.ship_class == "fighter", "Legacy save must load without resetting inventory")
	for actor in world.traffic.actors.values():
		var used := 0
		for id in actor.hold:
			check(LandingMarketState.ITEMS.has(id) and LandingMarketState.ITEMS[id].kind == "commodity", "NPC cargo must use real shop commodities")
			used += int(actor.hold[id])
		check(used <= actor.cargo_capacity, "NPC manifest must fit its defined hull")
	check(world.traffic.actors.local_hanseatic_01.cargo_capacity == 120 and world.traffic.actors.local_raider_01.cargo_capacity == 20, "Cog must carry more than a fighter")
	var trader: Dictionary = world.traffic.actors.local_hanseatic_02
	trader.leg = trader.path.size()
	world.traffic._civilian_step(trader, 0.1)
	check(trader.hold.is_empty() and trader.state == "DOCKED", "Delivery must actually unload NPC cargo")
	world.traffic._next_trip(trader)
	check(not trader.hold.is_empty(), "Departing trader must load a fresh real manifest")
	world.ship.position = Vector3(0, 1800, 0)
	world.brake()
	loot._random.seed = 1215
	var seen := {}
	for i in 40:
		var amount: int = loot.survivors(30)
		seen[amount] = true
		check(amount >= 0 and amount < 30, "Drop roll must always destroy part of the cargo")
	check(seen.size() > 3 and loot.survivors(1) == 0, "Survival must be randomized, with single units destroyed")
	# A real NPC death empties its manifest and creates only surviving real goods.
	var actor: Dictionary = world.traffic.actors.local_hanseatic_01
	actor.node.position = world.ship.position + Vector3(0, 0, -75)
	actor.node.visible = true
	actor.hold = {"grain": 60, "alloy": 25}
	actor.hull = 10
	actor.shield = 0
	world.traffic.damage(actor.id, 100, 100)
	check(not actor.alive and actor.hold.is_empty(), "Destroyed NPC must lose its actual hold")
	var surviving := {"grain": 0, "alloy": 0}
	for crate in loot.canisters.values():
		check(surviving.has(crate.good), "Loot must not invent goods absent from the destroyed ship")
		surviving[crate.good] += int(crate.quantity)
		check(int(crate.quantity) <= loot.UNITS_PER_CANISTER and crate.node is MeshInstance3D, "Survivors must be visible canisters with bounded stacks")
	check(surviving.grain < 60 and surviving.alloy < 25, "Each real cargo stack must suffer destruction")
	var count: int = loot.canisters.size()
	world.traffic.damage(actor.id, 100, 100)
	check(loot.canisters.size() == count, "A ship must not drop loot twice")
	world.combat.spawn_patrol(world.ship.position + Vector3(0, 0, -100))
	var fighter: Node3D = world.combat.enemies[0]
	check(fighter.get_meta("cargo_capacity") == 8, "Quest interceptor must have a small hold")
	world.combat.damage_enemy("patrol_1", 10000)
	check(fighter.get_meta("cargo_hold").is_empty() and fighter.get_meta("cargo_dropped"), "Quest combat death must use the same cargo-loss system")
	world.combat.clear_encounter()
	# Close-range pickup is partial, persistent and does not spend money or dealer stock.
	var crate_id: String = loot.spawn("grain", 10, world.ship.position + Vector3(0, 0, -10))
	loot.canisters[crate_id].node.position = world.ship.position + Vector3(0, 0, -10)
	world.select_target(crate_id)
	check(world.target_entry().kind == "cargo", "Canisters must be selectable contacts")
	market.cargo = {"alloy": 17}
	var credits := market.credits
	var stock := market.stock.duplicate(true)
	var result: Dictionary = loot.pickup()
	check(result.taken == 3 and market.cargo_used() == 20 and loot.canisters[crate_id].quantity == 7, "Pickup must take only free hold space and leave the remainder")
	check(market.credits == credits and market.stock == stock, "Salvage must not alter credits or market stock")
	check(loaded.load_state() and loaded.cargo_used() == 20 and loaded.owned("grain") == 3, "Recovered cargo must persist")
	result = loot.pickup()
	check(result.taken == 0 and loot.canisters[crate_id].quantity == 7, "Full hold must leave canister unchanged")
	market.cargo.clear()
	var good_path := market.save_path
	market.save_path = "user://missing_cargo_directory/state.json"
	result = loot.pickup()
	check(result.taken == 0 and market.cargo.is_empty() and loot.canisters[crate_id].quantity == 7, "Failed save must not consume loot or duplicate cargo")
	market.save_path = good_path
	loot.canisters[crate_id].node.position = world.ship.position + Vector3(0, 0, -100)
	for id in loot.canisters:
		if id != crate_id: loot.canisters[id].node.position = world.ship.position + Vector3(200, 0, 0)
	check(loot.pickup().taken == 0, "Distant canisters must be out of pickup range")
	loot.canisters[crate_id].node.position = world.ship.position + Vector3(0, 0, -10)
	world.engage_cruise()
	check(loot.pickup().taken == 0, "Cruise charging must lock tractor pickup")
	world.cancel_cruise()
	# Real H input collects, then removes the empty canister and its target.
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_H
		key.physical_keycode = KEY_H
		key.pressed = pressed
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		await process_frame
	check(not loot.has(crate_id) and market.owned("grain") == 7, "Physical H must collect a nearby canister exactly once")
	check(world.selected_id == world.DOCK_ID, "Empty canister must not leave an invalid selected target")
	check(market.trade("grain", 1, false).is_empty() and market.owned("grain") == 6, "Recovered cargo must sell through the existing commodity shop rules")
	# Player loss is also saved before its recoverable portion appears in space.
	market.cargo = {"grain": 12}
	market.save_state()
	loot.drop_player()
	check(market.cargo.is_empty() and loaded.load_state() and loaded.cargo.is_empty(), "Player loss must clear and save the hold")
	count = loot.canisters.size()
	loot.drop_player()
	check(loot.canisters.size() == count, "Player cargo cannot be duplicated by repeated death handling")
	world.combat.repair()
	# Loot ages/drifts, and chart/pause freezes its simulation.
	crate_id = loot.spawn("argent_ore", 5, world.ship.position + Vector3(0, 0, -18), Vector3.RIGHT)
	world.select_target(crate_id)
	var before: Vector3 = loot.canisters[crate_id].node.position
	world.advance(0.2, Vector2.ZERO, 0, false, false)
	check(loot.canisters[crate_id].node.position != before, "Floating canister must drift")
	scene.toggle_chart()
	var age: float = loot.canisters[crate_id].age
	scene._process(0.5)
	check(loot.canisters[crate_id].age == age, "Chart must freeze loot with the world")
	scene.toggle_chart()
	if not capture_dir.is_empty():
		for id in loot.canisters: loot.canisters[id].node.position = world.ship.position + Vector3(5 if id == crate_id else -4, 0, -12 if id == crate_id else -18)
		world.combat.ordnance.message_time = 0
		world.ship.rotation = Vector3.ZERO
		world.reset_view()
		scene._process(0)
		scene.target_hud.queue_redraw()
		await scene._capture(capture_dir, "artois-cargo-canisters.png")
	loot.canisters[crate_id].node.position = world.ship.position + Vector3(18, 6, -10)
	world.camera.position = loot.canisters[crate_id].node.position + Vector3(0, 0, 20)
	world.camera.look_at(loot.canisters[crate_id].node.position)
	check(scene.Picking.pick(world, world.camera.unproject_position(loot.canisters[crate_id].node.position)) == crate_id, "Space ray picking must include physical canisters")
	world.ship.position = loot.canisters[crate_id].node.position + Vector3(0, 0, 150)
	world.brake()
	world.navigate_to(crate_id)
	for frame in 400:
		world.advance(0.05, Vector2.ZERO, 0, false, false)
		if not world.autopilot: break
	check(world.ship.position.distance_to(loot.canisters[crate_id].node.position) <= loot.RANGE, "G navigation must stop inside collection range")
	loot.canisters[crate_id].age = loot.LIFETIME
	loot.advance(0)
	check(not loot.has(crate_id), "Expired canisters must be removed")
	for i in loot.MAX_CANISTERS + 2: loot.spawn("grain", 1, world.ship.position + Vector3(400, 0, 0))
	check(loot.canisters.size() == loot.MAX_CANISTERS, "Repeated encounters must not create unbounded loot nodes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(market.save_path))
	print("CARGO AND SALVAGE: %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)
