class_name PlayerOnFoot
extends Area3D

# The pilot out of the ship, seen in first person with a gun in hand. Walks
# on the planet with W/A/S/D relative to the view, Shift sprints (running on
# the ship's boost meter), Space jumps, left click fires, right click aims
# down the sights (the camera zooms). E next to the ship climbs back in.
# Enemies target whichever of ship or pilot is in the "player" group.
#
# Bailing out of the ship in flight ejects the pilot out of its top, keeping the
# ship's speed. The suit has boosters: under gravity, hold Space to climb
# (it drains the boost meter; empty, you fall) and W/A/S/D steer in the air.
# Out in space there's no gravity: W/A/S/D fly along the view, Space rises,
# Ctrl (or C) sinks, Shift boosts, and letting go the suit brakes to a stop.
#
# Hitting the ground faster than safe_landing_speed is fatal. Q in the air
# under gravity opens the pilot's own parachute (not the ship's), which slows
# the fall to a safe speed; the jetpack helps too. The parachute cuts away on
# landing (or with C) and stays on the ground; a new one is ready
# Parachute.COOLDOWN seconds later.
#
# The ship is solid: the pilot can't pass through it, but can stand, walk and
# jump on top of it.
#
# Scale: the pilot is person-sized next to the ship (about 0.18 units tall
# against the ship's 2.4 length, so the ship towers over them), and the
# walking robots are the same height. Speeds, jump and the gun are all scaled
# to match, so it feels like normal walking.

var bullet_scene: PackedScene = load("res://scenes/bullet.tscn")

@export_group("Movement")
@export var walk_speed := 0.5
@export var sprint_speed := 0.9
@export var acceleration := 4.0
@export var jump_speed := 0.6
@export var gravity_pull := 1.6
## Height of the pilot's center above the ground (eyes are higher, see CameraFollow.eye_height).
@export var stand_height := 0.09
## How far beside the ship the pilot appears when climbing out.
@export var exit_offset := 2.0
## Close enough to the ship to press E and climb in.
@export var board_distance := 3.0

@export_group("Suit Boosters")
## Speed of the kick out of the top of the ship when bailing out.
@export var eject_speed := 6.0
## Flying speed on the boosters (in the air and in space), and with Shift.
@export var jet_speed := 3.0
@export var jet_boost_speed := 6.0
## How quickly the boosters change the pilot's speed. Any extra speed (carried
## out of the ship) bleeds off at this rate too.
@export var jet_acceleration := 5.0
## Upward push while holding Space under gravity (must beat gravity_pull).
@export var jet_lift := 4.5
## Fastest fall under gravity.
@export var max_fall_speed := 8.0

@export_group("Parachute")
## Landing faster than this (straight down) kills the pilot. A jump lands at
## about 0.6; a free fall from about 8 units up is already too fast.
@export var safe_landing_speed := 5.0
## With the parachute open the pilot sinks at this speed...
@export var chute_fall_speed := 1.2
## ...and drifts sideways no faster than this.
@export var chute_glide_speed := 1.5
## How hard the open parachute slows the pilot, per second.
@export var chute_drag := 6.0
@export var chute_color := Color(0.2, 0.55, 1.0)

@export_group("Gun")
@export var fire_rate := 7.0
@export var bullet_speed := 40.0
## The gun is modelled at 1 = a big rifle; this shrinks it to the pilot's size.
@export var gun_scale := 0.1
## Where the gun sits in view (camera space, before gun_scale) from the hip, and aiming down the sights.
@export var hip_position := Vector3(0.2, -0.2, -0.45)
@export var aim_position := Vector3(0.0, -0.128, -0.6)

var ship: PlayerShipController
var active := false
var velocity := Vector3.ZERO
var sprinting := false
var on_ground := true

var health: PlayerHealth:
	get:
		return ship.health if ship != null else null

var near_ship: bool:
	get:
		return ship != null and not ship.wrecked and global_position.distance_to(ship.global_position) < board_distance

# Out in space, beyond the planet's pull.
var zero_g: bool:
	get:
		return ship != null and ship.gravity_weight(global_position) <= 0.0

# In the air under gravity, holding Space.
var jetting := false

# The pilot's parachute while it's open, and the wait before a new one.
var chute: Parachute
var chute_cooldown := 0.0

# In the air under gravity, parachute packed and ready.
var can_deploy_chute: bool:
	get:
		return chute == null and chute_cooldown <= 0.0 and not on_ground and not zero_g

var _cam: CameraFollow
# Sweeps the pilot's body against the ship's hull.
var _hull_query: PhysicsShapeQueryParameters3D
var _touch_query: PhysicsShapeQueryParameters3D
# Last move ended resting on the top of the ship.
var _on_hull := false
var _gun: Node3D
var _muzzle: Node3D
var _fire_cooldown := 0.0
var _recoil := 0.0
var _bob := 0.0


func _ready() -> void:
	_set_active(false)


func step_out(from_ship: PlayerShipController) -> void:
	ship = from_ship
	var planet := Planet.instance
	_cam = get_viewport().get_camera_3d() as CameraFollow
	if ship.state == PlayerShipController.State.LANDED:
		# Parked: step down beside the ship.
		var up := planet.up_at(ship.global_position)
		var side := ship.global_basis.x - up * ship.global_basis.x.dot(up)
		var ground := planet.up_at(ship.global_position + side.normalized() * exit_offset)
		global_position = planet.global_position + ground * (planet.radius + stand_height)
		velocity = Vector3.ZERO
		on_ground = true
	else:
		# Flying: eject out of the top, keeping the ship's speed.
		var top := ship.global_basis.y
		global_position = ship.global_position + top * (ship.hull_top + stand_height + 0.05)
		velocity = ship.velocity + top * eject_speed
		on_ground = false
		_cam.shake(0.5)
	if _gun == null:
		_build_gun()
	_cam.target = self
	_cam.first_person = true
	_set_active(true)


# Back into the ship (also used by restart, which puts the pilot in at once).
func climb_in() -> void:
	if not active:
		return
	_cut_chute()
	_set_active(false)
	ship.boosting = false
	ship.board()
	if _cam != null:
		_cam.first_person = false
		_cam.target = ship


# Builds the gun ahead of time and shows it, so the loading screen can get
# its materials compiled before the first time the pilot climbs out.
func prepare_gun(camera: CameraFollow) -> void:
	_cam = camera
	if _gun == null:
		_build_gun()
	_gun.visible = true


func hide_gun() -> void:
	if _gun != null:
		_gun.visible = active


func _set_active(on: bool) -> void:
	active = on
	collision_layer = Layers.PLAYER if on else 0
	if on:
		add_to_group("player")
	elif is_in_group("player"):
		remove_from_group("player")
	if _gun != null:
		_gun.visible = on


func _unhandled_input(event: InputEvent) -> void:
	if not active or not _can_act():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_E:
			if near_ship:
				climb_in()
				get_viewport().set_input_as_handled()
		KEY_Q:
			if can_deploy_chute:
				chute = Parachute.deploy(_chute_anchor(), Planet.instance.up_at(global_position),
					0.6, 1.0, chute_color, 0.0015)
				get_viewport().set_input_as_handled()
		KEY_C:
			if chute != null:
				_cut_chute()
				get_viewport().set_input_as_handled()
		KEY_SPACE:
			if on_ground and not zero_g:
				var up := Planet.instance.up_at(global_position)
				velocity += up * jump_speed
				on_ground = false


func _can_act() -> bool:
	var gm := GameManager.instance
	return ship != null and ship.enabled and not (gm != null and gm.is_game_over)


func _process(delta: float) -> void:
	if chute == null:
		chute_cooldown = maxf(0.0, chute_cooldown - delta)
	if not active or not _can_act():
		return
	_move(delta)
	_update_chute()
	_shoot(delta)
	_update_gun(delta)


# A new parachute right away (restarting the game).
func reset_chute() -> void:
	_cut_chute()
	chute_cooldown = 0.0


# Let the parachute go (it drifts down and stays on the ground).
func _cut_chute() -> void:
	if chute == null:
		return
	chute.cut()
	chute = null
	chute_cooldown = Parachute.COOLDOWN


# Keeps the canopy overhead; cuts it on landing or out in space.
func _update_chute() -> void:
	if chute == null:
		return
	if on_ground or zero_g:
		_cut_chute()
		return
	chute.hold(_chute_anchor(), Planet.instance.up_at(global_position), velocity)


# The harness, at the pilot's shoulders.
func _chute_anchor() -> Vector3:
	return global_position + Planet.instance.up_at(global_position) * 0.06


func _read_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): input.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): input.x += 1.0
	return input.limit_length(1.0)


func _move(delta: float) -> void:
	var planet := Planet.instance
	var up := planet.up_at(global_position)
	var input := _read_input()

	# Walk along the ground in the direction the view faces (ignoring look up/down).
	var forward := -_cam.view_rotation.z
	forward -= up * forward.dot(up)
	forward = forward.normalized() if forward.length_squared() > 0.0001 else -global_basis.z
	var right := forward.cross(up)

	var horizontal_speed := 0.0
	if zero_g:
		_fly_zero_g(input, delta)
	elif on_ground:
		horizontal_speed = _walk(input, forward, right, up, delta)
	else:
		_fly_under_gravity(input, forward, right, up, delta)
	ship.update_boost_meter(delta)

	# How fast the pilot is coming down, before anything stops them.
	var fall_speed := -velocity.dot(up)
	var pos := _slide(global_position, velocity * delta, up)
	var new_up := planet.up_at(pos)
	velocity = Quaternion(up, new_up) * velocity if up.dot(new_up) < 0.9999999 else velocity
	if planet.altitude(pos) > ship.max_altitude:
		pos = planet.global_position + new_up * (planet.radius + ship.max_altitude)
		velocity -= new_up * maxf(velocity.dot(new_up), 0.0)
	var was_airborne := not on_ground
	var on_planet := planet.altitude(pos) <= stand_height
	on_ground = on_planet or _on_hull
	if on_planet:
		pos = planet.global_position + new_up * (planet.radius + stand_height)
		var into := velocity.dot(new_up)
		if into < 0.0:
			velocity -= new_up * into
	if on_ground and was_airborne and fall_speed > safe_landing_speed:
		global_position = pos
		_hard_landing()
		return
	global_transform = Transform3D(Basis.looking_at(forward, new_up), pos)

	var moving := on_ground and horizontal_speed > 0.5
	_bob = _bob + delta * horizontal_speed * 1.6 if moving else move_toward(_bob, roundf(_bob / PI) * PI, delta * 4.0)


# Moves by `motion`, sliding along the ship's hull instead of passing through
# it. Resting on a surface that faces up (the top of the ship) counts as
# standing on the ground.
func _slide(from: Vector3, motion: Vector3, up: Vector3) -> Vector3:
	_on_hull = false
	if ship == null or ship.wrecked:
		return from + motion
	if _hull_query == null:
		var body := SphereShape3D.new()
		body.radius = stand_height
		_hull_query = PhysicsShapeQueryParameters3D.new()
		_hull_query.shape = body
		_hull_query.collision_mask = Layers.SHIP_HULL
		_hull_query.collide_with_areas = false
		_hull_query.collide_with_bodies = true
		# Finds where the body touches: a touch bigger, so a body resting
		# exactly on the hull still reports the contact.
		var touch := SphereShape3D.new()
		touch.radius = stand_height + 0.004
		_touch_query = PhysicsShapeQueryParameters3D.new()
		_touch_query.shape = touch
		_touch_query.collision_mask = Layers.SHIP_HULL
		_touch_query.collide_with_areas = false
		_touch_query.collide_with_bodies = true
	var space := get_world_3d().direct_space_state
	var pos := from
	for i in 3:
		if motion.length_squared() < 1e-12:
			break
		_hull_query.transform = Transform3D(Basis.IDENTITY, pos)
		_hull_query.motion = motion
		var hit := space.cast_motion(_hull_query)
		if hit.is_empty() or hit[1] >= 1.0:
			pos += motion
			break
		var info := _touch(space, pos + motion * hit[1])
		if info.is_empty():
			pos += motion
			break
		# Away from the touching point is out of the hull.
		var normal := (pos + motion * hit[1] - (info.point as Vector3)).normalized()
		if hit[1] <= 0.0 and motion.dot(normal) >= 0.0:
			pos += motion  # already touching and moving away
			break
		pos += motion * hit[0] + normal * 0.002
		var rest := motion * (1.0 - hit[0])
		rest -= normal * minf(rest.dot(normal), 0.0)
		var into := velocity.dot(normal)
		if into < 0.0:
			velocity -= normal * into
		if normal.dot(up) > 0.6:
			_on_hull = true
		motion = rest
	# Resting on top (the last contact pushed the body just clear of it):
	# feel a little way down to stay standing.
	if not _on_hull and velocity.dot(up) <= 0.01:
		_hull_query.transform = Transform3D(Basis.IDENTITY, pos)
		_hull_query.motion = -up * 0.01
		var below := space.cast_motion(_hull_query)
		if not below.is_empty() and below[1] < 1.0:
			var at := pos - up * 0.01 * below[1]
			var info := _touch(space, at)
			if not info.is_empty() and (at - (info.point as Vector3)).normalized().dot(up) > 0.6:
				_on_hull = true
	return pos


# Where the body centered at `at` touches the hull (empty if it doesn't).
func _touch(space: PhysicsDirectSpaceState3D, at: Vector3) -> Dictionary:
	_touch_query.transform = Transform3D(Basis.IDENTITY, at)
	return space.get_rest_info(_touch_query)


# Hit the ground too fast: fatal.
func _hard_landing() -> void:
	var gm := GameManager.instance
	if gm == null or gm.is_game_over:
		return
	velocity = Vector3.ZERO
	gm.death_reason = "YOU HIT THE GROUND TOO HARD"
	gm.player_hit(gm.health)


# On the ground: walk, sprint on the boost meter. Returns the walking speed.
func _walk(input: Vector2, forward: Vector3, right: Vector3, up: Vector3, delta: float) -> float:
	jetting = false
	# Sprint is the ship's boost, on legs: same meter, same lockout when it runs dry.
	var wants_sprint := Input.is_physical_key_pressed(KEY_SHIFT) and input.y > 0.0
	ship.boosting = wants_sprint and not ship.boost_locked
	sprinting = ship.boosting

	var speed := sprint_speed if sprinting else walk_speed
	var target := (forward * input.y + right * input.x) * speed
	var vertical := velocity.dot(up)
	var horizontal := velocity - up * vertical
	horizontal = horizontal.move_toward(target, acceleration * delta)
	vertical -= gravity_pull * ship.gravity_weight(global_position) * delta
	velocity = horizontal + up * vertical
	return horizontal.length()


# In the air under gravity: W/A/S/D steer on the boosters, holding Space
# climbs (on the boost meter), otherwise the pilot falls.
func _fly_under_gravity(input: Vector2, forward: Vector3, right: Vector3, up: Vector3, delta: float) -> void:
	var boost := Input.is_physical_key_pressed(KEY_SHIFT) and input != Vector2.ZERO
	jetting = Input.is_physical_key_pressed(KEY_SPACE) and not ship.boost_locked
	ship.boosting = (boost or jetting) and not ship.boost_locked
	sprinting = ship.boosting

	var speed := jet_boost_speed if boost and ship.boosting else jet_speed
	var target := (forward * input.y + right * input.x) * speed
	var vertical := velocity.dot(up)
	var horizontal := velocity - up * vertical
	horizontal = horizontal.move_toward(target, jet_acceleration * delta)

	vertical -= gravity_pull * ship.gravity_weight(global_position) * delta
	if jetting:
		vertical += jet_lift * delta
	# Speed carried out of the ship bleeds off; the fall tops out.
	if vertical > jet_speed:
		vertical = move_toward(vertical, jet_speed, jet_acceleration * delta)
	vertical = maxf(vertical, -max_fall_speed)
	velocity = horizontal + up * vertical
	if chute != null:
		velocity = Parachute.drag(chute, velocity, up, chute_fall_speed, chute_glide_speed, chute_drag, delta)


# Out in space: fly anywhere along the view. With nothing held the suit
# brakes to a stop.
func _fly_zero_g(input: Vector2, delta: float) -> void:
	jetting = false
	var rise := 0.0
	if Input.is_physical_key_pressed(KEY_SPACE): rise += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C): rise -= 1.0
	var dir := _cam.view_rotation * Vector3(input.x, rise, -input.y)
	dir = dir.limit_length(1.0)
	ship.boosting = Input.is_physical_key_pressed(KEY_SHIFT) and dir != Vector3.ZERO and not ship.boost_locked
	sprinting = ship.boosting
	var speed := jet_boost_speed if ship.boosting else jet_speed
	velocity = velocity.move_toward(dir * speed, jet_acceleration * delta)


func _shoot(delta: float) -> void:
	_fire_cooldown -= delta
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _cam.mouse_can_fire and _fire_cooldown <= 0.0:
		_fire()
		_fire_cooldown = 1.0 / fire_rate


func _fire() -> void:
	var dir := (_cam.aim_point() - _muzzle.global_position).normalized()
	# Start the shot a little past the muzzle so it doesn't flash across the sights.
	var origin := _muzzle.global_position + dir * 0.3
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.size = 0.3
	bullet.from_pilot = true
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin
	bullet.launch(dir, bullet_speed)
	_recoil = 1.0
	_cam.shake(0.05)


# Gun sways with the walk, kicks back on each shot and slides to the center
# of the view while aiming.
func _update_gun(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, delta * 8.0)
	var aim := smoothstep(0.0, 1.0, _cam.zoom_blend)
	var sway := (1.0 - aim * 0.8) * (1.6 if sprinting else 1.0)
	var bob := Vector3(cos(_bob) * 0.012, -absf(sin(_bob)) * 0.018, 0.0) * sway
	_gun.position = (hip_position.lerp(aim_position, aim) + bob + Vector3(0, 0.01, 0.06) * _recoil) * gun_scale
	_gun.rotation = Vector3(deg_to_rad(6.0) * _recoil, 0.0, 0.0)


# A chunky plasma rifle made from simple shapes, parented to the camera.
func _build_gun() -> void:
	var gunmetal := StandardMaterial3D.new()
	# Only half metallic: there's little in space for fully metal parts to
	# reflect, so they'd read as flat black.
	gunmetal.albedo_color = Color(0.24, 0.25, 0.28)
	gunmetal.metallic = 0.5
	gunmetal.roughness = 0.4
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.7, 0.72, 0.76)
	chrome.metallic = 0.6
	chrome.roughness = 0.25
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.3, 0.8, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.4, 0.85, 1.0)
	glow.emission_energy_multiplier = 4.0

	_gun = Node3D.new()
	_gun.name = "Gun"
	_cam.add_child(_gun)
	_gun_box(Vector3(0.07, 0.09, 0.34), Vector3(0, 0, -0.02), gunmetal)                  # receiver
	_gun_box(Vector3(0.05, 0.13, 0.06), Vector3(0, -0.1, 0.08), gunmetal, -15.0)          # grip
	_gun_box(Vector3(0.04, 0.12, 0.06), Vector3(0, -0.1, -0.08), chrome, 8.0)             # magazine
	_gun_box(Vector3(0.06, 0.07, 0.16), Vector3(0, -0.01, 0.2), gunmetal)                 # stock
	_gun_box(Vector3(0.016, 0.03, 0.05), Vector3(0, 0.06, 0.08), chrome)                  # rear sight
	_gun_box(Vector3(0.012, 0.028, 0.02), Vector3(0, 0.058, -0.16), chrome)               # front sight
	_gun_box(Vector3(0.04, 0.012, 0.2), Vector3(0.036, 0.0, -0.05), glow)                 # power strip
	_gun_cylinder(0.034, 0.18, Vector3(0, 0.0, -0.26), gunmetal)                          # shroud
	_gun_cylinder(0.018, 0.2, Vector3(0, 0.0, -0.38), chrome)                             # barrel
	_gun_cylinder(0.026, 0.03, Vector3(0, 0.0, -0.47), glow)                              # muzzle ring
	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 0, -0.5)
	_gun.add_child(_muzzle)
	_gun.scale = Vector3.ONE * gun_scale
	_gun.position = hip_position * gun_scale


func _gun_box(size: Vector3, pos: Vector3, mat: Material, tilt := 0.0) -> void:
	var box := BoxMesh.new()
	box.size = size
	_gun_part(box, pos, mat, Vector3(deg_to_rad(tilt), 0, 0))


func _gun_cylinder(radius: float, length: float, pos: Vector3, mat: Material) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 16
	_gun_part(cyl, pos, mat, Vector3(deg_to_rad(90.0), 0, 0))


func _gun_part(mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(mi)
