class_name AllyFighter
extends Area3D

# A friendly fighter, identical to the player's own ship. The AllySpawner
# makes the nearest few escorts: they race over to the player, fly around
# them, and dogfight the enemy fighters that go after allies. Enemies hunting
# the player are left for the player to shoot. The rest patrol. Enemy fighters shoot back
# (see Enemy._find_target), and enough hits bring one down for good. The
# player's shots pass through allies, and their kills aren't the player's.

var bullet_scene: PackedScene = load("res://scenes/bullet.tscn")

@export var max_health := 20
@export var speed := 7.5
@export var turn_rate := 95.0
@export var fire_interval := 1.1
@export var fire_range := 60.0
## Only fires when the target is within this many degrees of the nose.
@export var fire_cone := 10.0
@export var aim_spread := 4.5
@export var bullet_speed := 30.0
## Enemy fighters attacking allies within this distance of the player get engaged.
@export var engage_radius := 250.0
@export var break_off_distance := 7.0
@export var separation_radius := 5.0
@export var ground_avoid_height := 10.0
@export var patrol_radius := 80.0

@onready var fire_point: Node3D = $FirePoint

var health := 0
var dead := false
# Escorting the player (picked by the AllySpawner); otherwise patrolling.
var escorting := false
var home := Vector3.ZERO
# Place in the escort formation around the player (0..n).
var slot := 0
var target: Enemy
var _waypoint := Vector3.ZERO
var _fire_timer := 0.0
var _retarget := 0.0
var _break_off := 0.0
var _break_dir := Vector3.ZERO


func _ready() -> void:
	add_to_group("allies")
	add_to_group("allies_air")
	health = max_health
	_fire_timer = randf_range(0.5, 1.5)
	# Same colours as the player's ship (no tint).
	ShipModel.attach($Visual, ShipModel.PLAYER_THRUST_CORE, ShipModel.PLAYER_THRUST_TAIL)


func _process(delta: float) -> void:
	if dead:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var planet := Planet.instance
	if player == null or planet == null:
		return
	var pos := global_position
	var desired: Vector3
	var fly_speed := speed

	if escorting:
		_retarget -= delta
		if _retarget <= 0.0 or not _valid(target):
			_retarget = 0.5
			target = _pick_target(player)
		if _valid(target):
			desired = _attack(target, delta)
		else:
			# Hold station around the player: a ring of slots behind and around them.
			var up := planet.up_at(player.global_position)
			var ring := up.cross(Vector3.RIGHT).normalized().rotated(up, TAU * slot / 10.0)
			var station := player.global_position + ring * 25.0 + up * (8.0 + 4.0 * (slot % 3))
			desired = station - pos
		# Far away: race in, easing off as the gap closes.
		var gap := pos.distance_to(player.global_position)
		fly_speed = maxf(speed, (gap - 60.0) / 5.0)
	else:
		if _waypoint == Vector3.ZERO or pos.distance_to(_waypoint) < 10.0:
			_waypoint = planet.push_out(home + FxParticles.random_on_unit_sphere() * patrol_radius, ground_avoid_height * 3.0)
		desired = _waypoint - pos
		fly_speed = speed * 0.5

	desired = desired.normalized()
	for other in get_tree().get_nodes_in_group("allies_air"):
		if other == self:
			continue
		var away := pos - (other as Node3D).global_position
		var d := away.length()
		if d > 0.001 and d < separation_radius:
			desired += away / d * (1.0 - d / separation_radius) * 1.5
	var alt := planet.altitude(pos)
	if alt < ground_avoid_height:
		desired += planet.up_at(pos) * (1.0 - maxf(alt, 0.0) / ground_avoid_height) * 2.0

	if desired.length_squared() > 0.0001:
		var wanted := Rotations.look_rotation(desired, planet.up_at(pos))
		global_basis = Basis(Rotations.rotate_towards(global_basis.get_rotation_quaternion(), wanted, turn_rate * delta))
	global_position = planet.push_out(pos + -global_basis.z * fly_speed * delta, 1.0)


# The nearest enemy (within engage_radius of the player) that's attacking an
# ally: a fighter going after one, or a missile turret locking onto / firing
# at one. Ones hunting the player are the player's to shoot.
func _pick_target(player: Node3D) -> Enemy:
	var best: Enemy = null
	var best_d := engage_radius
	for e in Enemy.active(get_tree()):
		if e is GroundRobot:
			continue
		if e is MissileTurret:
			var lt := (e as MissileTurret).lock_target
			if not (is_instance_valid(lt) and lt.is_in_group("allies")):
				continue
		elif not (is_instance_valid(e.player) and e.player.is_in_group("allies")):
			continue
		var d := e.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


# Untyped on purpose: the target may already have been freed.
func _valid(e: Variant) -> bool:
	return is_instance_valid(e) and not (e as Enemy).dead and not (e as Enemy).is_queued_for_deletion()


# Chase and shoot, breaking off after a close pass like the enemies do.
func _attack(e: Enemy, delta: float) -> Vector3:
	var to := e.global_position - global_position
	var dist := to.length()
	var forward := -global_basis.z
	if _break_off <= 0.0 and dist < break_off_distance:
		_break_off = randf_range(1.2, 2.0)
		_break_dir = (forward + FxParticles.random_inside_unit_sphere() * 0.6).normalized()
	_fire_timer -= delta
	if _break_off > 0.0:
		_break_off -= delta
		return _break_dir
	var game_over := GameManager.instance != null and GameManager.instance.is_game_over
	if not game_over and _fire_timer <= 0.0 and dist < fire_range and rad_to_deg(forward.angle_to(to)) < fire_cone:
		_fire(to.normalized())
		_fire_timer = fire_interval * randf_range(0.8, 1.2)
	return to


func _fire(dir: Vector3) -> void:
	var spread_x := deg_to_rad(randf_range(-aim_spread, aim_spread))
	var spread_y := deg_to_rad(randf_range(-aim_spread, aim_spread))
	dir = Basis(global_basis.y, spread_y) * (Basis(global_basis.x, spread_x) * dir)
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.from_ally = true
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = fire_point.global_position
	bullet.launch(dir, bullet_speed)


# Hit by enemy fire.
func take_hit(damage: int, point: Vector3) -> void:
	if dead:
		return
	health -= damage
	Explosion.spawn(point, Color(0.6, 0.8, 1.0), 0.4)
	if health <= 0:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	remove_from_group("allies")
	remove_from_group("allies_air")
	Blast.spawn(global_position, 1.2)
	queue_free()
