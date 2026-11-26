class_name MissileTurret
extends Enemy

# Ground missile launcher. When an aircraft - the player's ship or an allied
# fighter - flies into its lock zone it swings round onto it, holds it in its
# sights for lock_time seconds (the HUD shows MISSILE LOCKING when it's the
# player) and fires a homing Missile from the next loaded tube. Each target
# is chased by one missile at a time; each tube reloads on its own. It can't
# lock onto anyone on foot or a parked ship. Allied fighters fight back when
# it goes after one of them. Armoured: 10 shots from the
# ship's guns or 20 from the pilot's rifle, and it goes up in a chain of
# explosions.
#
# Model (missile_turret.glb): TurretBase > TurretYaw (turns about Y) >
# TurretPitch (tilts about X, + = up) > Missile1..8 and FirePoint1..8.

const MODEL := preload("res://assets/models/missile_turret.glb")

static var all: Array[MissileTurret] = []

@export_group("Turret")
## The model is ~3.3 across its feet at 1; 2.9 makes it ~9.6 across, about
## four times the length of the player's ship (and ~5.2 tall).
@export var model_scale := 2.9
## Ships closer than this get locked onto.
@export var lock_radius := 300.0
## Seconds the ship must stay in its sights before it fires.
@export var lock_time := 2.0
## Seconds after a launch before it can start locking again.
@export var reload_time := 6.0
## Seconds before an emptied tube is loaded again.
@export var tube_reload := 14.0
## How fast the launcher swings round, in degrees per second.
@export var aim_speed := 80.0
## Missiles are stretched this much longer than modelled (same thickness).
@export var missile_length := 2.5

@export_group("Armour")
## Shots from the ship's guns it takes to destroy...
@export var ship_shots_to_kill := 10
## ...and shots from the pilot's rifle on foot.
@export var foot_shots_to_kill := 20
## Seconds of explosions going off around it before the final blast.
@export var death_time := 1.6

# 0..1 while locking on (drives the HUD warning when it's the player).
var lock_progress := 0.0
# The aircraft it's locking onto or has fired at (the player's ship or an
# allied fighter), or null.
var lock_target: Node3D
var _yaw: Node3D
var _pitch: Node3D
var _tubes: Array[Dictionary] = []
var _next_tube := 0
var _cooldown := 0.0
var _missile: Missile


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


func _build_visual() -> void:
	var model := MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale
	$Visual.add_child(model)
	_yaw = model.find_child("TurretYaw", true, false) as Node3D
	_pitch = model.find_child("TurretPitch", true, false) as Node3D
	for i in range(1, 9):
		# Stretch each racked missile backward into its tube, so its nose
		# still sticks out the same amount (the nose is at z = -0.22 in the
		# missile's own space, forward being -Z).
		var rack := model.find_child("Missile%d" % i, true, false) as Node3D
		rack.scale.z *= missile_length
		rack.position.z += 0.22 * (missile_length - 1.0)
		_tubes.append({
			"missile": model.find_child("Missile%d" % i, true, false),
			"fire": model.find_child("FirePoint%d" % i, true, false),
			"reload": 0.0,
		})
	_yaw.rotation.y = randf() * TAU


# Health is counted in rifle shots: a ship's shot does foot/ship times as much.
func configure(level: int) -> void:
	var w := maxi(0, level - 1)
	health = foot_shots_to_kill
	lock_time = maxf(2.0 - 0.1 * w, 1.2)
	score_value = 300 + 50 * w


# Locking on (and no missile, from any turret, already chasing the ship).
var locking: bool:
	get:
		return lock_progress > 0.0 and is_instance_valid(lock_target) and lock_target is PlayerShipController \
			and not Missile.chasing(lock_target)


# Turrets only ever go after the player's ship, never allies.
func _ally_group() -> String:
	return ""


func _missile_in_flight() -> bool:
	return is_instance_valid(_missile) and _missile.homing


func _process(delta: float) -> void:
	_find_target()
	if dead:
		return
	for tube in _tubes:
		if tube.reload > 0.0:
			tube.reload -= delta
			if tube.reload <= 0.0:
				(tube.missile as Node3D).visible = true
	_cooldown -= delta

	var target := _choose_target()
	if target != lock_target:
		lock_progress = 0.0
	lock_target = target
	attacking = target != null

	# Only one missile chases any one target at a time, across all turrets.
	var on_target := target != null and _aim_at(target.global_position, delta)
	if on_target and not Missile.chasing(target) and _cooldown <= 0.0 and _has_missile():
		lock_progress = minf(1.0, lock_progress + delta / lock_time)
		if lock_progress >= 1.0:
			_launch(target)
	else:
		lock_progress = maxf(0.0, lock_progress - delta / lock_time * 2.0)


# An aircraft in the lock zone: the player's ship in flight, or an allied
# fighter. Sticks with its current target while that's still in the zone,
# otherwise takes the nearest.
func _choose_target() -> Node3D:
	if GameManager.instance != null and GameManager.instance.is_game_over:
		return null
	if _lockable(lock_target):
		return lock_target
	var best: Node3D = null
	var best_d := lock_radius
	var ship := GameManager.instance.player if GameManager.instance != null else null
	if _lockable(ship):
		best_d = ship.global_position.distance_to(global_position)
		best = ship
	for a in get_tree().get_nodes_in_group("allies_air"):
		var d := (a as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = a
	return best


# Untyped on purpose: the old target may already have been freed.
func _lockable(n: Variant) -> bool:
	if not is_instance_valid(n) or (n as Node3D).global_position.distance_to(global_position) >= lock_radius:
		return false
	var ship := n as PlayerShipController
	if ship != null:
		return ship.enabled and not ship.on_foot and ship.state != PlayerShipController.State.LANDED
	return n is AllyFighter and not (n as AllyFighter).dead


# Turn and tilt toward `point`; true once it's roughly lined up.
func _aim_at(point: Vector3, delta: float) -> bool:
	var step := deg_to_rad(aim_speed) * delta
	var base := _yaw.get_parent() as Node3D
	var local := base.global_transform.affine_inverse() * point
	var yaw_goal := atan2(-local.x, -local.z)
	_yaw.rotation.y = rotate_toward(_yaw.rotation.y, yaw_goal, step)
	var rel := _yaw.global_transform.affine_inverse() * point - _pitch.position
	var pitch_goal := clampf(atan2(rel.y, Vector2(rel.x, rel.z).length()), deg_to_rad(-5.0), deg_to_rad(80.0))
	_pitch.rotation.x = rotate_toward(_pitch.rotation.x, pitch_goal, step)
	return absf(angle_difference(_yaw.rotation.y, yaw_goal)) < deg_to_rad(8.0) \
		and absf(_pitch.rotation.x - pitch_goal) < deg_to_rad(8.0)


func _has_missile() -> bool:
	for tube in _tubes:
		if tube.reload <= 0.0:
			return true
	return false


# Fire from the next loaded tube: that missile leaves the rack and flies.
func _launch(target: Node3D) -> void:
	for n in _tubes.size():
		var i := (_next_tube + n) % _tubes.size()
		var tube := _tubes[i]
		if tube.reload > 0.0:
			continue
		var rack := tube.missile as Node3D
		var body := rack.duplicate() as Node3D
		body.visible = true
		rack.visible = false
		tube.reload = tube_reload
		_missile = Missile.launch((tube.fire as Node3D).global_transform, body, target)
		_next_tube = (i + 1) % _tubes.size()
		lock_progress = 0.0
		_cooldown = reload_time
		return


func hit(damage: int, hit_point: Vector3, bullet: Bullet = null) -> void:
	if dead:
		return
	var from_ship := bullet == null or not bullet.from_pilot
	var amount := damage * (int(float(foot_shots_to_kill) / float(ship_shots_to_kill)) if from_ship else 1)
	super.hit(amount, hit_point, bullet)


# Goes up in a string of explosions around the launcher, then one big blast.
func die(killed_by_player: bool) -> void:
	if dead:
		return
	dead = true
	attacking = false
	lock_progress = 0.0
	remove_from_group("enemies")
	collision_layer = 0
	if killed_by_player and GameManager.instance != null:
		GameManager.instance.register_kill(score_value)
	var up := global_basis.y
	var center := _blast_point()
	var pops := 5
	for i in pops:
		var offset := FxParticles.random_inside_unit_sphere() * model_scale * 1.2
		offset += up * randf_range(-0.5, 0.5) * model_scale
		get_tree().create_timer(death_time * float(i) / pops).timeout.connect(
			Blast.spawn.bind(center + offset, blast_size * randf_range(0.35, 0.6)))
	await get_tree().create_timer(death_time).timeout
	Blast.spawn(center, blast_size * 1.3)
	queue_free()


# The launcher, not the base, blows up.
func _blast_point() -> Vector3:
	return global_position + global_basis.y * 1.5 * model_scale


# Warm-up helper for the loading screen: fire one tube with no target.
func test_fire() -> void:
	var tube := _tubes[0]
	var body := (tube.missile as Node3D).duplicate() as Node3D
	Missile.launch((tube.fire as Node3D).global_transform, body, null)
