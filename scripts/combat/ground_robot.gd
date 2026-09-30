class_name GroundRobot
extends Enemy

# T-800 style walker that lives on the planet surface. It walks over the
# curved ground toward the spot under the player, stops at a comfortable
# range, turns to face them, raises its cannon arm and fires. The walk is
# animated in code (WalkerRig) by swinging the joints of ground_robot.glb.
# Hunting robots also go after the player's land teammates if they're nearer.

const MODEL := preload("res://assets/models/ground_robot.glb")
# Height the model is exported at.
const MODEL_HEIGHT := 3.4

@export_group("Walker")
## Standing height: the same as the pilot on foot (the ship towers over both).
@export var height := 0.19
## Stops walking when the player is this close along the ground.
@export var stop_distance := 2.5
## Only fires when facing within this many degrees of the player.
@export var fire_facing := 25.0
## Stride cycles (in radians) per unit walked.
@export var stride_rate := 24.0
@export var hip_swing := 26.0
@export var knee_bend := 45.0
@export var arm_swing := 18.0
## Idle robots wander this far from where they stand.
@export var wander_radius := 1.5
## Idle robots further than this from the player stand still (nobody's there to see).
@export var wander_view_distance := 120.0

var _rig: WalkerRig
var _pause := 0.0
# Fighting distance for this robot (a bit different for each), and the
# sidestep it's doing: -1 left, 1 right, 0 holding still for a moment.
var _hold := 0.0
var _strafe := 0.0
var _strafe_timer := 0.0
# Speed the legs are animated for this frame (wandering is slower than hunting).
var _stride_speed := 0.0


func _build_visual() -> void:
	var model := MODEL.instantiate() as Node3D
	model.name = "RobotModel"
	model.scale = Vector3.ONE * (height / MODEL_HEIGHT)
	$Visual.add_child(model)
	_rig = WalkerRig.new(model)
	_hold = stop_distance * randf_range(1.0, 1.8)
	_rig.stride_rate = stride_rate
	_rig.hip_swing = hip_swing
	_rig.knee_bend = knee_bend
	_rig.arm_swing = arm_swing


# While the player is up in the air, every robot in the battle fights the
# troopers; once the player lands, most of them turn on the player.
func _player_out_of_reach(p: Node3D) -> bool:
	return Planet.instance != null and Planet.instance.altitude(p.global_position) > 5.0


# Hunting robots fight the player's land teammates too.
func _ally_group() -> String:
	return "allies_ground"


# Person-sized, walking pace; they take two hits.
func configure(level: int) -> void:
	var w := maxi(0, level - 1)
	speed = minf(0.45 + 0.03 * w, 0.75)
	turn_rate = minf(90.0 + 10.0 * w, 180.0)
	fire_interval = maxf(2.6 * pow(0.9, w), 1.0)
	aim_spread = maxf(2.0 - 0.15 * w, 0.8)
	fire_range = 7.0
	health = 2
	score_value = 150 + 25 * w


func _process(delta: float) -> void:
	_find_target()
	var planet := Planet.instance
	if player == null or dead or planet == null:
		return
	if not attacking:
		_wander(planet, delta)
		return
	_stride_speed = speed

	var pos := global_position
	var up := planet.up_at(pos)
	var to_player := player.global_position - pos
	var flat := to_player - up * to_player.dot(up)
	var forward := -global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()

	var desired := flat.normalized() if flat.length_squared() > 0.01 else forward
	# Keep a little space from other robots so they don't walk into each other.
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not other is GroundRobot or not (other as Enemy).attacking:
			continue
		var away := pos - (other as Node3D).global_position
		away -= up * away.dot(up)
		var d := away.length()
		if d > 0.001 and d < separation_radius:
			desired += away / d * (1.0 - d / separation_radius) * 1.5

	var turn := forward.signed_angle_to(desired, up)
	var step := deg_to_rad(turn_rate) * delta
	forward = forward.rotated(up, clampf(turn, -step, step))

	# Close in to its fighting distance, then keep moving: sidestep around
	# the target (switching direction now and then), backing off if too close.
	var dist := flat.length()
	var move := Vector3.ZERO
	if dist > _hold:
		move = forward
	else:
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(1.0, 2.6)
			_strafe = [-1.0, 1.0, -1.0, 1.0, 0.0][randi() % 5]
		move = forward.cross(up) * _strafe * 0.7
		if dist < _hold * 0.6:
			move -= forward * 0.6
	var walking := move.length_squared() > 0.01
	if walking:
		pos += move.normalized() * speed * minf(move.length(), 1.0) * delta
	# Stay on the ground: feet on the surface, standing straight up from it.
	up = planet.up_at(pos)
	pos = planet.global_position + up * planet.radius
	forward = (forward - up * forward.dot(up)).normalized()
	global_transform = Transform3D(Basis.looking_at(forward, up), pos)

	_rig.animate(delta, walking, _stride_speed, to_player, up)

	fire_timer -= delta
	var game_over := GameManager.instance != null and GameManager.instance.is_game_over
	var facing := absf(rad_to_deg(forward.signed_angle_to(flat, up))) < fire_facing
	# Never shoot at a player that's below the horizon (through the planet).
	var in_sight := to_player.normalized().dot(up) > -0.1
	if not game_over and fire_timer <= 0.0 and to_player.length() < fire_range and facing and in_sight:
		_fire()
		fire_timer = fire_interval * randf_range(0.8, 1.2)


# Not hunting: stroll between random spots near home, pausing at each.
func _wander(planet: Planet, delta: float) -> void:
	if global_position.distance_to(player.global_position) > wander_view_distance:
		return
	var pos := global_position
	var up := planet.up_at(pos)
	var forward := -global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	if _waypoint == Vector3.ZERO:
		_pick_waypoint(planet)
	var to := _waypoint - pos
	to -= up * to.dot(up)
	var walking := false
	if to.length() < 0.08:
		_pause -= delta
		if _pause <= 0.0:
			_pick_waypoint(planet)
	else:
		walking = true
		var turn := forward.signed_angle_to(to, up)
		var step := deg_to_rad(turn_rate) * delta
		forward = forward.rotated(up, clampf(turn, -step, step))
		pos += forward * speed * 0.5 * delta
	up = planet.up_at(pos)
	pos = planet.global_position + up * planet.radius
	forward = (forward - up * forward.dot(up)).normalized()
	global_transform = Transform3D(Basis.looking_at(forward, up), pos)
	_stride_speed = speed * 0.5
	_rig.animate(delta, walking, _stride_speed, forward, up)


func _pick_waypoint(planet: Planet) -> void:
	var up := planet.up_at(home)
	var side := FxParticles.random_on_unit_sphere()
	side = (side - up * side.dot(up)).normalized()
	var p := home + side * randf_range(0.3, wander_radius)
	_waypoint = planet.global_position + planet.up_at(p) * planet.radius
	_pause = randf_range(1.5, 4.0)


# The robot's origin is at its feet; blow it up from the chest.
func _blast_point() -> Vector3:
	return global_position + global_basis.y * height * 0.55


func _fire() -> void:
	if _rig.muzzle != null:
		fire_point.global_position = _rig.muzzle.global_position
	super._fire()
