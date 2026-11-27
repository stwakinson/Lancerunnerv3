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
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	while root.get_node("SceneFader").busy: await process_frame
	var world: Node3D = scene.space_world
	var combat: Node3D = world.combat
	var market := LandingMarketState.new()
	market.save_path = "user://effects_smoke_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	combat.configure(world, market)
	check(is_equal_approx(float(market.Ships.profile("fighter").turn), 1.6 * 1.25), "Warden turns 25 percent faster")
	combat.fire()
	check(world.shots.size() == 1 and is_equal_approx((world.shots[0].get_meta("velocity") as Vector3).length(), 187.5), "Lance bolt must travel 50 percent faster at rest")
	combat.clear_projectiles()
	var fx: Node3D = combat.effects
	combat.damage_player(5, -1, world.ship.position + Vector3.FORWARD * 20)
	check(fx.bursts.back().kind == "shield", "Player ward hits produce blue impact")
	combat.shield = 0
	combat.damage_player(5, -1, world.ship.position + Vector3.RIGHT * 20)
	check(fx.bursts.back().kind == "hull", "Player hull hits produce warm sparks")
	combat.spawn_patrol(world.ship.position + Vector3(0, 0, -70))
	var target: Node3D = combat.enemies[0]
	combat.apply_missile_to_enemy(str(target.get_meta("id")), "pavise_missile")
	check(fx.bursts.any(func(burst: Dictionary) -> bool: return burst.kind == "ward_missile"), "Anti-ward missile has a blue detonation")
	combat.damage_enemy(str(target.get_meta("id")), 10000)
	check(fx.bursts.back().kind == "destruction", "Quest enemy death produces destruction burst")
	var local: Dictionary = world.traffic.actors.values()[0]
	local.node.show()
	world.traffic.damage(local.id, 100000, 100000)
	check(not local.alive and fx.bursts.back().kind == "destruction", "Ambient ship death shares explosion and normal death logic")
	for i in 50: combat._explosion(world.ship.position + Vector3(0, 0, -70))
	check(fx.bursts.size() == fx.LIMIT, "Explosion spam must remain bounded")
	fx.advance(4.0)
	await process_frame
	check(fx.bursts.is_empty() and fx.get_child_count() == 0, "All effect nodes expire without leaks")
	combat.clear_encounter()
	world.ship.position = world.target_position("planet_dock") + Vector3(0, 0, 65)
	world.select_target("planet_dock")
	world.brake()
	await scene.toggle_docking()
	combat._explosion(world.ship.position)
	scene._process(4)
	check(fx.bursts.is_empty(), "Offscreen effects still expire while docked")
	await scene.toggle_docking()
	if not capture_dir.is_empty():
		world.ship.position = world.target_position("planet_dock") + Vector3(0, 100, 300)
		var centre: Vector3 = world.ship.position + Vector3(0, 0, -65)
		world.camera.position = centre + Vector3(0, 12, 52)
		world.camera.look_at(centre, Vector3.UP)
		world.camera.far = 1200
		combat._explosion(centre, 8.0, Vector3(2, 0, 0))
		combat.missile_effect(centre + Vector3(-16, 0, 0), "pavise_missile")
		fx.advance(0.12)
		await scene._capture(capture_dir, "artois-combat-explosions.png")
		fx.advance(0.45)
		await scene._capture(capture_dir, "artois-combat-debris.png")
	print("COMBAT EFFECTS: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
