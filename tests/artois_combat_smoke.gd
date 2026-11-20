extends SceneTree

var failures := 0
var capture_dir := ""
var scene: Control
var world: ArtoisSpace
var combat: ArtoisCombat


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	scene = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	world = scene.space_world
	combat = world.combat
	# Isolate all economy writes from the player's saved game.
	var market := LandingMarketState.new()
	market.save_path = "user://artois_combat_smoke_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	combat.configure(world, market)

	# Physical taps, key repeat and independent local-space directions.
	await key(KEY_A, true)
	await key(KEY_A, true, true)
	check(world.dodge_velocity == Vector3.ZERO, "Key repeat must not count as a second tap")
	await key(KEY_A, false)
	await key(KEY_A, true)
	await key(KEY_A, false)
	check(world.dodge_velocity.x < -100, "AA must dodge left through actual input")
	var before := world.ship.position
	world.advance(0.2, Vector2.ZERO, 0, false, false)
	check(world.ship.position.x < before.x - 10, "Dodge must move the ship rather than just change a flag")
	check(not world.tap_direction(KEY_D, 10) and not world.tap_direction(KEY_D, 10.1), "Cooldown must prevent a second burst")
	for pair in [[KEY_A, Vector3.LEFT], [KEY_D, Vector3.RIGHT], [KEY_W, Vector3.FORWARD], [KEY_S, Vector3.BACK], [KEY_Q, Vector3.DOWN], [KEY_E, Vector3.UP]]:
		world.brake()
		world.dodge_cooldown = 0
		world.ship.rotation = Vector3(0.2, 1.1, 0)
		check(not world.tap_direction(pair[0], 20), "First tap must not dodge")
		check(world.tap_direction(pair[0], 20.15), "Second tap must dodge on every axis")
		check(world.dodge_velocity.normalized().dot(world.ship.basis * pair[1]) > 0.99, "Dodge must use the ship's local axes")
	world.prepare_launch()
	world.tap_direction(KEY_A, 30)
	world.tap_direction(KEY_A, 30.5)
	check(world.dodge_velocity == Vector3.ZERO, "Slow taps must not dodge")

	# Equipment must affect firing, shields and visible hardpoints.
	market.weapons = ["", ""]
	combat.configure(world, market)
	world._fire_shot()
	check(world.shots.is_empty() and combat._mounts.get_child_count() == 0, "Empty hardpoints must not fire")
	market.weapons = ["pulse_laser", ""]
	check(market.trade("autocannon", 1, true).is_empty() and market.fit("autocannon").is_empty(), "Outfitter must fit a second gun")
	check(market.trade("shield", 1, true).is_empty() and market.fit("shield").is_empty(), "Outfitter must fit Aegis")
	combat.configure(world, market)
	check(combat.shield_max == 180 and combat._mounts.get_child_count() == 2, "Fitting must update shield capacity and hardpoints")
	world._fire_shot()
	check(world.shots.size() == 2, "Both fitted guns must fire")
	combat.clear_projectiles()
	combat.damage_player(200)
	check(combat.shield == 0 and combat.hull == 100, "Shields must absorb damage before hull")
	combat.advance(2)
	check(combat.shield == 0, "Shield recharge must wait after damage")
	combat.advance(2.1)
	check(combat.shield > 0 and combat.hull == 100, "Aegis must regenerate shields, not hull")
	combat.repair()
	world.engage_cruise()
	world._fire_shot()
	check(world.shots.is_empty(), "Cruise must lock both fitted guns")
	world.brake()

	# Dock and use the planet contact. Rendered runs click the actual buttons.
	world.ship.position = world.target_position(world.DOCK_ID) + Vector3(0, 0, 60)
	await scene.toggle_docking()
	check(scene.landed and scene.contact_button.visible, "Contact must be available only on the planet")
	await scene._capture(capture_dir, "artois-contact.png")
	if DisplayServer.get_name() != "headless": await click(scene.contact_hotspot)
	else: scene.open_contract()
	check(scene.contract_panel.visible, "Planet contact must open a conversation")
	await scene.toggle_docking()
	check(scene.landed, "Conversation must block launch")
	if DisplayServer.get_name() != "headless": await click(scene.contract_panel.get_node("ContractAction"))
	else: scene.contract_panel._act()
	check(scene.mission.phase == "active" and combat.enemies.size() == 5, "Accept must spawn exactly five enemies")
	check(not scene.mission.accept() and combat.enemies.size() == 5, "Repeated acceptance must not duplicate the encounter")
	await scene._capture(capture_dir, "artois-contract.png")
	scene.contract_panel.close_panel()
	await scene.toggle_docking()
	check(not scene.landed and world.selected_id == scene.mission.TARGET_ID, "Launch must preserve the mission destination")
	scene.toggle_chart()
	check(scene.chart._picker.item_count == 39, "Mission waypoint must appear in the chart")
	scene.toggle_chart()
	world.brake()
	world.tap_direction(KEY_A, 100)
	scene.toggle_chart()
	await key(KEY_A, true)
	await key(KEY_A, false)
	await key(KEY_A, true)
	await key(KEY_A, false)
	check(world.dodge_velocity == Vector3.ZERO, "Chart input must never dodge the ship")
	scene.toggle_chart()
	check(not world.tap_direction(KEY_A, 100.1), "Opening chart must clear earlier taps")
	world.reset_taps()
	var site: Vector3 = world.layout.world(scene.mission.SITE)
	world.advance(0.1, Vector2.ZERO, 0, false, false)
	for fighter in combat.enemies: check(not fighter.get_meta("active"), "Patrol must wait while the player is far away")
	world.ship.position = site + Vector3(0, 0, 120)
	world.brake()
	for i in 35: world.advance(0.1, Vector2.ZERO, 0, false, false)
	for fighter in combat.enemies: check(fighter.get_meta("active"), "Nearby enemies must activate")
	check(combat.shield < combat.shield_max or not combat.hostile_shots.is_empty(), "Activated patrol must fire real hostile projectiles")
	world.select_target("patrol_3")
	world.navigate_to("patrol_3")
	check(world.autopilot, "Navigation must accept a live hostile target")
	world.brake()
	world.align_to_target()
	world.reset_view()
	check(world.target_entry().kind == "hostile", "Hostiles must be valid selectable targets")
	check(scene.Picking.pick(world, world.camera.unproject_position(combat.enemy("patrol_3").position)).begins_with("patrol_"), "Click picking must include hostile ships")
	scene._process(0.0)
	await process_frame
	await process_frame
	await scene._capture(capture_dir, "artois-patrol.png")

	# Fight the actual moving ships using equipped projectiles, not direct kills.
	# Repair between isolated engagements so this is a deterministic hit test.
	for id in ["patrol_1", "patrol_2", "patrol_3", "patrol_4", "patrol_5"]:
		world.select_target(id)
		for frame in 240:
			if combat.enemy(id) == null: break
			world.align_to_target()
			world.advance(1.0 / 30.0, Vector2.ZERO, 0, false, true)
		check(combat.enemy(id) == null, "Equipped projectiles must destroy " + id)
		combat.repair()
	check(scene.mission.kills == 5 and scene.mission.phase == "return", "Exactly five kills must complete the objective")
	check(combat.enemies.is_empty() and world.selected_id == world.DOCK_ID, "Final kill must track the return port")
	world.ship.position = world.target_position(world.DOCK_ID) + Vector3(0, 0, 60)
	world.brake()
	await scene.toggle_docking()
	scene.open_contract()
	var credits := market.credits
	scene.contract_panel._act()
	check(market.credits == credits + 1500 and scene.mission.phase == "paid", "Returning to contact must pay the reward")
	check(not scene.mission.claim(market) and market.credits == credits + 1500, "Reward must not pay twice")
	var loaded := LandingMarketState.new()
	loaded.save_path = market.save_path
	check(loaded.load_state() and loaded.credits == market.credits, "Reward and equipment must persist through the economy save")

	# Missile guidance and loss/retry recovery.
	scene.contract_panel._act()
	check(scene.mission.phase == "active" and combat.enemies.size() == 5 and scene.mission.kills == 0, "Paid contract must be explicitly repeatable")
	scene.contract_panel.close_panel()
	market.weapons = ["missile_rack", ""]
	await scene.toggle_docking()
	combat.configure(world, market)
	world.ship.position = site + Vector3(0, 0, 90)
	world.select_target("patrol_3")
	world.align_to_target()
	world._fire_shot()
	check(world.shots.size() == 1 and world.shots[0].get_meta("target") == "patrol_3", "Missile rack must launch with selected hostile guidance")
	for i in 90: world.advance(1.0 / 60.0, Vector2.ZERO, 0, false, false)
	check(combat.enemy("patrol_3") == null or float(combat.enemy("patrol_3").get_meta("hull")) < 65, "Guided missile must damage its moving target")
	combat.damage_player(9999)
	for i in 120:
		await process_frame
		if scene.landed and not scene.transitioning: break
	if not scene.landed or scene.transitioning: await create_timer(1.0).timeout
	check(scene.landed and not combat.dead and combat.hull == combat.HULL_MAX, "Defeat must recover the player to the repaired planet hub")
	check(scene.mission.phase == "failed" and combat.enemies.is_empty(), "Defeat must fail and clear the encounter")
	scene.open_contract()
	scene.contract_panel._act()
	check(scene.mission.phase == "active" and combat.enemies.size() == 5 and scene.mission.kills == 0, "Failed mission must restart cleanly from the contact")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(market.save_path))
	if failures == 0: print("PASS: double-tap dodge, fitted combat, shields, patrol activation, projectile kills, quest UI, reward, missile guidance and defeat/retry")
	quit(0 if failures == 0 else 1)


func key(code: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame


func click(control: Control) -> void:
	var at := root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
