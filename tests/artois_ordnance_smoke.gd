extends SceneTree
var failures := 0
var scene: Control
var world: ArtoisSpace
var combat: ArtoisCombat
var arms: ArtoisOrdnance
var market: LandingMarketState
var capture_dir := ""


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
	arms = combat.ordnance
	market = LandingMarketState.new()
	market.save_path = "user://ordnance_smoke_%d.json" % OS.get_process_id()
	scene.market_state = market
	scene.shop_panel.configure(market)
	scene.contract_panel.market = market
	market.weapons = ["pulse_laser", "missile_rack"]
	for id in ["pavise_missile", "bodkin_missile", "fetter_missile", "armourer_mites", "ward_phial"]:
		check(market.trade(id, 3, true).is_empty(), "Supply must be purchasable: " + id)
		check(not market.fit_error(id).is_empty(), "Supplies must not occupy a fitted slot")
	check(market.cargo_used() == 4, "Supplies must use dedicated bins, not commodity hold space")
	combat.configure(world, market)
	world.ship.position = Vector3(0, 1000, 0)
	world.ship.rotation = Vector3.ZERO
	world.brake()
	world.reset_view()

	# Cursor aiming follows the view ray, with a hard forward cone.
	var forward := -world.ship.basis.z
	var aim := world.ship.position + forward * 200 + world.ship.basis.x * 55
	arms.set_cursor(world.camera.unproject_position(aim))
	combat.fire()
	check(world.shots.size() == 1, "Primary fire must exclude missile racks")
	var velocity: Vector3 = world.shots[0].get_meta("velocity")
	check(velocity.normalized().dot(world.ship.position.direction_to(aim)) > 0.999, "Gun must fire toward the cursor's world point")
	combat.clear_projectiles()
	combat.repair()
	arms.set_cursor(Vector2(9000, 180))
	combat.fire()
	velocity = world.shots[0].get_meta("velocity")
	check(forward.angle_to(velocity.normalized()) <= arms.ARC + 0.00001 and arms.aim_clamped, "Extreme cursor positions must never fire sideways")
	combat.clear_projectiles()
	combat.repair()

	# Test lock acquisition, loss and atomic ammo consumption.
	scene.mission.accept()
	var target := combat.enemy("patrol_3")
	world.ship.position = target.position + Vector3(0, 0, 170)
	world.select_target("patrol_3")
	world.align_to_target()
	world.reset_view()
	arms.set_cursor(world.camera.unproject_position(target.position))
	check(not arms.launch() and market.owned("pavise_missile") == 3, "Missiles must not launch or consume ammo before lock")
	arms.advance(0.75)
	check(arms.lock_progress > 0 and arms.lock_progress < arms.LOCK_TIME, "Lock must take time")
	world.select_target("patrol_2")
	check(arms.lock_progress == 0, "Changing target must immediately reset lock")
	world.select_target("patrol_3")
	world.align_to_target()
	arms.advance(1.0)
	world.ship.rotate_y(PI / 2)
	arms.advance(0.1)
	check(arms.lock_progress == 0, "Turning outside the seeker cone must lose lock")
	world.align_to_target()
	arms.advance(1.6)
	check(arms.lock_progress == arms.LOCK_TIME and arms.launch(), "A completed valid lock must launch a missile")
	check(market.owned("pavise_missile") == 2 and world.shots.size() == 1, "Launch must spend exactly one round")
	check(not arms.launch() and market.owned("pavise_missile") == 2, "Launcher cooldown must prevent duplicate consumption")
	for i in 90: combat.advance(1.0 / 60.0)
	check(float(target.get_meta("shield")) == 0 and float(target.get_meta("hull")) < 65, "Pavise must strike a moving target and strip shields")
	combat.clear_projectiles()
	world.ship.position = target.position + Vector3(0, 0, 800)
	world.align_to_target()
	arms.advance(2)
	check(arms.lock_progress == 0, "Out-of-range targets must not lock")

	# Damage specialisation, including actual cruise cancellation and speed cap.
	target.set_meta("shield", 100.0)
	target.set_meta("hull", 200.0)
	combat.apply_missile_to_enemy("patrol_3", "pavise_missile")
	check(float(target.get_meta("shield")) == 10 and float(target.get_meta("hull")) == 200, "Pavise must specialise in shields")
	target.set_meta("shield", 0.0)
	combat.apply_missile_to_enemy("patrol_3", "bodkin_missile")
	check(float(target.get_meta("hull")) == 120, "Bodkin must specialise in exposed hull")
	target.set_meta("cruise", true)
	target.set_meta("velocity", Vector3.FORWARD * 130)
	combat.apply_missile_to_enemy("patrol_3", "fetter_missile")
	check(not target.get_meta("cruise") and float(target.get_meta("disruption")) == 6, "Fetter must cancel enemy cruise")
	check((target.get_meta("velocity") as Vector3).length() <= 12, "Fetter must immediately cut enemy speed")
	world.engage_cruise()
	world.velocity = Vector3.FORWARD * 175
	combat.apply_missile_to_player("fetter_missile")
	world.engage_cruise()
	check(not world.cruise and world.disruption_remaining > 0 and world.velocity.length() <= 12, "Fetter must cancel player cruise and prevent reactivation")
	world.advance(0.1, Vector2.ONE, 1.0, true, false)
	check(world.speed <= 12.001, "Boosting must not bypass a disruption speed cap")
	combat.clear_encounter()
	world.advance(6.1, Vector2.ZERO, 0, false, false)
	world.engage_cruise()
	check(world.cruise and world.disruption_remaining == 0, "Cruise must recover after the disruption expires")
	world.brake()

	# Repair supplies restore appropriate health without wasting stock at full health.
	combat.repair()
	check(not arms.use_recovery("armourer_mites") and market.owned("armourer_mites") == 3, "Full hull must not consume mites")
	combat.hull = 30
	check(arms.use_recovery("armourer_mites") and combat.hull == 90 and market.owned("armourer_mites") == 2, "Mites must restore sixty hull and consume one")
	combat.shield = 0
	check(not arms.use_recovery("ward_phial") and market.owned("ward_phial") == 3, "Recovery supplies must share a cooldown")
	arms.advance(3.1)
	check(arms.use_recovery("ward_phial") and combat.shield == combat.shield_max and market.owned("ward_phial") == 2, "Phial must restore shields, capped at capacity")
	var loaded := LandingMarketState.new()
	loaded.save_path = market.save_path
	check(loaded.load_state() and loaded.owned("pavise_missile") == 2 and loaded.owned("armourer_mites") == 2 and loaded.owned("ward_phial") == 2, "Ammo and recovery consumption must persist")
	var path := market.save_path
	market.save_path = "user://nonexistent-ordnance-folder/save.json"
	var count := market.owned("bodkin_missile")
	check(not market.consume("bodkin_missile").is_empty() and market.owned("bodkin_missile") == count, "Save failure must not consume stock")
	market.save_path = path

	# A legacy ten-item save must load without resetting credits/equipment.
	market.save_state()
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for id in market.ITEMS:
		if id not in market.LEGACY_IDS: legacy.stock.erase(id)
	legacy.locker = {}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	loaded = LandingMarketState.new()
	loaded.save_path = path
	check(loaded.load_state() and loaded.credits == market.credits and loaded.weapons == market.weapons and loaded.stock.has("fetter_missile"), "Legacy saves must gain dealer supply stock without losing player state")

	# Real shop and cursor events in the rendered run.
	world.ship.position = world.target_position(world.DOCK_ID) + Vector3(0, 0, 60)
	world.brake()
	await scene.toggle_docking()
	scene.open_shop("equipment")
	select_supply("ward_phial")
	check(not scene.shop_panel._fit.visible, "Consumables must not show a fit action")
	var before := market.owned("ward_phial")
	if DisplayServer.get_name() != "headless": await click(scene.shop_panel._buy)
	else: scene.shop_panel._trade(true)
	check(market.owned("ward_phial") == before + 1, "Shop button must purchase consumables")
	await scene._capture(capture_dir, "artois-consumables-shop.png")
	scene.shop_panel.close_shop()
	await scene.toggle_docking()
	scene.mission.fail()
	scene.mission.accept()
	target = combat.enemy("patrol_3")
	world.ship.position = target.position + Vector3(0, 0, 170)
	world.select_target("patrol_3")
	world.align_to_target()
	world.reset_view()
	arms.cursor_enabled = false
	arms.reset_lock()
	arms.missile_cooldown = 0
	arms.selected_missile = "bodkin_missile"
	for i in 16: arms.advance(0.1)
	if DisplayServer.get_name() != "headless":
		var view: Vector2 = scene.size
		var factor := maxf(view.x / scene.space_view.size.x, view.y / scene.space_view.size.y)
		var local: Vector2 = world.camera.unproject_position(target.position) * factor + (view - Vector2(scene.space_view.size) * factor) * 0.5
		Input.warp_mouse(local)
		await process_frame
		var motion := InputEventMouseMotion.new()
		motion.position = root.get_final_transform() * local
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await process_frame
		check(arms.cursor_enabled, "Real mouse motion must activate cursor aim")
		scene.toggle_pixels()
		scene._process(0)
		check(not arms.aim_clamped and arms.aim_direction.dot(world.ship.position.direction_to(target.position)) > 0.995, "Cursor must aim at the target in native mode")
		scene.toggle_pixels()
	# Draw an acquired lock and inventory HUD, without advancing enemy simulation.
	scene._process(0)
	await process_frame
	await process_frame
	await scene._capture(capture_dir, "artois-missile-lock.png")
	var rounds := market.owned("bodkin_missile")
	await key(KEY_F)
	check(world.shots.size() == 1 and market.owned("bodkin_missile") == rounds - 1, "F must launch the selected missile through real key input")
	await key(KEY_Z)
	check(arms.selected_missile == "fetter_missile" and arms.lock_progress == 0, "Z must cycle ammunition and reacquire lock")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures == 0: print("PASS: cursor arc, missile lock/ammunition/profiles, disruption, recovery supplies, shop and legacy saves")
	quit(0 if failures == 0 else 1)


func select_supply(id: String) -> void:
	scene.shop_panel.selected_id = id
	scene.shop_panel._refresh()


func click(control: Control) -> void:
	var at := root.get_final_transform() * (control.get_global_transform_with_canvas() * (control.size * 0.5))
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


func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
