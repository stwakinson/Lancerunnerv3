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
	var combat: Node3D = world.combat
	world.traffic.player_present = false
	world.ship.position = Vector3(0, 2200, 0)
	world.brake()
	combat.hull = 100000 # Observe a whole fight without defeat changing scenes.
	combat.spawn_patrol(Vector3(0, 2200, -110))
	for i in range(4, 0, -1):
		combat.enemies[i].queue_free()
		combat.enemies.remove_at(i)
	var fighter: Node3D = combat.enemies[0]
	var brain: RefCounted = fighter.get_meta("brain")
	var states := {}
	for frame in 900:
		var before := fighter.basis.orthonormalized().get_rotation_quaternion()
		var cruising: bool = brain.cruise
		world.advance(1.0 / 60, Vector2.ZERO, 0, false, false)
		states[brain.state] = true
		for shot in combat.hostile_shots:
			if float(shot.get_meta("remaining")) > 3.47:
				var relative: Vector3 = shot.get_meta("velocity") - brain.velocity
				check((-fighter.global_basis.z.normalized()).angle_to(relative) <= PI / 6 + 0.01, "Real AI shots must stay inside the gun arc")
				check(is_equal_approx(relative.length(), 110), "AI shots must inherit ship velocity")
		var angle := before.angle_to(fighter.basis.orthonormalized().get_rotation_quaternion())
		check(angle < deg_to_rad(70.0) / 60.0 + 0.002, "Fighter turning must be bounded")
		if cruising and brain.cruise: check(angle < deg_to_rad(12.6) / 60.0 + 0.002, "Cruise turning must be slower")
		if brain.state in ["BREAK AWAY", "RECOVER"]: check(not brain.committed(), "Recovery must release the attack slot")
	for state in ["WINDUP", "ATTACK RUN", "BREAK AWAY", "RECOVER"]: check(states.has(state), "Duel must visit " + state)
	check(brain.shots_fired > 0 and combat.shield < combat.shield_max, "Committed runs must fire real projectiles that can hit")
	# Reaction time: a visible, incoming round never triggers an immediate dodge.
	combat.clear_projectiles()
	fighter.global_position = world.ship.position + Vector3(0, 0, -160)
	fighter.basis = Basis.looking_at(Vector3.BACK, Vector3.UP).scaled(Vector3.ONE * 1.6)
	fighter.set_meta("velocity", Vector3.ZERO)
	brain.idle(0)
	brain.state = "WINDUP"
	brain.timer = -3
	brain._dodge_wait = 0
	var round: MeshInstance3D = combat._projectile(fighter.position + Vector3(0, 0, 100), Vector3(0, 0, -125), 48, "8ae5ed", 3)
	world.shots.append(round)
	var dodges: int = brain.dodges
	for i in 2: brain.advance(0.1, world.ship, Vector3.ZERO, false, 1.0, 0)
	check(brain.dodges == dodges, "NPC must not dodge before reaction delay")
	for i in 4: brain.advance(0.1, world.ship, Vector3.ZERO, false, 1.0, 0)
	check(brain.dodges == dodges + 1, "NPC must perform a delayed physical dodge")
	check(absf(fighter.position.x - world.ship.position.x) > 5, "Dodge must move the fighter")
	combat.clear_projectiles()
	# Recovery guard uses the player's directional block and power rules.
	fighter.position = world.ship.position + Vector3(0, 0, -150)
	fighter.set_meta("velocity", Vector3.ZERO)
	brain.state = "RECOVER"
	brain.timer = 0
	brain.hit()
	brain.defence.energy = 100
	brain.advance(0.1, world.ship, Vector3.ZERO, false, 1.0, 0)
	check(not brain.defence.guard_active, "Guard must respect reaction delay")
	brain.advance(0.3, world.ship, Vector3.ZERO, false, 1.0, 0)
	check(brain.defence.guard_active, "Threatened recovering fighter must raise its guard")
	var shield: float = fighter.get_meta("shield")
	combat.damage_enemy(str(fighter.get_meta("id")), 20, -1, fighter.global_position - fighter.global_basis.z.normalized() * 30)
	check(is_equal_approx(float(fighter.get_meta("shield")), shield - 1), "NPC frontal guard must block 95 percent")
	combat.damage_enemy(str(fighter.get_meta("id")), 5, -1, fighter.global_position + fighter.global_basis.z.normalized() * 30)
	check(is_equal_approx(float(fighter.get_meta("shield")), shield - 6), "Rear damage must bypass NPC guard")
	# A ship facing away cannot shoot sideways or backwards.
	fighter.position = world.ship.position + Vector3(0, 0, -150)
	fighter.basis = Basis.IDENTITY.scaled(Vector3.ONE * 1.6)
	fighter.set_meta("velocity", Vector3.ZERO)
	brain.state = "ATTACK RUN"
	brain.timer = 0
	brain._burst = 2
	brain._shot_wait = 0
	brain._goal = fighter.position + Vector3.FORWARD * 100
	brain.defence.energy = 100
	var behind: Dictionary = brain.advance(0.1, world.ship, Vector3.ZERO, true, 1, 0)
	check(not behind.fire and is_equal_approx(brain.defence.energy, 100), "Out-of-arc shots must neither fire nor consume energy")
	fighter.basis = Basis.looking_at(Vector3.BACK, Vector3.UP).scaled(Vector3.ONE * 1.6)
	brain._goal = world.ship.position + Vector3.BACK * 100
	var aligned: Dictionary = brain.advance(0.1, world.ship, Vector3.ZERO, true, 1, 0)
	check(aligned.fire and is_equal_approx(brain.defence.energy, 88), "Aligned AI shot must spend the same twelve energy")
	# An empty reserve cannot fire; transit cannot fire or block.
	brain.state = "ATTACK RUN"
	brain.timer = 0
	brain._burst = 2
	brain._shot_wait = 0
	brain.defence.energy = 0
	brain.defence._quiet = 0
	var action: Dictionary = brain.advance(0.1, world.ship, Vector3.ZERO, true, 1.0, 0)
	check(not action.fire, "NPC guns must require energy")
	brain.idle(0)
	fighter.position = world.ship.position + Vector3(0, 0, -500)
	fighter.basis = Basis.looking_at(Vector3.BACK, Vector3.UP).scaled(Vector3.ONE * 1.6)
	fighter.set_meta("velocity", Vector3.ZERO)
	brain.advance(0.1, world.ship, Vector3.ZERO, true, 1.0, 0)
	check(not brain.cruise and brain.charge > 0, "NPC interception must spool")
	for i in 18:
		action = brain.advance(0.1, world.ship, Vector3.ZERO, true, 1.0, 0)
		check(not action.fire and not brain.defence.guard_active, "Cruise/spool must lock guns and guard")
	check(brain.cruise, "Cruise must engage after spool")
	brain.advance(0.1, world.ship, Vector3.ZERO, true, 1.0, 6)
	check(not brain.cruise and brain.charge == 0 and brain.velocity.length() <= 12.001, "Fetter must cancel AI cruise and cap speed")
	brain.advance(0.1, world.ship, Vector3.ZERO, true, 0.1, 0)
	check(brain.state == "RETREAT", "Wounded freebooters must attempt a retreat")
	# Real ambient impacts must carry direction and use the round's actual damage.
	combat.clear_projectiles()
	combat.repair()
	world.traffic.player_present = true
	world.ship.rotation = Vector3.ZERO
	combat.defence.guard_active = true
	combat.defence.guard_direction = Vector3.FORWARD
	var hostile: MeshInstance3D = combat._projectile(world.ship.position + Vector3.FORWARD * 20, Vector3.BACK * 110, 22, "ff7059", 3)
	hostile.set_meta("source", "local_freebooter_01")
	world.traffic.shots.append(hostile)
	world.traffic._advance_shots(0.2)
	check(is_equal_approx(combat.shield, 58.9), "Player guard must block an actual ambient NPC round")
	var trader: Dictionary = world.traffic.actors.local_britannian_01
	trader.node.position = world.ship.position + Vector3.RIGHT * 80
	trader.node.visible = true
	trader.hull = 145
	trader.shield = 0
	var local_round: MeshInstance3D = combat._projectile(trader.node.position + Vector3.FORWARD * 25, Vector3.BACK * 110, 22, "ff7059", 3)
	local_round.set_meta("source", "local_freebooter_01")
	world.traffic.shots.append(local_round)
	world.traffic._advance_shots(0.25)
	check(is_equal_approx(trader.hull, 123), "NPC-to-NPC collision must use projectile damage instead of six")
	world.traffic.player_present = false
	combat.hull = 100000
	# A squad shares two commitment slots and uses different staging positions.
	combat.clear_encounter()
	world.ship.position = Vector3(0, 2200, 0)
	combat.spawn_patrol(Vector3(0, 2200, -100))
	var flanked := false
	for frame in 720:
		world.advance(1.0 / 60, Vector2.ZERO, 0, false, false)
		check(combat.committed_attackers("player") <= 2, "A five-ship squad must not all attack at once")
		for ship in combat.enemies:
			if ship.get_meta("brain").state == "FLANK": flanked = true
	check(flanked, "Non-committed ships must stage on the flanks")
	var observer: RefCounted = combat.enemies[0].get_meta("brain")
	var planet: Vector3 = world.layout.world(world.layout.planet)
	observer.pilot.position = planet + Vector3.RIGHT * (float(world.layout.planet.radius) + 100)
	check(not observer._clear_line(planet - Vector3.RIGHT * (float(world.layout.planet.radius) + 100)), "AI must not shoot through the planet")
	# Personality changes timing/accuracy without exposing raider affiliation in the HUD.
	var raider: Dictionary = world.traffic.actors.local_raider_01
	check(raider.brain.personality == "valois" and not world.traffic.target_entry(raider.id).notes.contains("Valois"), "Raider tactics must keep their affiliation concealed")
	if not capture_dir.is_empty():
		world.prepare_launch()
		world.ship.position += Vector3(0, 300, 0)
		combat.clear_encounter()
		combat.repair()
		combat.spawn_patrol(world.ship.position + Vector3(0, 0, -20))
		for i in combat.enemies.size():
			combat.enemies[i].get_meta("brain").state = "WINDUP" if i in [1, 2] else "FLANK"
			combat.enemies[i].get_meta("brain").timer = 0
		world.advance(0.2, Vector2.ZERO, 0, false, false)
		world.select_target("patrol_3")
		world.reset_view()
		scene._process(0)
		scene.target_hud.queue_redraw()
		await scene._capture(capture_dir, "artois-enemy-windup.png")
		var guarding: RefCounted = combat.enemies[2].get_meta("brain")
		guarding.state = "RECOVER"
		guarding.timer = 0
		guarding.hit()
		guarding.advance(0.45, world.ship, Vector3.ZERO, false, 1, 0)
		scene.target_hud.queue_redraw()
		await scene._capture(capture_dir, "artois-enemy-guard.png")
	print("TACTICAL AI: %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)
