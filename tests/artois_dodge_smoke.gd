extends SceneTree
const Dodge = preload("res://scripts/artois/artois_dodge.gd")
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
	market.save_path = "user://dodge_smoke_%d.json" % OS.get_process_id()
	world.combat.configure(world, market)
	world.ship.position = Vector3(8000, 1500, 8000)
	world.ship.rotation = Vector3.ZERO
	world.brake()
	world.dodge_cooldown = 0
	world.tap_direction(KEY_A, 1)
	check(world.tap_direction(KEY_A, 1.1), "Double tap must start physical dodge")
	var from: Vector3 = world.ship.position
	var root_basis: Basis = world.ship.basis
	var engine_position: Vector3 = world.ship.engines[0].position
	var initial: float = world.dodge_velocity.length()
	check(initial > 0 and initial < 50 and world.ship.position == from, "Kick responds immediately without teleporting or instantly reaching peak")
	world._advance_manual(0.05, Vector2.ZERO, 0, false)
	world.dodge.visualise(0.05)
	check(world.dodge_velocity.length() > initial and world.dodge.phase() == "KICK", "Thrusters must accelerate during kick")
	check(absf(world.dodge.bank.z) > 0.01 and world.ship.basis.is_equal_approx(root_basis), "Hull must bank without rotating aim/camera frame")
	check(world.ship.engines[0].position.distance_to(engine_position) > 0.001 and is_equal_approx(world.ship.engines[0].position.length(), engine_position.length()), "Bank must rotate the complete hull about its centre, including engine positions")
	check(world.dodge._kick_jet.emitting and not world.dodge._counter_jet.emitting, "Kick jets must fire opposite the shove")
	if not capture_dir.is_empty():
		world.reset_view()
		scene._process(0)
		await create_timer(0.06).timeout
		await scene._capture(capture_dir, "artois-dodge-kick.png")
	world._advance_manual(0.1, Vector2.ZERO, 0, false)
	world.dodge.visualise(0.1)
	var peak: float = world.dodge_velocity.length()
	check(peak > 100 and world.dodge.phase() == "SLIDE", "Ship must carry sustained lateral speed after acceleration")
	world._advance_manual(0.15, Vector2.ZERO, 0, false)
	world.dodge.visualise(0.15)
	check(world.dodge_velocity.length() > 0 and world.dodge_velocity.length() < peak and world.dodge._counter_jet.emitting, "Recovery must visibly counter-thrust while retaining drift")
	world.combat.ordnance.cursor_enabled = false
	var shots: int = world.shots.size()
	world.combat.fire()
	check(world.shots.size() > shots, "Guns must work throughout dodge")
	var shield: float = world.combat.shield
	world.combat.damage_player(5)
	check(world.combat.shield < shield, "Dodge must not grant invulnerability")
	world.combat._shield_flash = 0
	world.combat._bubble.visible = false
	# Visual capture of actual recovery, with enough rendered frames to emit particles.
	if not capture_dir.is_empty():
		world.reset_view()
		scene._process(0)
		await create_timer(0.06).timeout
		await scene._capture(capture_dir, "artois-dodge-counter-thrust.png")
	world._advance_manual(0.5, Vector2.ZERO, 0, false)
	world.dodge.visualise(1.0)
	check(not world.dodge.active and world.dodge_velocity == Vector3.ZERO and world.dodge.bank.length() < 0.001, "Recovery must finish cleanly and right the hull")
	check(from.distance_to(world.ship.position) > 30 and from.distance_to(world.ship.position) < 50, "Physical dodge must travel a useful bounded distance")
	var reference := Vector3.ZERO
	for fps in [30, 60, 144]:
		var dodge := Dodge.new()
		dodge.start(Vector3.LEFT, market.Ships.catalog.fighter.dodge)
		var displacement := Vector3.ZERO
		for frame in fps: displacement += dodge.advance(1.0 / fps)
		if fps == 30: reference = displacement
		check(reference.distance_to(displacement) < 0.001 and not dodge.active, "Distance and recovery must be frame-rate independent")
	var light := Dodge.new()
	var heavy := Dodge.new()
	light.start(Vector3.LEFT, market.Ships.catalog.interceptor.dodge)
	heavy.start(Vector3.LEFT, market.Ships.catalog.pilgrim.dodge)
	light.advance(0.1)
	heavy.advance(0.1)
	check(light.velocity.length() > heavy.velocity.length() * 2 and heavy.duration() > light.duration(), "Heavy trader must accelerate/recover more slowly than interceptor")
	world.brake()
	world.dodge_cooldown = 0
	world.tap_direction(KEY_A, 3)
	world.tap_direction(KEY_A, 3.1)
	world.ship.rotation.y = PI / 2
	from = world.ship.position
	world._advance_manual(0.1, Vector2.ZERO, 0, false)
	check((world.ship.position - from).normalized().dot(Vector3.LEFT) > 0.999, "Steering must not rotate already-established dodge momentum")
	world.apply_disruption(6)
	check(not world.dodge.active and world.dodge_velocity == Vector3.ZERO and not world.dodge._kick_jet.visible, "Fetter must cancel motion and presentation together")
	world.disruption_remaining = 0
	world.dodge_cooldown = 0
	world.tap_direction(KEY_A, 5)
	world.tap_direction(KEY_A, 5.1)
	world.brake()
	check(not world.dodge.active and world.dodge.bank == Vector3.ZERO, "Brake must cancel motion and restore hull attitude")
	market.ship_class = "pilgrim"
	world.combat.configure(world, market)
	world.dodge_cooldown = 0
	world.tap_direction(KEY_D, 7)
	world.tap_direction(KEY_D, 7.1)
	check(world.dodge.duration() > 0.8 and world.dodge_cooldown > world.dodge.duration(), "Ship swap must select the trader's heavier profile and recovery cooldown")
	world.prepare_launch()
	check(not world.dodge.active and world.dodge_velocity == Vector3.ZERO and world.dodge.bank == Vector3.ZERO, "Launch must not carry residual dodge motion/bank")
	print("PHYSICAL SHIP DODGE: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
