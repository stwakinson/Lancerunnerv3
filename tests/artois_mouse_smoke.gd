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
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	var world: Node3D = scene.space_world
	world.ship.position = Vector3(0, 1800, 0)
	world.brake()
	for i in 10: world.advance(0.1, Vector2.ZERO, 0, false, false)
	check(not world.ship.engines[0].visible and world._effects._samples[0].is_empty(), "Stationary ship must stop emitting exhaust")
	for i in 15: world.advance(0.1, Vector2.ZERO, 1, false, false)
	check(world.ship.engines[0].visible and not world._effects._samples[0].is_empty(), "Moving ship must emit speed-dependent trails")
	world.brake()
	await mouse(MOUSE_BUTTON_LEFT, true)
	check(scene._fire_held(), "LMB must request guns in default flight mode")
	scene._process(0.01)
	check(not world.shots.is_empty(), "Physical LMB must produce a projectile")
	await mouse(MOUSE_BUTTON_LEFT, false)
	await key(KEY_ENTER)
	check(scene.free_mouse and not scene.landed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Enter must free cursor without docking")
	world.camera.position = world.target_position("asques_gate") + Vector3(0, 0, 180)
	world.camera.look_at(world.target_position("asques_gate"))
	await mouse(MOUSE_BUTTON_LEFT, true)
	check(world.selected_id == "asques_gate", "Free-cursor click must select the object under the pointer")
	check(not scene._fire_held(), "Free-cursor clicks must not fire")
	await mouse(MOUSE_BUTTON_LEFT, false)
	await key(KEY_ENTER)
	check(not scene.free_mouse, "Enter must return to flight")
	await mouse(MOUSE_BUTTON_RIGHT, true)
	scene._process(0.01)
	check(world.combat.defence.guard_active, "RMB must raise shield")
	await mouse(MOUSE_BUTTON_RIGHT, false)
	var defence: RefCounted = world.combat.defence
	world.ship.rotation = Vector3.ZERO
	defence.guard_direction = Vector3.RIGHT
	defence.guard_active = true
	defence.energy = 100
	var residual: float = defence.block(40, world.ship.global_position + Vector3.RIGHT * 50, world.ship)
	check(is_equal_approx(residual, 2), "Shield must block in aim direction, independently of nose")
	check(defence.block(40, world.ship.global_position + Vector3.FORWARD * 50, world.ship) == 40, "Nose direction must not block when aiming sideways")
	world.combat.ordnance.set_cursor(Vector2(scene.space_view.size) * Vector2(0.9, 0.5))
	world.advance(0.01, Vector2.ZERO, 0, false, false)
	check(defence.guard_direction.dot(world.combat.ordnance.pointer_direction) > 0.999, "Live shield direction must follow pointer ray")
	await key(KEY_ESCAPE)
	check(scene.pause_menu.visible and current_scene == scene, "Escape must open in-game menu")
	var position: Vector3 = world.ship.position
	var elapsed: float = world.traffic.elapsed
	var energy: float = defence.energy
	scene._process(1)
	check(world.ship.position == position and world.traffic.elapsed == elapsed and defence.energy == energy, "Pause must freeze player, NPCs and energy")
	await key(KEY_ESCAPE)
	check(not scene.pause_menu.visible, "Escape in pause menu must resume")
	var actor: Dictionary
	for candidate in world.traffic.actors.values():
		if not candidate.hostile:
			actor = candidate
			break
	actor.node.visible = true
	actor.node.position = world.ship.position + Vector3(0, 0, -100)
	actor.state = "FLEEING"
	actor.threat = "player"
	actor.timer = 7
	actor.velocity = Vector3.ZERO
	actor.cruise_charge = 0
	actor.cruise = false
	world.traffic._civilian_step(actor, 0.1)
	check(not actor.cruise and (actor.velocity as Vector3).length() <= 35, "Attacked civilian must not instantly cruise")
	for i in 20: world.traffic._civilian_step(actor, 0.1)
	check(actor.cruise and (actor.velocity as Vector3).length() > 35 and (actor.velocity as Vector3).length() <= 175, "Civilian must spool then accelerate within player cruise cap")
	actor.disruption = 6
	world.traffic._civilian_step(actor, 0.1)
	check(not actor.cruise and actor.cruise_charge == 0 and (actor.velocity as Vector3).length() <= 12, "Disruption must cancel NPC cruise and spool")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			world.prepare_launch()
			world.combat.repair()
			world.combat.ordnance.set_cursor(Vector2(scene.space_view.size) * Vector2(0.7, 0.45))
			world.combat.guard_requested = true
			world.advance(0.1, Vector2.ZERO, 0, false, false)
			scene.target_hud.queue_redraw()
			await scene._capture(arg.trim_prefix("--capture-dir="), "artois-mouse-shield.png")
			scene._menu()
			await scene._capture(arg.trim_prefix("--capture-dir="), "artois-pause-menu.png")
	if not scene.pause_menu.visible: scene._menu()
	var quit_button: Button = scene.pause_menu.get_child(0).get_child(2)
	await click(quit_button)
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://scenes/menu.tscn", "Only explicit quit menu action must return to main menu")
	print("MOUSE FLIGHT: %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)
func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = root.get_final_transform() * (current_scene.get_global_transform_with_canvas() * (current_scene.size * 0.5))
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
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
