class_name ShipWeapons
extends RefCounted

# Updated explicitly by the ship while occupied and enabled, preserving the
# controller's input order and pausing its cooldown while the pilot is outside.

var bullet_scene: PackedScene = load("res://scenes/bullet.tscn")
var fire_cooldown := 0.0


func update(ship: PlayerShipController, delta: float) -> void:
	fire_cooldown -= delta
	# Mouse only fires while the cursor is captured, so the click that re-captures it doesn't shoot.
	var mouse_fires := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and (ship.aim_camera == null or ship.aim_camera.mouse_can_fire)
	var wants_fire := mouse_fires or Input.is_physical_key_pressed(KEY_SPACE)

	if wants_fire and fire_cooldown <= 0.0:
		_fire(ship)
		fire_cooldown = 1.0 / maxf(0.01, ship.fire_rate)


func _fire(ship: PlayerShipController) -> void:
	if ship.fire_point == null:
		return
	# Aim at the crosshair, not just along the nose, so shots land where you're
	# looking even while the ship is still turning to catch up with the view.
	var origin := ship.fire_point.global_position
	var dir := -ship.fire_point.global_basis.z
	if ship.aim_camera != null:
		var to_aim := ship.aim_camera.aim_point() - origin
		if to_aim.length_squared() > 0.01:
			dir = to_aim.normalized()

	var bullet := bullet_scene.instantiate() as Bullet
	ship.get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin
	# Shots carry the ship's forward speed, so they don't lag behind while boosting.
	bullet.launch(dir, ship.bullet_speed + maxf(0.0, ship.velocity.dot(dir)))
