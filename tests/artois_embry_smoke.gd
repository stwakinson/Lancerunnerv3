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
	var station: Node3D = world.landmarks.embry
	var field: MultiMeshInstance3D = world.field_nodes.embry_field
	check(station.get_meta("profile") == "embry_canyon_station", "Embry must use the industrial tower model")
	check(station.position.is_equal_approx(world.layout.world(world.layout.target("embry"))), "Station map/nav coordinates must stay unchanged")
	check(field.get_meta("profile") == "column_canyon" and field.multimesh.instance_count == 220, "Embry must retain 220 field instances using the new profile")
	check(world.asteroid_count == 780 and world.field_nodes.size() == 3, "Other fields and system counts must remain intact")
	var tall := 0
	var nearby := 0
	for box in world.embry_art.column_bounds:
		if box.size.y > 200: tall += 1
		if box.get_center().distance_to(station.position) < 350: nearby += 1
		check(world.embry_art._clear(box, world, station.position), "Columns must preserve station and authored traffic approach clearances")
	check(tall == 64 and nearby >= 3, "Major columns must tower over and nest around the station")
	var harbour: Vector3 = world.traffic.routes.harbour("embry")
	check(harbour.is_equal_approx(station.position + Vector3(0, 20, 95)), "Existing traffic harbour must remain at the front platform")
	var body := station.get_node("EmbryIndustrialTower") as MeshInstance3D
	check(body.get_aabb().size.y > 250, "Tower must include its dome deck, balconies and long hanging understructure")
	for actor in world.traffic.actors.values():
		if actor.hostile:
			actor.target = ""
			actor.decision = 9999
	# An actual cog approach should remain a clear, selectable route to the station.
	var cog: Dictionary = world.traffic.actors.local_hanseatic_01
	cog.node.position = harbour + Vector3(0, 0, 120)
	cog.path = [{"position": harbour, "mode": "flight"}]
	cog.leg = 0
	cog.destination = "embry"
	cog.state = "LOCAL DELIVERY"
	cog.velocity = Vector3.ZERO
	world.traffic.player_present = false
	for i in 100:
		world.traffic.advance(0.1)
		if cog.state == "DOCKED": break
	check(cog.state == "DOCKED", "Local cargo traffic must still complete an Embry harbour approach")

	world.highways.reset()
	world.brake()
	world.select_target("embry")
	world.ship.position = station.position + Vector3(60, 30, 300)
	world.align_to_target()
	world.reset_view()
	world.combat.ordnance.cursor_enabled = false
	world.camera.position = station.position + Vector3(190, 85, 480)
	world.camera.look_at(station.position + Vector3(0, 10, 0), Vector3.UP)
	scene.target_hud.queue_redraw()
	scene._status.text = "EMBRY / COLUMN CANYON / STATION APPROACH"
	scene.contact_label.text = "EMBRY / INDUSTRIAL STATION / COLUMN CANYON"
	var pixel := world.camera.unproject_position(station.position + Vector3(0, 35, 12))
	check(scene.Picking.pick(world, pixel) == "embry", "Tall column bounds must not steal station clicks through empty space")
	await process_frame
	await process_frame
	await scene._capture(capture_dir, "embry-station-canyon.png")
	world.camera.position = station.position + Vector3(650, 210, 900)
	world.camera.look_at(station.position + Vector3(0, 20, -100), Vector3.UP)
	scene.target_hud.queue_redraw()
	await process_frame
	await process_frame
	await scene._capture(capture_dir, "embry-column-field.png")
	if failures == 0: print("PASS: Embry column geometry, tower, unchanged navigation/counts, traffic corridors, harbour delivery and station picking")
	quit(0 if failures == 0 else 1)
