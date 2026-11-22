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
	var highway: Node3D = world.highways
	check(highway.gates.size() == 36, "Nine links must have two rings at each end")
	for index in highway.routes.size():
		var route: Dictionary = highway.routes[index]
		var prefix: String = "highway_" + str(route.id)
		var a: Dictionary = highway.gates[prefix + "_a"]
		var b: Dictionary = highway.gates[prefix + "_b"]
		check(a.position.y - b.position.y == 80, "Opposing lanes must be 80 metres apart")
		for sample in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var upper: Vector3 = highway.lane_point(index, route.length * sample, 1)
			var lower: Vector3 = highway.lane_point(index, route.length * sample, -1)
			check(is_equal_approx(upper.distance_to(lower), 80), "Weaving must preserve lane separation")
		check(highway.lane_point(index, 0, 1).is_equal_approx(a.position), "Weave must meet upper entrance")
		check(highway.lane_point(index, route.length, -1).is_equal_approx(b.position), "Weave must meet lower entrance")
		var graph: RefCounted = world.traffic.routes
		check(graph.filaments.has(Vector2i(index * 4, index * 4 + 1)), "Upper NPC graph edge must go A to B")
		check(graph.filaments.has(Vector2i(index * 4 + 2, index * 4 + 3)), "Lower NPC graph edge must go B to A")
		check(not graph.filaments.has(Vector2i(index * 4 + 1, index * 4)), "Upper NPC lane must not be bidirectional")
	var gate: Dictionary = highway.gates.highway_caulers_junction_a
	world.ship.position = gate.position - gate.axis * 3 + Vector3.UP * 10
	world.ship.basis = Basis.looking_at(gate.axis, Vector3.UP)
	world.velocity = gate.axis * 35
	highway.lockout = 0
	check(highway.try_enter(world.ship.position, world.ship.position + gate.axis * 6), "Correct one-way entrance must capture")
	world.ship.position += gate.axis * 6
	check(highway.joining.branches.size() == 1, "Capture must create a light branch to the joining ship")
	check(highway.joining.branches[0].node.mesh != null, "Join branch must have actual render geometry")
	world.advance(0.1, Vector2.ZERO, 0, false, false)
	check(world.velocity.dot(gate.axis) > 35 and world.velocity.dot(gate.axis) < 55, "Entry must accelerate gradually, not jump to 350")
	var midpoint: Vector3 = highway.lane_point(7, highway.routes[7].length * 0.5, 1)
	highway.tick(0.5)
	check(midpoint.distance_to(highway.lane_point(7, highway.routes[7].length * 0.5, 1)) > 0.01, "Tendril centreline must weave over time")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			world.reset_view()
			scene.target_hud.queue_redraw()
			await scene._capture(arg.trim_prefix("--capture-dir="), "artois-filament-joining.png")
	var previous: float = world.velocity.dot(gate.axis)
	for frame in 1200:
		if not highway.attached(): break
		world.advance(1.0 / 60, Vector2.ZERO, 0, false, false)
		var speed: float = world.velocity.dot(gate.axis)
		check(absf(speed - previous) <= 110.0 / 60.0 + 0.1, "Transit including exit must not jump speed")
		previous = speed
	check(not highway.attached() and previous > 35, "Exit must preserve momentum above normal speed")
	world.advance(0.1, Vector2.ZERO, 0, false, false)
	check(world.velocity.dot(gate.axis) < previous and world.velocity.dot(gate.axis) > 35, "Exit must coast down smoothly under manual flight")
	highway.lockout = 0
	var exit: Dictionary = highway.gates.highway_caulers_junction_b_exit
	for sign in [1.0, -1.0]:
		world.ship.basis = Basis.looking_at(exit.axis * sign, Vector3.UP)
		check(not highway.try_enter(exit.position - exit.axis * sign * 3, exit.position + exit.axis * sign * 3), "Exit ring must reject capture in either direction")
	# Real local ships take opposing one-way legs and retain exit momentum.
	var actors: Array = world.traffic.actors.values()
	var npc_route: Dictionary = highway.routes[8]
	for i in 2:
		var actor: Dictionary = actors[i]
		var sign := 1.0 if i == 0 else -1.0
		actor.node.position = highway.lane_point(8, 0 if sign > 0 else npc_route.length, sign)
		actor.velocity = Vector3.ZERO
		actor.disruption = 0.0
		actor.state = "LOCAL DELIVERY"
		actor.leg = 0
		actor.join_leg = -1
		actor.path = [{"position": highway.lane_point(8, npc_route.length if sign > 0 else 0, sign), "mode": "filament", "route": 8, "sign": sign}, {"position": npc_route.end + Vector3(300, 0, 0), "mode": "flight"}]
	for frame in 80:
		for i in 2: world.traffic._civilian_step(actors[i], 0.1)
		check(actors[0].node.position.distance_to(actors[1].node.position) >= 79.9, "Opposing NPC filament traffic must stay apart")
	check((actors[0].velocity as Vector3).dot(npc_route.axis) > 0 and (actors[1].velocity as Vector3).dot(npc_route.axis) < 0, "NPC directions must follow their own lanes")
	var coasting: Dictionary = actors[0]
	coasting.node.position = coasting.path[0].position - npc_route.axis * 5
	coasting.velocity = npc_route.axis * 100
	world.traffic._civilian_step(coasting, 0.1)
	check(coasting.leg == 1 and is_equal_approx((coasting.velocity as Vector3).length(), 100), "NPC exit must not reset its velocity")
	world.traffic._civilian_step(coasting, 0.1)
	check((coasting.velocity as Vector3).length() < 100 and (coasting.velocity as Vector3).length() > 90, "NPC must decelerate gradually after exit")
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.physical_keycode = KEY_SPACE
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	check(scene.free_mouse, "Space must now toggle free cursor")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			var route: Dictionary = highway.routes[7]
			var centre: Vector3 = (route.start + route.end) * 0.5
			world.camera.position = centre + Vector3(0, 200, 850)
			world.camera.look_at(centre)
			scene.target_hud.hide()
			await scene._capture(arg.trim_prefix("--capture-dir="), "artois-paired-filaments.png")
	print("DIRECTIONAL LANES: %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)
