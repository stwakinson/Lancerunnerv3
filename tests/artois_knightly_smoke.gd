extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var scene: Control = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	var world: ArtoisSpace = scene.space_world
	var combat := world.combat
	var power := combat.defence
	var selected := world.selected_id
	await key(KEY_TAB, true)
	check(scene._boost_held() and world.selected_id == selected, "Tab must hold afterburner without cycling targets")
	await key(KEY_TAB, false)
	await key(KEY_T, true)
	await key(KEY_T, false)
	check(world.selected_id != selected, "T must cycle targets")
	world.engage_cruise()
	await key(KEY_S, true)
	await key(KEY_S, false)
	check(world.cruise_spool == 0, "Physical S must cancel spool immediately")
	world.ship.position = Vector3(0, 1800, 0)
	world.engage_cruise()
	check(not world.cruise and world.cruise_spool > 0, "Cruise must spool before engaging")
	combat.fire()
	check(world.shots.is_empty(), "Spooling must inhibit guns")
	world.advance(0.5, Vector2.ZERO, 0, false, false)
	check(power._particles[0].emitting, "Spooling must emit engine particles")
	world.advance(0.1, Vector2.ZERO, -1, false, false)
	check(not world.cruise and world.cruise_spool == 0, "S/reverse must cancel spool")
	world.engage_cruise()
	for i in 120: world.advance(1.0 / 60, Vector2.ZERO, 0, false, false)
	check(world.cruise and not power._particles[0].emitting, "Cruise must engage after 1.8 seconds")
	var before := world.ship.rotation.y
	world.orbit(Vector2(100, 0))
	var cruise_turn := absf(world.ship.rotation.y - before)
	world.cancel_cruise()
	before = world.ship.rotation.y
	world.orbit(Vector2(100, 0))
	check(absf(world.ship.rotation.y - before) > cruise_turn * 5, "Cruise steering must be substantially slower")
	world.brake()
	world.ship.rotation = Vector3.ZERO
	combat.repair()
	combat.fire()
	check(is_equal_approx(power.energy, 88) and world.shots.size() == 1, "Successful pulse must spend 12 energy")
	check((world.shots[0].get_meta("velocity") as Vector3).length() < 140 and float(world.shots[0].get_meta("damage")) == 48, "Pulse rounds must be slower and harder hitting")
	combat.fire()
	check(is_equal_approx(power.energy, 88), "Cooldown must not spend energy")
	combat.clear_projectiles()
	combat.repair()
	for i in 50: world.advance(0.1, Vector2.ZERO, 1, true, false)
	check(power.energy < 30 and world.speed < 105, "Held afterburner must exhaust power and fall back to normal speed")
	world.advance(0.1, Vector2.ZERO, 0, false, false)
	for i in 50: world.advance(0.1, Vector2.ZERO, 0, false, false)
	check(power.energy > 80, "Energy must recover after spending stops")
	world.brake()
	combat.repair()
	combat.guard_requested = true
	world.advance(0.1, Vector2.ZERO, 0, false, false)
	check(power.guard_active and power._guard.visible, "Held guard must raise visible knight shield")
	var front := world.ship.global_position - world.ship.global_basis.z * 20
	combat.damage_player(40, -1, front)
	check(is_equal_approx(combat.shield, 58) and power.energy < 82, "Frontal block must stop 95 percent and spend impact energy")
	combat.damage_player(40, -1, world.ship.global_position + world.ship.global_basis.z * 20)
	check(is_equal_approx(combat.shield, 18), "Rear shots must bypass directional guard")
	combat.guard_requested = false
	world.advance(0.01, Vector2.ZERO, 0, false, false)
	combat.shield = 0
	combat.damage_player(100)
	check(power.armour == 0 and combat.hull == 100, "Armour must absorb 80 before hull takes the overflow")
	combat.repair()
	power.energy = 2
	power.guard_active = true
	combat.shield = 0
	combat.damage_player(100, -1, front)
	check(not power.guard_active and combat.hull < 120, "Tiny energy reserve must not provide a free full block")
	combat.repair()
	world.engage_cruise()
	combat.guard_requested = true
	world.advance(0.1, Vector2.ZERO, 0, false, false)
	check(not power.guard_active, "Transit must prevent raising the guard")
	world.apply_disruption(6)
	check(world.cruise_spool == 0, "Disruption must cancel pending cruise")
	var scanner = load("res://scripts/artois/artois_scanner.gd")
	var ahead: Vector3 = scanner.project(world.ship, world.ship.global_position - world.ship.global_basis.z * 100)
	check(ahead.z < -99 and absf(ahead.x) < 0.1, "Scanner ahead must remain up after ship rotation")
	# A swept hostile projectile hits a stationary ship; the existing dodge can evade it.
	for dodging in [false, true]:
		world.disruption_remaining = 0
		world.ship.position = Vector3(0, 1800, 0)
		world.ship.rotation = Vector3.ZERO
		world.brake()
		combat.repair()
		combat.guard_requested = false
		combat.clear_projectiles()
		var shot := combat._projectile(world.ship.position + Vector3(0, 0, -55), Vector3(0, 0, 110), 26, "ff7059", 2)
		combat.hostile_shots.append(shot)
		if dodging:
			world.dodge_cooldown = 0
			world.tap_direction(KEY_A, 10)
			world.tap_direction(KEY_A, 10.1)
		for i in 40: world.advance(1.0 / 60, Vector2.ZERO, 0, false, false)
		check(combat.shield == 60 if dodging else combat.shield < 60, "Dodge must change the outcome of an incoming projectile")
	combat.repair()
	combat.ordnance.message_time = 0
	world.prepare_launch()
	await mouse(MOUSE_BUTTON_RIGHT, true)
	scene._process(0.1)
	check(power.guard_active, "Physical RMB must raise guard")
	scene.toggle_chart()
	var reserve := power.energy
	scene._process(0.5)
	check(not power.guard_active and power.energy == reserve, "Chart must pause energy spending and lower guard")
	scene.toggle_chart()
	await mouse(MOUSE_BUTTON_RIGHT, false)
	combat.guard_requested = true
	world.advance(0.1, Vector2.ZERO, 0, false, false)
	scene.target_hud.queue_redraw()
	await process_frame
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): await scene._capture(arg.trim_prefix("--capture-dir="), "artois-knight-shield.png")
	combat.guard_requested = false
	world.engage_cruise()
	world.advance(0.5, Vector2.ZERO, 0, false, false)
	scene.target_hud.queue_redraw()
	await process_frame
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): await scene._capture(arg.trim_prefix("--capture-dir="), "artois-cruise-spool.png")
	print("KNIGHTLY COMBAT: %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = root.size * 0.5
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
