extends Node

# Run with: godot --headless --path . res://tests/component_smoke.tscn
# Exercise the actual game scene so component wiring and existing settings
# are covered alongside firing, hull state, boarding and restart behaviour.

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	for mode in [GameMode.Mode.INFINITE, GameMode.Mode.CLASSIC]:
		GameMode.current = mode
		var game := load("res://scenes/main.tscn").instantiate() as Node3D
		add_child(game)
		await get_tree().process_frame
		await get_tree().process_frame
		game.process_mode = Node.PROCESS_MODE_DISABLED
		var ship := game.get_node("Player") as PlayerShipController
		var gm := game.get_node("GameManager") as GameManager
		var hull := ship.visual.get_node("Hull") as ShipHull
		_check(hull != null, "Ship must build its hull component")
		_check(hull.get_child(0).shape.get_faces().size() > 0, "Hull must contain the ship's mesh faces")
		_check(is_equal_approx(ship.hull_top, hull.top_height), "Pilot must use the generated hull height")
		var skirt := hull.get_node("Skirt") as CollisionShape3D
		hull.update_parked(true)
		_check(not skirt.disabled, "Parked hull must close the gap beneath the ship")
		hull.update_parked(false)
		_check(skirt.disabled, "Flying hull must leave the skirt disabled")

		# Queue a real HUD draw with a known nearby contact, then check that the
		# extracted scope receives it and drops it when it leaves radar range.
		var hud := game.get_node("HUDLayer/HUD") as Hud
		var contact := gm.spawner.fighters[0]
		contact.global_position = ship.global_position + Vector3.RIGHT * 10.0
		hud.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(hud._radar._pings.has(contact.get_instance_id()), "HUD draw must register a nearby radar contact")
		contact.global_position = ship.global_position + ship.aim_camera.global_basis.x * 2000.0
		hud.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(not hud._radar._pings.has(contact.get_instance_id()), "Radar must discard contacts outside its range")

		# Use actual physical-key input and the controller's normal update path.
		# Freeze movement to isolate projectile origin, direction and cadence.
		ship.state = PlayerShipController.State.LANDED
		ship.velocity = Vector3.ZERO
		var camera := ship.aim_camera
		ship.aim_camera = null
		ship.global_basis = Basis.IDENTITY
		ship.fire_rate = 6.0
		ship.bullet_speed = 30.0
		var before := _player_bullets()
		_key(KEY_SPACE, true)
		ship._process(0.0)
		var after := _player_bullets()
		_check(after.size() == before.size() + 1, "Space must fire one ship projectile")
		if after.size() > before.size():
			var shot := after.back() as Bullet
			_check(shot.global_position.is_equal_approx(ship.fire_point.global_position), "Shot must start at the fire point")
			_check(shot.velocity.is_equal_approx(Vector3.FORWARD * 30.0), "Shot must follow the fire point when no aim camera exists")
		ship._process(0.01)
		_check(_player_bullets().size() == after.size(), "Fire rate must prevent an immediate second shot")
		ship._process(0.2)
		_check(_player_bullets().size() == after.size() + 1, "Held fire must repeat after the cooldown")
		var forward := -ship.fire_point.global_basis.z
		ship.velocity = forward * 22.0
		ship._weapons.update(ship, 0.2)
		var boosted_shot := _player_bullets().back() as Bullet
		_check(boosted_shot.velocity.is_equal_approx(forward * 52.0), "Projectiles must inherit forward ship speed")
		ship.velocity = Vector3.ZERO
		ship.aim_camera = camera
		var expected_aim := (camera.aim_point() - ship.fire_point.global_position).normalized()
		ship._weapons.update(ship, 0.2)
		var aimed_shot := _player_bullets().back() as Bullet
		_check(aimed_shot.velocity.normalized().is_equal_approx(expected_aim), "Projectiles must aim toward the camera crosshair")
		_key(KEY_SPACE, false)

		# The pilot and ship must retain their existing lifecycle integration.
		ship.exit_ship()
		_check(ship.on_foot and ship.pilot.active, "Leaving the ship must activate the pilot")
		_check(not ship.is_in_group("player") and ship.pilot.is_in_group("player"), "Leaving must transfer the player group")
		var parked_count := _player_bullets().size()
		_key(KEY_SPACE, true)
		ship._process(0.2)
		_check(_player_bullets().size() == parked_count, "An unoccupied ship must not fire")
		_key(KEY_SPACE, false)
		contact.global_position = ship.pilot.global_position + camera.global_basis.x * 40.0
		hud.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(not hud._radar._pings.has(contact.get_instance_id()), "On-foot radar must use its shorter range")
		ship.pilot.global_position += Vector3.ONE * 100.0
		ship.wreck()
		_check(hull.collision_layer == 0, "An empty wreck must stop blocking the pilot")
		gm.restart_game()
		_check(not ship.on_foot and not ship.wrecked and ship.enabled, "Restart must restore the occupied ship")
		_check(hull.collision_layer == Layers.SHIP_HULL, "Restart must restore hull collision")
		_check(ship.is_in_group("player") and not ship.pilot.active, "Restart must restore player ownership")
		_check(gm.spawner.enemies_left == 100, "Both missions must restart with 50 fighters and 50 robots")
		game.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		print("Component smoke complete: ", GameMode.title)

	if _failures == 0:
		print("PASS: ship components and both mission lifecycles")
	get_tree().quit(0 if _failures == 0 else 1)


func _player_bullets() -> Array[Node]:
	return get_tree().get_nodes_in_group("bullets").filter(func(node: Node) -> bool:
		return node is Bullet and node.from_player and not node.from_ally)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
