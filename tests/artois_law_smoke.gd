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
	while root.get_node("SceneFader").busy: await process_frame
	var world: Node3D = scene.space_world
	var market := LandingMarketState.new()
	market.save_path = "user://law_smoke_%d.json" % OS.get_process_id()
	world.combat.configure(world, market)
	var law: Node = world.law
	var traffic: Node3D = world.traffic
	check(traffic.actors.size() == 38, "Thirty locals plus eight guards")
	var guard: Dictionary = traffic.actors.local_britannian_navy_01
	var cog: Dictionary = traffic.actors.local_hanseatic_01
	check(not law.enemy(guard) and traffic.target_entry(guard.id).kind == "local", "Armed neutral guards must not be red")
	check(law.territory_owner("agincourt") == "valois" and law.territory_owner("east_gate") == "valois" and law.territory_owner("picardie_gate") == "valois" and law.territory_owner("calais_gate") == "britannian", "Territorial ownership")
	world.ship.position = guard.node.position + Vector3(60, 0, 0)
	traffic._choose_prey(guard)
	check(guard.target != "player", "Neutral guard must not attack peaceful player")
	traffic.damage(cog.id, 1, 1)
	check(law.score("hanseatic") == -8 and law.score("britannian") == -3 and law.score("valois") == -3, "Civilian assault must harm both protectors")
	for i in 20: traffic.damage(cog.id, 1, 1)
	check(law.score("hanseatic") == -8, "Bullet bursts must count as one incident")
	traffic.damage(cog.id, 10000, 10000)
	check(law.score("hanseatic") == -38 and law.score("britannian") == -15 and law.score("valois") == -15, "Destruction must carry additional larger penalty")
	traffic.damage(cog.id, 10000, 10000)
	check(law.score("hanseatic") == -38, "Death may not be charged twice")
	var neutral: Dictionary = traffic.actors.local_borderlander_01
	traffic.damage(neutral.id, 1, 1, "local_raider_01")
	check(law.score("borderlander") == 0, "NPC crimes must not implicate player")
	var before: int = law.score("valois")
	var raider: Dictionary = traffic.actors.local_raider_01
	traffic.damage(raider.id, 10000, 10000)
	check(law.score("valois") == before, "Secret raiders must not leak Valois allegiance")
	for i in range(2, 5):
		var merchant: Dictionary = traffic.actors["local_hanseatic_%02d" % i]
		traffic.damage(merchant.id, 10000, 10000)
	check(law.hostile("britannian") and law.hostile("valois"), "Repeated merchant murders must turn both powers hostile")
	traffic._choose_prey(guard)
	check(guard.target == "player" and law.enemy(guard), "Hostile naval guards must engage player within patrol area")
	world.ship.position = Vector3(9000, 9000, 9000)
	traffic._choose_prey(guard)
	check(guard.target != "player", "Naval guard must not pursue across whole system")
	var loaded := LandingMarketState.new()
	loaded.save_path = market.save_path
	check(loaded.load_state() and loaded.reputation == market.reputation, "Negative standings must survive save/load")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(market.save_path))
	data.erase("reputation")
	check(market._valid_save(data), "Old saves must remain valid")
	data.reputation = {"britannian": -101}
	check(not market._valid_save(data), "Malformed standings must be rejected")
	world.ship.position = world.launch_position()
	world.reset_view()
	law.ledger_visible = true
	scene.target_hud.queue_redraw()
	await process_frame
	if not capture_dir.is_empty(): await scene._capture(capture_dir, "artois-reputation.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(market.save_path))
	print("ARTOIS REPUTATION AND LAW: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
