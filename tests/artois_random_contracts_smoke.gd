extends SceneTree
var failures := 0
var capture_dir := ""
var scene: Control
var world: Node3D
var market: LandingMarketState
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func dock(port: String) -> void:
	if scene.contract_panel.visible: scene.contract_panel.close_panel()
	if scene.landed:
		await scene.toggle_docking()
		if scene.mission.phase == "return": check(world.selected_id == scene.mission.return_port(), "Return waypoint must remain the original issuer after launch")
	world.highways.reset()
	world.ship.position = world.target_position(port) + Vector3(0, 0, 65)
	world.select_target(port)
	world.brake()
	await scene.toggle_docking()
	scene._sync_mouse_mode()
	check(scene.landed and scene.docked_id == port and world.docked, "Dock at " + port)
func kill(id: String) -> void:
	world.combat.damage_enemy(id, 100000, 100000, world.ship.position)
func run() -> void:
	scene = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	world = scene.space_world
	market = LandingMarketState.new()
	market.save_path = "user://random_contracts_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	world.combat.configure(world, market)
	var mission: RefCounted = scene.mission
	var board: RefCounted = mission.board
	board._random.seed = 1415007
	check(board.contacts("planet_dock").size() == 4 and board.contacts("valois_carrier").size() == 1 and board.contacts("britannian_carrier").size() == 1, "Four planet contacts and one per carrier")
	var identities := {}
	var sites := {}
	for contact in board.config.contacts:
		var offers: Array = board.offers(contact.id, world)
		check(offers.size() == 3 and offers == board.offers(contact.id, world), "Offers must remain stable while browsing")
		for offer in offers:
			check(not identities.has(offer.id), "Offers need unique encounter identity")
			identities[offer.id] = true
			sites[str(offer.site)] = true
			check(offer.count >= 2 and offer.count <= 6 and offer.reward > 0 and offer.port == contact.port and offer.faction == contact.faction, "Bounded generated encounter/rewards/issuer")
			var position: Vector3 = world.layout.world({"map": [offer.site.x, offer.site.y], "altitude": offer.altitude})
			for entry in world.layout.locations:
				check(position.distance_to(world.layout.world(entry)) >= 650, "Sites must avoid docking and guard locations")
			check(offer.objective == (1 if offer.template == "bounty" else offer.count), "Bounty must require captain only")
		offers[0].reward = 1
		check(board.offers(contact.id, world)[0].reward != 1, "Browsing cannot mutate cached offers")
	check(sites.size() > 10 and world.combat.enemies.is_empty(), "Random positions must vary; browsing must not spawn enemies")
	var first: Dictionary = board.offers("fluellen", world)[0]
	check(not mission.accept_offer("fluellen", first.id, market), "Cannot accept from space using a stale market id")
	await dock("planet_dock")
	scene.enter_tavern()
	# Keep all four contacts in this contract-board fixture; tavern randomness is tested separately.
	for seed_value in range(1, 32):
		scene.tavern.begin_visit(board.contacts("planet_dock"), "fluellen", seed_value)
		if scene.tavern.contacts.size() == 4: break
	market.reputation.britannian = -20
	check(not mission.accept_error("fluellen", first.id, market).is_empty(), "Hostile/wary issuers must deny work")
	market.reputation.britannian = 0
	check(mission.accept_error("fluellen", board.offers("fluellen", world)[2].id, market).contains("10"), "Harder bounties need standing")
	if DisplayServer.get_name() == "headless": scene.open_contract("fluellen")
	else:
		scene._sync_shop_hotspots()
		if not capture_dir.is_empty(): await scene._capture(capture_dir, "artois-faction-contacts.png")
		await click(patron_button("factor"))
		check(scene.contract_panel.contact_id == "factor", "Clicking Hanseatic street contact must select their faction")
		scene.contract_panel.close_panel()
		await click(patron_button("fluellen"))
	check(scene.contract_panel.visible and scene.contract_panel._contacts.item_count == 4 and scene.contract_panel._offers.get_root().get_child_count() == 3, "Planet contact GUI lists faction givers and three offers")
	if DisplayServer.get_name() != "headless":
		var tree: Tree = scene.contract_panel._offers
		await click(tree, tree.get_item_area_rect(tree.get_root().get_child(2)).get_center())
		check(scene.contract_panel._action.disabled, "Selecting a locked bounty must disable acceptance in the actual GUI")
		await click(tree, tree.get_item_area_rect(tree.get_root().get_child(0)).get_center())
		check(not scene.contract_panel._action.disabled, "Selecting an eligible patrol must restore acceptance")
	if not capture_dir.is_empty(): await scene._capture(capture_dir, "artois-faction-contracts.png")
	if DisplayServer.get_name() == "headless": scene.contract_panel._act()
	else: await click(scene.contract_panel._action)
	check(mission.phase == "active" and world.combat.enemies.size() == int(first.count) and not world.layout.target(mission.TARGET_ID).is_empty(), "GUI acceptance creates exactly one bounded mission encounter and waypoint")
	check(not mission.accept_offer("reeve", board.offers("reeve", world)[0].id, market), "Cannot accept second job while one is active")
	mission._on_enemy_destroyed("local_freebooter_01")
	mission._on_enemy_destroyed("contract_stale_1")
	check(mission.kills == 0, "Ambient and stale kills cannot count")
	scene.contract_panel.close_panel()
	await scene.toggle_docking()
	check(not world.docked and world.selected_id == mission.TARGET_ID, "Launch tracks mission destination")
	var site: Vector3 = world.target_position(mission.TARGET_ID)
	world.ship.position = site + Vector3(0, 0, 700)
	world.combat.advance(0)
	check(not world.combat.enemies[0].get_meta("active"), "Encounter waits for proximity")
	world.ship.position = site + Vector3(0, 0, 180)
	world.combat.advance(0)
	check(world.combat.enemies[0].get_meta("active"), "Encounter engages nearby player")
	var ids: Array = world.combat.enemies.map(func(enemy: Node3D) -> String: return str(enemy.get_meta("id")))
	for id in ids: kill(id)
	check(mission.phase == "return" and mission.kills == int(first.count) and world.selected_id == "planet_dock", "Patrol completion tracks issuing port")
	mission._on_enemy_destroyed(ids[0])
	check(mission.kills == int(first.count) and not mission.claim(market, "fluellen"), "No double kills or remote claim")
	await dock("planet_dock")
	check(not mission.claim(market, "reeve"), "Wrong faction contact cannot pay")
	scene.open_contract("fluellen")
	var old_credits: int = market.credits
	scene.contract_panel._act()
	check(mission.phase == "paid" and market.credits == old_credits + int(first.reward) and market.reputation.britannian == int(first.reputation), "Correct issuer pays generated reward and only its own reputation")
	check(market.reputation.valois == 0 and not mission.claim(market, "fluellen"), "No cross-faction or duplicate reward")
	check(world.layout.target(mission.TARGET_ID).is_empty() and board.offers("fluellen", world)[0].id != first.id, "Claim cleans marker and refreshes resolved board")
	scene.contract_panel.close_panel()
	# Carrier raider contract returns to that carrier, without revealing allegiance.
	await dock("valois_carrier")
	scene.open_contract()
	check(scene.contact_button.visible and scene.contract_panel._contacts.item_count == 1, "Carrier exposes its naval quest giver")
	var raid: Dictionary = board.offers("valois_captain", world)[1]
	check(mission.accept_offer("valois_captain", raid.id, market), "Valois raider contract accepts")
	scene.contract_panel.close_panel()
	await scene.toggle_docking()
	check(world.combat.enemies[0].get_meta("faction") == "raider" and world.combat.enemies[0].get_meta("display_name").begins_with("Unidentified"), "Raider identity must remain public")
	for enemy in world.combat.enemies.duplicate(): kill(str(enemy.get_meta("id")))
	check(mission.return_port() == "valois_carrier" and world.selected_id == "valois_carrier" and market.reputation.valois == 0, "Raid completion returns to carrier without Valois crime penalties")
	check(not mission.claim(market, "valois_captain"), "Carrier contract cannot be paid remotely")
	await dock("planet_dock")
	check(not mission.claim(market, "valois_captain"), "Planet visit cannot substitute for carrier return")
	await dock("valois_carrier")
	scene.open_contract()
	if not capture_dir.is_empty(): await scene._capture(capture_dir, "valois-contract-return.png")
	var path: String = market.save_path
	market.save_path = "user://missing_random_contract_folder/save.json"
	old_credits = market.credits
	check(not mission.claim(market, "valois_captain") and mission.phase == "return" and market.credits == old_credits and market.reputation.valois == 0, "Failed reward save rolls back money and standing without losing claim")
	market.save_path = path
	check(mission.claim(market, "valois_captain") and market.reputation.valois == int(raid.reputation), "Carrier can pay successful retry")
	# Named captain is the sole bounty objective; escorts are optional.
	scene.contract_panel.close_panel()
	await dock("britannian_carrier")
	market.reputation.britannian = 25
	var bounty: Dictionary = board.offers("british_marshal", world)[2]
	check(mission.accept_offer("british_marshal", bounty.id, market), "Trusted standing unlocks captain bounty")
	scene.contract_panel.close_panel()
	await scene.toggle_docking()
	world.ship.position = world.target_position(mission.TARGET_ID) + Vector3(0, 40, 220)
	world.ship.look_at(world.target_position(mission.TARGET_ID))
	world._sync_angles()
	world.reset_view()
	var captain: String = str(world.combat.enemies[0].get_meta("id"))
	var escort: String = str(world.combat.enemies[1].get_meta("id"))
	check(world.combat.enemies[0].get_meta("display_name") == "Captain " + bounty.captain, "Captain name must match briefing")
	check(bool(world.combat.enemies[0].get_meta("bounty_target")) and not bool(world.combat.enemies[1].get_meta("bounty_target")), "Wanted captain must have a unique objective marker")
	world.select_target(captain)
	scene._process(0)
	if not capture_dir.is_empty(): await scene._capture(capture_dir, "artois-captain-bounty.png")
	kill(escort)
	check(mission.kills == 0 and mission.phase == "active", "Escort kills must not complete bounty")
	kill(captain)
	check(mission.kills == 1 and mission.phase == "return" and not world.combat.enemies.is_empty(), "Captain kill alone completes bounty; surviving escorts remain until resolution")
	await dock("britannian_carrier")
	check(mission.claim(market, "british_marshal") and world.combat.enemies.is_empty(), "Claim cleans surviving mission escorts")
	var loaded := LandingMarketState.new()
	loaded.save_path = market.save_path
	check(loaded.load_state() and loaded.credits == market.credits and loaded.reputation == market.reputation, "Generated rewards must persist")
	# Abandon/fail remove only the dedicated encounter, not the living population.
	var roster: int = world.traffic.actors.size()
	var next: Dictionary = board.offers("british_marshal", world)[0]
	check(mission.accept_offer("british_marshal", next.id, market), "New job available after completion")
	old_credits = market.credits
	check(mission.abandon() and world.combat.enemies.is_empty() and world.layout.target(mission.TARGET_ID).is_empty() and market.credits == old_credits, "Abandon cleans without payment")
	next = board.offers("british_marshal", world)[0]
	check(mission.accept_offer("british_marshal", next.id, market), "Can accept after abandonment")
	mission.fail()
	check(mission.phase == "failed" and world.combat.enemies.is_empty() and world.layout.target(mission.TARGET_ID).is_empty() and world.traffic.actors.size() == roster, "Defeat cleans contract without resetting ambient ships")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(market.save_path))
	print("RANDOM FACTION CONTRACTS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
func click(control: Control, local := Vector2.INF) -> void:
	if not local.is_finite(): local = control.size * 0.5
	var at := root.get_final_transform() * (control.get_global_transform_with_canvas() * local)
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

func patron_button(id: String) -> Button:
	for button in [scene.contact_hotspot] + scene.faction_hotspots:
		if str(button.get_meta("contact_id", "")) == id: return button
	return scene.contact_hotspot
