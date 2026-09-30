class_name AllyTrooper
extends Area3D

# A friendly soldier on the planet surface (ally_trooper.glb, walked with the
# same WalkerRig as the enemy robots and the same size as the pilot). While
# the player is down on the ground the AllySpawner deploys the nearest few:
# they stay close to the player and shoot the enemy robots that go after
# allies. Robots hunting the player are left for the player.
# The rest wander where they stand. Enemy robots shoot back, and enough hits
# kill one for good. The player's shots pass through them.

const MODEL := preload("res://assets/models/ally_trooper.glb")
const MODEL_HEIGHT := 3.4

var bullet_scene: PackedScene = load("res://scenes/bullet.tscn")

@export var height := 0.19
@export var max_health := 30
@export var speed := 0.5
@export var turn_rate := 140.0
@export var fire_interval := 1.8
## Shoots robots within this range...
@export var fire_range := 7.0
## ...and goes after robots attacking allies within this range of itself,
@export var engage_radius := 12.0
## ...and any robot at all this close to itself (self-defence).
@export var defend_radius := 5.0
@export var aim_spread := 2.5
@export var bullet_speed := 30.0
## When there's nothing to fight, it keeps within this distance of the player.
@export var follow_distance := 2.0
@export var wander_radius := 1.5
## Idle troopers further than this from the player stand still.
@export var wander_view_distance := 120.0

@onready var fire_point: Node3D = $FirePoint

var health := 0
var dead := false
# Deployed alongside the player (picked by the AllySpawner); otherwise idle.
var deployed := false
var home := Vector3.ZERO
var target: Enemy
var _rig: WalkerRig
var _waypoint := Vector3.ZERO
var _pause := 0.0
var _fire_timer := 0.0
var _retarget := 0.0
var _player: Node3D
# Where it stands around the player when there's nothing to shoot (an offset
# picked now and then, so the squad spreads out and moves around).
var _post := Vector3.ZERO
var _post_timer := 0.0
var _strafe := 0.0
var _strafe_timer := 0.0


func _ready() -> void:
	add_to_group("allies")
	add_to_group("allies_ground")
	health = max_health
	_fire_timer = randf_range(0.3, 1.0)
	var model := MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * (height / MODEL_HEIGHT)
	$Visual.add_child(model)
	_rig = WalkerRig.new(model)


func _process(delta: float) -> void:
	if dead:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var planet := Planet.instance
	if player == null or planet == null:
		return
	_player = player
	if not deployed:
		_wander(planet, player, delta)
		return

	_retarget -= delta
	if _retarget <= 0.0 or not _valid(target):
		_retarget = 0.5
		target = _pick_target()

	var pos := global_position
	var up := planet.up_at(pos)
	var goal: Vector3
	var stop := 0.25
	var aim := -global_basis.z
	var fighting := _valid(target)
	if fighting:
		goal = target.global_position
		stop = fire_range * 0.6
		aim = target.global_position + planet.up_at(target.global_position) * 0.1 - _muzzle_pos()
	else:
		# Take up a spot around the player, moving to a new one every few seconds.
		_post_timer -= delta
		if _post_timer <= 0.0 or _post == Vector3.ZERO:
			_post_timer = randf_range(3.0, 6.0)
			var pu := planet.up_at(player.global_position)
			var side := pu.cross(FxParticles.random_on_unit_sphere()).normalized()
			_post = side * randf_range(1.2, follow_distance * 1.8)
		goal = player.global_position + _post

	var to := goal - pos
	var flat := to - up * to.dot(up)
	var forward := -global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	var desired := flat.normalized() if flat.length_squared() > 0.0001 else forward
	# Keep a little space between troopers.
	for other in get_tree().get_nodes_in_group("allies_ground"):
		if other == self:
			continue
		var away := pos - (other as Node3D).global_position
		away -= up * away.dot(up)
		var d := away.length()
		if d > 0.001 and d < 0.5:
			desired += away / d * (1.0 - d / 0.5) * 1.5
	var turn := forward.signed_angle_to(desired, up)
	forward = forward.rotated(up, clampf(turn, -deg_to_rad(turn_rate) * delta, deg_to_rad(turn_rate) * delta))
	var move := Vector3.ZERO
	if flat.length() > stop:
		move = forward
	elif fighting:
		# In range: sidestep while shooting, switching direction now and then.
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(1.0, 2.4)
			_strafe = [-1.0, 1.0, 0.0][randi() % 3]
		move = forward.cross(up) * _strafe * 0.7
	var walking := move.length_squared() > 0.01
	if walking:
		pos += move.normalized() * speed * minf(move.length(), 1.0) * delta
	_stand(planet, pos, forward)
	_rig.animate(delta, walking, speed, aim, planet.up_at(global_position))

	_fire_timer -= delta
	var game_over := GameManager.instance != null and GameManager.instance.is_game_over
	if _valid(target) and not game_over and _fire_timer <= 0.0 and flat.length() < fire_range \
			and absf(rad_to_deg(forward.signed_angle_to(flat, up))) < 25.0:
		_fire(aim)
		_fire_timer = fire_interval * randf_range(0.8, 1.2)


# The nearest enemy robot that's attacking an ally (within engage_radius),
# or any robot that has come right up to this trooper (defend_radius).
# Other robots hunting the player are the player's to shoot.
func _pick_target() -> Enemy:
	var best: Enemy = null
	var best_d := engage_radius
	for e in Enemy.active(get_tree()):
		if not e is GroundRobot:
			continue
		var d := e.global_position.distance_to(global_position)
		var on_an_ally := is_instance_valid(e.player) and e.player.is_in_group("allies")
		if not on_an_ally and d > defend_radius:
			continue
		if d < best_d:
			best_d = d
			best = e
	return best


# Untyped on purpose: the target may already have been freed.
func _valid(e: Variant) -> bool:
	return is_instance_valid(e) and not (e as Enemy).dead and not (e as Enemy).is_queued_for_deletion()


func _muzzle_pos() -> Vector3:
	return _rig.muzzle.global_position if _rig.muzzle != null else fire_point.global_position


func _fire(dir: Vector3) -> void:
	var up := Planet.instance.up_at(global_position)
	var spread := deg_to_rad(randf_range(-aim_spread, aim_spread))
	dir = dir.normalized().rotated(up, spread)
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.size = 0.3
	bullet.from_ally = true
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = _muzzle_pos()
	bullet.launch(dir, bullet_speed)


# Feet on the ground, standing straight up from it, facing `forward`.
func _stand(planet: Planet, pos: Vector3, forward: Vector3) -> void:
	var up := planet.up_at(pos)
	pos = planet.global_position + up * planet.radius
	forward = (forward - up * forward.dot(up)).normalized()
	global_transform = Transform3D(Basis.looking_at(forward, up), pos)


# Not deployed: stroll between random spots near home, pausing at each.
func _wander(planet: Planet, player: Node3D, delta: float) -> void:
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
		forward = forward.rotated(up, clampf(turn, -deg_to_rad(turn_rate) * delta, deg_to_rad(turn_rate) * delta))
		pos += forward * speed * 0.4 * delta
	_stand(planet, pos, forward)
	_rig.animate(delta, walking, speed * 0.4, forward, planet.up_at(global_position))


func _pick_waypoint(planet: Planet) -> void:
	var up := planet.up_at(home)
	var side := FxParticles.random_on_unit_sphere()
	side = (side - up * side.dot(up)).normalized()
	var p := home + side * randf_range(0.3, wander_radius)
	_waypoint = planet.global_position + planet.up_at(p) * planet.radius
	_pause = randf_range(1.5, 4.0)


# Hit by enemy fire.
func take_hit(damage: int, point: Vector3) -> void:
	if dead:
		return
	health -= damage
	Explosion.spawn(point, Color(0.6, 0.8, 1.0), 0.15)
	if health <= 0:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	remove_from_group("allies")
	remove_from_group("allies_ground")
	Blast.spawn(global_position + global_basis.y * height * 0.55, 0.3)
	queue_free()
