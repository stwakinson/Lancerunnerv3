extends SceneTree
var failures := 0
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
	var scene: Control = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	var world := scene.space_world as ArtoisSpace
	var count := 0
	for entry in world.layout.locations:
		if entry.kind != "hyper_gate": continue
		count += 1
		check(entry.destination == null and not entry.enabled, "Hyper gate must be unlinked and disabled")
		check(world.landmarks.has(entry.id), "Hyper gate must have visible geometry")
		var facing := Vector3(entry.facing[0], entry.facing[1], entry.facing[2])
		world.highways.reset()
		world.brake()
		world.ship.position = world.layout.world(entry) - facing * 110
		world.select_target(entry.id)
		world.align_to_target()
		world.reset_view()
		check(world.docking_error().contains("HYPER GATE OFFLINE"), "Gate approach must explain its inactive demo status")
		await scene.toggle_docking()
		check(not scene.landed and current_scene == scene, "Interacting with hyper gate must never leave Artois or land")
		world.ship.position = world.layout.world(entry) - facing * 5
		world.velocity = facing * 35
		world.ship.basis = Basis.looking_at(facing, Vector3.UP)
		world.advance(0.3, Vector2.ZERO, 1.0, false, false)
		check(current_scene == scene and not world.highways.attached(), "Crossing a dormant hyper gate must not teleport or capture")
	check(count == 3, "Demo must have north, east and south hyper gates")
	var north := world.layout.target("calais_gate")
	var south := world.layout.target("picardie_gate")
	var east := world.layout.target("east_gate")
	check(north.direction == "north" and south.direction == "south" and east.direction == "east", "Gate directions must match requested termini")
	check(world.layout.world(east).x > world.layout.world(world.layout.target("maroeuil_field")).x, "East gate must be beyond Maroeuil")
	var route: Dictionary = world.layout.highways.back()
	# Measure the authored terminal gap in map units so system-scale changes remain valid.
	check(route.id == "junction_east" and world.layout.world({"map": route.to}).distance_to(world.layout.world(east)) / world.layout.scale_factor < 25, "East highway must terminate near its hyper gate")
	scene.toggle_chart()
	check(scene.chart._picker.item_count == 61, "Chart must list the new gate and eastern highway entrances")
	await scene._capture(capture_dir, "artois-hyper-gates-chart.png")
	scene.toggle_chart()
	world.ship.position = world.layout.world(east) + Vector3(-240, 50, 70)
	world.select_target("east_gate")
	world.brake()
	world.align_to_target()
	world.reset_view()
	world.combat.ordnance.cursor_enabled = false
	scene._process(0)
	await process_frame
	await process_frame
	await scene._capture(capture_dir, "artois-east-hyper-gate.png")
	if failures == 0: print("PASS: north/east/south dormant hyper gates, null destinations, inert crossings, chart and eastern highway")
	quit(0 if failures == 0 else 1)
