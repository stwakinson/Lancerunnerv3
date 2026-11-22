extends SceneTree
var failures := 0
var scene: Control
var world: ArtoisSpace
var traffic: ArtoisTraffic
var capture_dir := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func quiet() -> void:
	for actor in traffic.actors.values():
		if actor.hostile:
			actor.target = ""
			actor.provoked = false
			actor.decision = 9999


func _run() -> void:
	scene = load("res://scenes/artois.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	while root.get_node("SceneFader").busy: await process_frame
	world = scene.space_world
	traffic = world.traffic
	check(traffic.actors.size() == 30 and traffic.population_limit == 30, "Population must be bounded at thirty session locals")
	var counts := {}
	var identities := {}
	var names := {}
	for actor in traffic.actors.values():
		counts[actor.faction] = int(counts.get(actor.faction, 0)) + 1
		check(not names.has(actor.name), "Every local ship must have a unique stable callsign")
		names[actor.name] = true
		identities[actor.id] = [actor.pilot, actor.name, actor.node.get_instance_id()]
		if not actor.hostile:
			check(world.layout.target(actor.destination).kind != "hyper_gate", "Local trade must never target closed hyper gates")
			check(not actor.path.is_empty(), "Civilian ships must start with real orders")
	check(counts == {"hanseatic": 6, "britannian": 5, "valois": 5, "borderlander": 8, "freebooter": 4, "raider": 2}, "Faction mix must match the finite roster")
	var cog: Dictionary = traffic.actors.local_hanseatic_01
	world.select_target(cog.id)
	check(world.target_entry().pilot == cog.pilot and world.target_entry().notes.contains("Cargo:"), "Tracking must expose pilot, cargo and current orders")
	check(world.combat.enemy(cog.id) == null, "Civilian traffic must not become a missile-lock enemy")
	check(traffic.nearby_ids().has(cog.id), "Nearby contact cycling must include the merchant at launch")
	check(scene.Picking.pick(world, world.camera.unproject_position(cog.node.position)).begins_with("local_"), "Space picking must include local hulls")
	scene._process(0)
	await process_frame
	await process_frame
	await scene._capture(capture_dir, "artois-local-merchants.png")

	# Actual world-click selection in a rendered window.
	if DisplayServer.get_name() != "headless":
		world.select_target(world.DOCK_ID)
		var factor := maxf(scene.size.x / scene.space_view.size.x, scene.size.y / scene.space_view.size.y)
		var at: Vector2 = world.camera.unproject_position(cog.node.position) * factor + (scene.size - Vector2(scene.space_view.size) * factor) * 0.5
		await click(at)
		check(world.selected_id.begins_with("local_"), "Left-click must change selection to a visible local")
		await key(KEY_V)
		check(world.selected_id.begins_with("local_"), "V must cycle nearby contacts through actual input")
	world.combat.ordnance.cursor_enabled = false

	# Long-lived routines: a full delivery, dwell, departure and a salvage stop.
	quiet()
	traffic.player_present = false
	world.ship.position = Vector3(20000, 1000, 20000)
	var plan := traffic.routes.plan(traffic.routes.harbour("border_post"), traffic.routes.harbour("southern_outpost"))
	var uses_filament := false
	for leg in plan:
		if leg.mode == "filament": uses_filament = true
	check(uses_filament, "Long trips must plan through the authored highway network")
	var from: Vector3 = cog.node.position
	var saw_filament := false
	for i in 1800:
		traffic.advance(0.1)
		if cog.state == "FILAMENT TRANSIT": saw_filament = true
		if cog.trips > 0: break
	check(cog.trips > 0 and cog.state == "DOCKED" and not cog.node.visible, "Merchant must reach its berth and unload")
	check(cog.distance > 200 and cog.node.position.distance_to(from) > 200, "Routine must actually travel through the system")
	var delivered_to: String = cog.destination
	traffic.advance(21)
	check(cog.destination != delivered_to or cog.trips > 1, "After its dwell the same merchant must depart on another trip")
	var salvager: Dictionary = traffic.actors.local_borderlander_06
	salvager.destination = "wrecked_shipyard"
	salvager.node.position = traffic.routes.harbour("wrecked_shipyard")
	salvager.path = [{"position": salvager.node.position, "mode": "flight"}]
	salvager.leg = 0
	salvager.state = "SALVAGE RUN"
	salvager.salvage_next = false
	traffic.advance(0.2)
	check(salvager.state == "SALVAGING" and salvager.node.visible and salvager.cargo == "Recovered scrap", "Salvager must hold at a wreck and recover cargo")
	traffic.advance(21)
	check(salvager.destination in traffic.profiles.borderlander.ports, "Salvager must return to a local port")
	for actor in traffic.actors.values():
		check(identities[actor.id] == [actor.pilot, actor.name, actor.node.get_instance_id()], "Distance and elapsed time must not replace NPC identity")
	check(traffic.actors.size() == 30, "No background spawn loop may exceed the roster cap")

	# Disguised raiders choose trade targets without revealing their allegiance.
	quiet()
	var raider: Dictionary = traffic.actors.local_raider_01
	var brit: Dictionary = traffic.actors.local_britannian_01
	var valois: Dictionary = traffic.actors.local_valois_01
	var zone := Vector3(6000, 300, 2000)
	raider.node.position = zone
	brit.node.position = zone + Vector3(0, 0, 200)
	valois.node.position = zone + Vector3(0, 0, 80)
	brit.node.visible = true
	valois.node.visible = true
	traffic._choose_prey(raider)
	check(raider.target == brit.id, "Raiders must make selective attacks rather than attack the closer Valois trader")
	check(traffic.target_entry(raider.id).faction == "Unidentified Raiders" and not traffic.target_entry(raider.id).notes.contains("Valois"), "Target information must not expose the raiders' hidden affiliation")

	# A pirate fires a swept projectile at a trader; the trader flees and calls out.
	quiet()
	var pirate: Dictionary = traffic.actors.local_freebooter_02
	brit.node.position = zone + Vector3(0, 0, 90)
	brit.node.visible = true
	brit.shield = 40.0
	brit.hull = 145.0
	brit.state = "LOCAL DELIVERY"
	brit.velocity = Vector3.ZERO
	brit.provoked = false
	brit.decision = 0
	pirate.node.position = zone
	pirate.node.look_at(brit.node.position, Vector3.UP)
	pirate.brain.idle(0)
	# Start an already-signalled ambush; the trader can still spool and flee.
	pirate.brain.state = "WINDUP"
	pirate.brain.timer = 0.7
	pirate.velocity = Vector3.ZERO
	pirate.target = brit.id
	pirate.fire_wait = 0
	pirate.decision = 9999
	world.ship.position = brit.node.position + Vector3(300, 0, 0)
	traffic._radio_ready = 0
	var before: Vector3 = brit.node.position
	for i in 120: traffic.advance(0.05)
	check(brit.state == "FLEEING" and brit.node.position.distance_to(before) > 20, "Civilian must evade an actual local attacker")
	check(brit.shield < 40, "NPC projectiles must damage other NPCs")
	check(not traffic.radio_history.is_empty(), "Local actions must produce contextual radio messages")

	world.ship.position = brit.node.position + Vector3(65, 25, 150)
	world.select_target(brit.id)
	world.align_to_target()
	world.reset_view()
	scene._process(0)
	await process_frame
	await process_frame
	await scene._capture(capture_dir, "artois-local-encounter.png")

	# The player can fight locals; these kills never advance the test sortie.
	quiet()
	scene.mission.accept()
	var enemy: Dictionary = traffic.actors.local_freebooter_01
	zone = Vector3(4000, 800, 4000)
	enemy.node.position = zone
	enemy.hull = 80.0
	enemy.shield = 25.0
	enemy.velocity = Vector3.ZERO
	enemy.target = "player"
	enemy.decision = 9999
	enemy.fire_wait = 0
	world.ship.position = zone + Vector3(0, 0, 85)
	world.ship.rotation = Vector3.ZERO
	world.brake()
	world.combat.repair()
	world.combat.ordnance.cursor_enabled = false
	traffic.player_present = true
	world.select_target(enemy.id)
	# Give a telegraphed attacker time to commit before the player retaliates.
	enemy.node.look_at(world.ship.position, Vector3.UP)
	enemy.brain.idle(0)
	for i in 180: world.advance(1.0 / 30, Vector2.ZERO, 0, false, false)
	var took_damage: bool = world.combat.shield < world.combat.shield_max
	for i in 360:
		var lead: Vector3 = enemy.node.position + enemy.velocity * minf(world.ship.position.distance_to(enemy.node.position) / 125.0, 1.4)
		world.ship.look_at(lead, Vector3.UP)
		world._sync_angles()
		world.advance(1.0 / 30, Vector2.ZERO, 0, false, true)
		if not enemy.alive: break
	check(not enemy.alive, "Player projectiles must destroy a local hostile")
	check(took_damage, "Local hostile fire must damage the player before retaliation")
	check(scene.mission.kills == 0, "Local kills must not count toward the separate five-enemy contract")
	world.combat.clear_encounter()
	check(traffic.actors.size() == 30 and not enemy.alive, "Resetting the test encounter must not reset ambient locals")
	traffic.advance(5)
	check(not enemy.alive, "Destroyed locals must not immediately respawn")
	var disrupted: Dictionary = traffic.actors.local_freebooter_03
	disrupted.velocity = Vector3.FORWARD * 350
	world.combat.apply_missile_to_enemy(disrupted.id, "fetter_missile")
	check(disrupted.disruption == 6 and (disrupted.velocity as Vector3).length() <= 12, "Existing Fetter missiles must affect ambient ships")

	# Traffic remains alive during a market visit, without attacking a hidden player.
	quiet()
	world.combat.repair()
	world.highways.reset()
	world.brake()
	world.ship.position = world.target_position(world.DOCK_ID) + Vector3(0, 0, 60)
	await scene.toggle_docking()
	check(scene.landed, "Existing planet docking must still work")
	var clock := traffic.elapsed
	var shield := world.combat.shield
	scene.open_contract()
	scene.set_process(true)
	await create_timer(0.2).timeout
	scene.set_process(false)
	check(traffic.elapsed > clock and not traffic.player_present and world.combat.shield == shield, "Routines must continue safely while the player visits the planet contact")
	scene.contract_panel.close_panel()
	await scene.toggle_docking()
	check(world.traffic == traffic and traffic.actors.size() == 30 and not enemy.alive, "Launching must retain the same local population")
	if failures == 0: print("PASS: finite factions, persistent identities, route planning, delivery/docking/salvage, selective raiders, NPC combat/fleeing, player combat, mission isolation and planet continuity")
	quit(0 if failures == 0 else 1)


func click(local: Vector2) -> void:
	var at := root.get_final_transform() * local
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


func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
