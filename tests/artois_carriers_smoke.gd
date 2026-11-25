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
	market.save_path = "user://carrier_smoke_%d.json" % OS.get_process_id()
	market.credits = 100000
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	world.combat.configure(world, market)
	check(world.landmarks.has("valois_carrier") and world.landmarks.has("britannian_carrier"), "Both carriers must have geometry")
	check(world.target_position("valois_carrier").distance_to(world.target_position("agincourt")) < 600, "Valois carrier must be near castle")
	check(world.target_position("britannian_carrier").z < world.target_position("calais_gate").z, "Britannian carrier must be north of gate")
	for attitude in [Vector3.ZERO, Vector3(0.4, 1.2, 0.1), Vector3(-0.6, -2.0, 0)]:
		world.ship.rotation = attitude
		world._update_camera(0)
		check(world.camera.unproject_position(world.ship.global_position).distance_to(Vector2(scene.space_view.size) / 2) < 0.1, "Hull must project to exact viewport centre at every attitude")
		world.ship.rotation.y += 0.2
		world._update_camera(0.1)
		check(world.camera.unproject_position(world.ship.global_position).distance_to(Vector2(scene.space_view.size) / 2) < 0.1, "Camera lag must not move ship off centre")
	check(float(market.Ships.catalog.fighter.turn) > 1.0, "Starting Warden must turn faster")
	# A hit on one Valois patrol alerts the pair without globally condemning the player.
	var guard: Dictionary = world.traffic.actors.local_valois_navy_01
	var partner: Dictionary = world.traffic.actors.local_valois_navy_04
	var remote: Dictionary = world.traffic.actors.local_valois_navy_02
	world.ship.position = guard.node.position + Vector3(0, 0, 100)
	world.traffic.damage(guard.id, 1, 1)
	check(partner.provoked and partner.target == "player", "Patrol partner must immediately retaliate")
	check(not remote.provoked and not world.traffic.actors.local_britannian_navy_01.provoked, "Remote patrol and other faction must not be alerted")
	check(market.reputation.valois == -8, "Alerting a partner must not add another assault penalty")
	world.traffic._choose_prey(partner)
	check(partner.target == "player", "Partner must retain legal local combat target on next AI decision")
	# The carrier remains accessible at neutral standing but its fighter needs trust.
	for pair in [["valois_carrier", "epervier", "valois"], ["britannian_carrier", "longbow", "britannian"]]:
		var port: String = pair[0]
		var hull: String = pair[1]
		var faction: String = pair[2]
		market.reputation[faction] = 0
		world.highways.reset()
		world.brake()
		world.ship.position = world.target_position(port) + Vector3(0, 0, 70)
		world.select_target(port)
		check(world.docking_error().is_empty(), "Neutral carrier approach must permit docking")
		await scene.toggle_docking()
		check(scene.landed and scene.docked_id == port and scene.dealer_button.visible, "Carrier must have working hangar and ship dealer")
		scene.open_shop("ships")
		check(scene.shop_panel._tree.get_root().get_child_count() == 1 and scene.shop_panel.selected_id == hull, "Carrier must sell only its faction fighter")
		check(scene.shop_panel._buy.disabled and market.ship_purchase_error(hull).contains("25"), "Neutral rep must not buy naval fighter")
		market.reputation[faction] = 25
		scene.shop_panel._refresh()
		check(not scene.shop_panel._buy.disabled, "Trusted naval standing must unlock purchase")
		if not capture_dir.is_empty(): await scene._capture(capture_dir, port + "-dealer.png")
		scene.shop_panel._buy.pressed.emit()
		check(market.ship_class == hull and world.ship.has_node("PurchasedHull") and world.combat.hull_max == float(market.Ships.profile(hull).hull), "Naval purchase must fit playable faction hull")
		scene.shop_panel.close_shop()
		await scene.toggle_docking()
		check(not scene.landed and world.active_port == port, "Launch must return outside same carrier")
		if not capture_dir.is_empty():
			world.ship.rotation = Vector3.ZERO
			world.reset_view()
			scene._process(0)
			await scene._capture(capture_dir, port + "-flight.png")
		market.reputation[faction] = -20
		world.ship.position = world.target_position(port) + Vector3(0, 0, 70)
		check(world.docking_error().contains("REFUSED"), "Wary carrier reputation must deny docking")
	market.set_market("planet_dock")
	check(market.ship_purchase_error("longbow").contains("not sold"), "Civilian dealer must not bypass carrier exclusivity")
	# Reputation is earned through the existing contract, saved with payment, once.
	market.reputation.britannian = 0
	market.reputation.valois = 0
	for i in 3:
		scene.mission.phase = "return"
		check(scene.mission.claim(market), "Contract payout must succeed")
	check(market.reputation.britannian == 30 and market.reputation.valois == 30, "Three anti-pirate contracts must earn naval licences")
	check(not scene.mission.claim(market) and market.reputation.valois == 30, "Same completed contract may not award twice")
	var loaded := LandingMarketState.new()
	loaded.save_path = market.save_path
	check(loaded.load_state() and loaded.ship_class == "longbow" and loaded.reputation.valois == 30, "Faction hull and earned standing must persist")
	var good_path: String = market.save_path
	market.save_path = "user://missing_carrier_folder/save.json"
	scene.mission.phase = "return"
	var before: int = market.credits
	check(not scene.mission.claim(market) and market.credits == before and market.reputation.valois == 30, "Failed contract save must roll back credits and reputation")
	market.save_path = good_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(good_path))
	print("CARRIERS AND PATROL RESPONSE: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
