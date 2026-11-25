extends SceneTree
var failures := 0
var scene: Control
var world: ArtoisSpace
var highway: ArtoisHighways
var capture_dir := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func place(gate_id: String, offset := Vector3.ZERO, distance := 8.0) -> void:
	highway.reset()
	highway.lockout = 0
	world.brake()
	world.combat.clear_projectiles()
	world._effects.clear_trails()
	var gate: Dictionary = highway.gates[gate_id]
	world.ship.position = gate.position - gate.axis * distance + offset
	world.ship.basis = Basis.looking_at(gate.axis, Vector3.UP)
	world._sync_angles()
	world.velocity = gate.axis * world.NORMAL_SPEED
	world.reset_view()


func enter(gate_id: String, offset := Vector3.ZERO) -> void:
	place(gate_id, offset)
	world.advance(0.3, Vector2.ZERO, 1.0, false, false)
	check(highway.attached(), "Crossing must capture " + gate_id)


func _run() -> void:
	scene = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	world = scene.space_world
	highway = world.highways
	check(highway.routes.size() == 9 and highway.gates.size() == 36, "Map must contain nine routes with thirty-six directional rings")
	for id in highway.gates:
		check(world.landmarks.has(id), "Highway gate must have selectable geometry")
		check(world.layout.world(world.layout.target(id)).is_equal_approx(highway.gates[id].position), "Chart and gate coordinates must agree")

	# Traverse every segment in both directions through real swept gate entry.
	for lane in world.layout.highways:
		for endpoint in ["a", "b"]:
			var id: String = "highway_" + str(lane.id) + "_" + endpoint
			enter(id)
			var axis := highway.direction()
			var target: Vector3 = world.target_position()
			var peak := 0.0
			# Allow the full route at cruise speed, plus entry/exit acceleration.
			var route: Dictionary = highway.routes[highway.gates[id].route]
			var travel_frames := ceili((float(route.length) / highway.SPEED + 10.0) / 0.1)
			for frame in travel_frames:
				if not highway.attached(): break
				world.advance(0.1, Vector2.ZERO, 0.0, false, false)
				if highway.attached(): peak = maxf(peak, world.velocity.dot(axis))
			check(not highway.attached(), "Route must exit automatically in either direction: " + id)
			check(peak > world.NORMAL_SPEED and peak <= world.NORMAL_SPEED * 10.0 + 1, "Transit must accelerate within ten-times speed cap: " + id)
			check(world.ship.position.distance_to(target) < 12, "Arrival must cross its exit without teleporting")
			check(world.velocity.dot(axis) > world.NORMAL_SPEED, "Arrival must retain coasting momentum")
			world.advance(0.1, Vector2.ZERO, 0.0, false, false)
			check(not highway.attached(), "Exit gate must not immediately recapture the ship")

	var id := "highway_caulers_junction_a"
	var axis: Vector3 = highway.gates[id].axis
	# No magnetic capture simply for being near the middle of the filament.
	place(id, Vector3.UP * 28)
	world.advance(0.3, Vector2.ZERO, 1.0, false, false)
	check(not highway.attached(), "Missing the ring must not capture")
	place(id)
	world.ship.position += axis * 120
	world.advance(0.3, Vector2.ZERO, 1.0, false, false)
	check(not highway.attached(), "Crossing the middle of a filament must not capture")
	place(id, Vector3.ZERO, 45)
	world.cruise = true
	world.velocity = axis * world.CRUISE_SPEED
	world.advance(0.5, Vector2.ZERO, 1.0, false, false)
	check(highway.attached() and not world.cruise, "Fast cruise entry must use a swept gate test and cancel cruise")

	enter(id, Vector3.UP * 14)
	var gate: Dictionary = highway.gates[id]
	var before := world.ship.position.distance_to(gate.position + axis * (world.ship.position - gate.position).dot(axis))
	for frame in 10: world.advance(0.1, Vector2.ZERO, 0.0, false, false)
	check(absf(world.ship.position.y - gate.position.y) < before * 0.4, "Magnetism must draw an off-centre ship onto its directional filament")
	for frame in 5: world.advance(0.1, Vector2(1, 1), 0.0, false, true)
	var centre: Vector3 = gate.position + axis * (world.ship.position - gate.position).dot(axis)
	check(world.ship.position.distance_to(centre) < 8, "Normal steering must be resisted by the magnetic spring")
	check(world.shots.is_empty(), "Weapons must be locked during filament travel")
	world.brake()
	world.toggle_cruise()
	check(highway.attached() and not world.cruise, "Normal brake/cruise controls must not defeat magnetism")

	# Chart pauses transit and absorbs breakout input.
	scene.toggle_chart()
	var paused: Vector3 = world.ship.position
	scene.set_process(true)
	await create_timer(0.1).timeout
	scene.set_process(false)
	check(world.ship.position == paused, "Opening chart must pause filament transit")
	await key(KEY_SHIFT, true)
	await key(KEY_D, true)
	await key(KEY_D, false)
	await key(KEY_SHIFT, false)
	check(highway.attached(), "Chart input must not break out of transit")
	scene.toggle_chart()

	# Directional boost, Shift+W shortcut, and double-tap all break free.
	await key(KEY_TAB, true)
	await key(KEY_D, true)
	scene._process(0.016)
	await key(KEY_D, false)
	await key(KEY_TAB, false)
	check(not highway.attached() and highway.lockout > 0, "Tab+direction must defeat the magnetic pull")
	var escaped := world.ship.position
	world.advance(0.2, Vector2(1, 0), 0.0, false, false)
	check(world.ship.position.distance_to(escaped) > 8, "Breakout must produce actual motion")
	check(not highway.try_enter(gate.position - axis, gate.position + axis), "Breakout lockout must prevent immediate recapture")
	world._fire_shot()
	check(not world.shots.is_empty(), "Weapons must unlock after breakout")
	enter(id)
	await key(KEY_SHIFT, true)
	await key(KEY_W, true, true)
	await key(KEY_W, false)
	await key(KEY_SHIFT, false)
	check(not highway.attached() and not world.cruise, "Shift+W must break free rather than engage cruise in transit")
	enter(id)
	world.dodge_cooldown = 0
	world.tap_direction(KEY_A, 10)
	check(world.tap_direction(KEY_A, 10.1) and not highway.attached(), "Double-tap directional boost must break free")

	# G positions outside an entry and faces into its ring.
	place(id, Vector3.UP * 160 + Vector3(0, 0, 160), 160)
	world.brake()
	world.navigate_to(id)
	for frame in 600:
		world.advance(0.05, Vector2.ZERO, 0.0, false, false)
		if not world.autopilot: break
	check(not world.autopilot and not highway.attached(), "Navigate must stop outside a highway gate")
	check(world.ship.position.distance_to(highway.approach_position(id)) < 18, "Navigation must reach the safe approach waypoint")
	check((-world.ship.basis.z).dot(axis) > 0.99, "Approach must align the ship into the filament")

	# Native chart and gate-click geometry are exercised in rendered runs.
	scene.toggle_chart()
	check(scene.chart._picker.item_count == 59, "Chart must list highway entrances")
	await scene._capture(capture_dir, "artois-highways-chart.png")
	if DisplayServer.get_name() != "headless":
		await click(scene.chart, scene.chart.target_point(world.layout.target(id)))
		check(world.selected_id == id, "Chart rings must select the matching highway gate")
	scene.toggle_chart()
	place(id, Vector3.ZERO, 125)
	world.select_target(id)
	scene._process(0)
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		world.select_target("embry")
		var factor := maxf(scene.size.x / scene.space_view.size.x, scene.size.y / scene.space_view.size.y)
		var offset: Vector2 = (scene.size - Vector2(scene.space_view.size) * factor) * 0.5
		var point: Vector2 = world.camera.unproject_position(gate.position) * factor + offset
		scene.free_mouse = true
		await click(scene, point)
		check(world.selected_id == id, "Space click must change selection to the highway ring")
	await scene._capture(capture_dir, "artois-filament-approach.png")
	enter(id)
	for frame in 17: world.advance(0.1, Vector2.ZERO, 0.0, false, false)
	scene._process(0)
	await process_frame
	await process_frame
	await scene._capture(capture_dir, "artois-filament-transit.png")
	if not capture_dir.is_empty():
		var route := highway.routes[7]
		var midpoint: Vector3 = (route.start + route.end) * 0.5
		world.camera.position = midpoint + Vector3(0, 180, 950)
		world.camera.look_at(midpoint, Vector3.UP)
		scene.target_hud.queue_redraw()
		await process_frame
		await process_frame
		await scene._capture(capture_dir, "artois-filament-overview.png")
	world.prepare_launch()
	check(not highway.attached() and world.velocity == Vector3.ZERO, "Launch/reset must clear transit state")
	if failures == 0: print("PASS: golden highway layout, both directions, swept capture, 10x travel, magnetic centring, arrival, boost/dodge escape, chart pause and approach navigation")
	quit(0 if failures == 0 else 1)


func key(code: Key, pressed: bool, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame


func click(control: Control, local: Vector2) -> void:
	var at := root.get_final_transform() * (control.get_global_transform_with_canvas() * local)
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
