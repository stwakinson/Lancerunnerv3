class_name Enemy
extends Area3D

# Enemy fighter. Chases the player with a limited turn rate (so it can be
# out-turned), fires when roughly lined up, and breaks off after a close pass
# so it swoops past and loops back instead of ramming. Stats scale with the
# wave number via configure().

var bullet_scene: PackedScene = load("res://scenes/enemy_bullet.tscn")

@export_group("Stats (overwritten per wave by configure)")
@export var health := 1
@export var speed := 5.0
## Degrees per second. Lower = easier to escape.
@export var turn_rate := 55.0
@export var fire_interval := 3.0
@export var aim_spread := 2.5
@export var score_value := 100

@export_group("Behaviour")
## Closer than this, the enemy breaks off and swoops past instead of ramming.
@export var break_off_distance := 7.0
@export var fire_range := 45.0
## Only fires when the player is within this many degrees of its nose.
@export var fire_cone := 12.0
@export var separation_radius := 5.0
## Enemies steer back down when they climb this high above the planet.
@export var leash_altitude := 1500.0
## Freshly warped-in enemies race toward the player at this multiple of their speed...
@export var arrival_speed_multiplier := 3.5
## ...easing down to normal speed by this distance from the player.
@export var arrival_slowdown_distance := 60.0
## Hunters called in from far across the world close most of the gap this
## fast (seconds per e-fold), so they show up in about 10-15 s from anywhere.
@export var arrival_time_constant := 5.0
## Enemies pull up when they get this close to the planet's surface.
@export var ground_avoid_height := 10.0

@export_group("Patrol")
## Idle fighters cruise between random points this far from home...
@export var patrol_radius := 80.0
## ...at this fraction of their speed.
@export var patrol_speed_factor := 0.5

@export_group("Shooting")
@export var bullet_speed := 18.0
## Share of enemies that go after the player's allies; the rest hunt the
## player (see _player_out_of_reach for when they take on allies too).
@export var ally_hunter_chance := 0.5
## Ally-hunters attack the nearest of the player and any allies closer than this.
@export var ally_target_range := 200.0
## Size of the shots (see Bullet.size).
@export var bullet_size := 1.0
## What the shots do to the player's ship (-1 = the bullet's own damage).
@export var bullet_ship_damage := -1

@export_group("Look")
@export var tint := Color(1.0, 0.45, 0.4)
@export var explosion_color := Color(1.0, 0.45, 0.15)
## Size of the fiery blast when destroyed.
@export var blast_size := 1.2

@onready var fire_point: Node3D = $FirePoint

var player: Node3D
var fire_timer := 0.0
var break_off_timer := 0.0
var break_off_direction := Vector3.ZERO
var dead := false
# True from warp-in until the enemy has closed in on the player.
var arriving := false
# Hunting the player (the spawner picks which); otherwise patrolling near home.
var attacking := false
var home := Vector3.ZERO
var _waypoint := Vector3.ZERO
var _retarget := 0.0
# Rolled once: whether this enemy goes after allies as well as the player.
var hunts_allies := false


static func active(tree: SceneTree) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in tree.get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and not e.dead:
			out.append(e)
	return out


func _ready() -> void:
	add_to_group("enemies")
	hunts_allies = randf() < ally_hunter_chance
	fire_timer = randf_range(1.5, 3.0)
	_build_visual()
	player = get_tree().get_first_node_in_group("player")


# Puts the model under $Visual. Other enemy types override this.
func _build_visual() -> void:
	ShipModel.attach($Visual, ShipModel.ENEMY_THRUST_CORE, ShipModel.ENEMY_THRUST_TAIL, tint)


# Difficulty curve: level 1 is slow and forgiving; each level (the spawner
# raises it over time) adds speed, agility, fire rate and accuracy. Enemies
# always go down in one shot.
func configure(level: int) -> void:
	var w := maxi(0, level - 1)
	speed = minf(5.0 + 0.45 * w, 9.5)
	turn_rate = minf(55.0 + 8.0 * w, 140.0)
	fire_interval = maxf(3.0 * pow(0.88, w), 0.9)
	aim_spread = maxf(2.5 - 0.2 * w, 0.8)
	health = 1
	score_value = 100 + 25 * w


func _process(delta: float) -> void:
	_find_target()
	if player == null or dead:
		return
	if not attacking:
		_patrol(delta)
		return

	var pos := global_position
	var forward := -global_basis.z
	var to_player := player.global_position - pos
	var dist := to_player.length()
	var dir_to_player := to_player / dist if dist > 0.001 else forward

	if break_off_timer <= 0.0 and dist < break_off_distance:
		break_off_timer = randf_range(1.5, 2.5)
		break_off_direction = (forward + FxParticles.random_inside_unit_sphere() * 0.6).normalized()

	var desired: Vector3
	if break_off_timer > 0.0:
		break_off_timer -= delta
		desired = break_off_direction
	else:
		desired = dir_to_player

	# Keep a little space from the other hunters so they don't stack up.
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not (other as Enemy).attacking:
			continue
		var away := pos - (other as Node3D).global_position
		var d := away.length()
		if d > 0.001 and d < separation_radius:
			desired += away / d * (1.0 - d / separation_radius) * 1.5

	var planet := Planet.instance
	if planet != null:
		var alt := planet.altitude(pos)
		if alt > leash_altitude:
			desired -= planet.up_at(pos)
		if alt < ground_avoid_height:
			desired += planet.up_at(pos) * (1.0 - maxf(alt, 0.0) / ground_avoid_height) * 2.0

	if desired.length_squared() > 0.0001:
		var wanted := Rotations.look_rotation(desired)
		global_basis = Basis(Rotations.rotate_towards(global_basis.get_rotation_quaternion(), wanted, turn_rate * delta))
	var current_speed := speed
	if arriving:
		var rush := clampf((dist - arrival_slowdown_distance) / arrival_slowdown_distance, 0.0, 1.0)
		current_speed = speed * lerpf(1.0, arrival_speed_multiplier, rush)
		current_speed = maxf(current_speed, (dist - arrival_slowdown_distance) / arrival_time_constant)
		if rush <= 0.0:
			arriving = false
	global_position += -global_basis.z * current_speed * delta
	if planet != null:
		global_position = planet.push_out(global_position, 1.0)

	fire_timer -= delta
	var game_over := GameManager.instance != null and GameManager.instance.is_game_over
	if not game_over and fire_timer <= 0.0 and dist < fire_range and rad_to_deg((-global_basis.z).angle_to(to_player)) < fire_cone:
		_fire()
		fire_timer = fire_interval * randf_range(0.8, 1.2)


# Not hunting: cruise between random points around home, keeping off the ground.
func _patrol(delta: float) -> void:
	var pos := global_position
	var planet := Planet.instance
	if _waypoint == Vector3.ZERO or pos.distance_to(_waypoint) < 10.0:
		_waypoint = home + FxParticles.random_on_unit_sphere() * patrol_radius
		if planet != null:
			_waypoint = planet.push_out(_waypoint, ground_avoid_height * 3.0)
	var desired := (_waypoint - pos).normalized()
	if planet != null and planet.altitude(pos) < ground_avoid_height * 2.0:
		desired += planet.up_at(pos)
	var wanted := Rotations.look_rotation(desired)
	global_basis = Basis(Rotations.rotate_towards(global_basis.get_rotation_quaternion(), wanted, turn_rate * 0.5 * delta))
	global_position += -global_basis.z * speed * patrol_speed_factor * delta
	if planet != null:
		global_position = planet.push_out(global_position, 1.0)


# Where the blast goes off (the middle of the body).
func _blast_point() -> Vector3:
	return global_position


# The player (ship, or the pilot on foot) - or, when hunting, whichever of
# the player and their allies (see _ally_group) is nearest. Re-picked twice a
# second; `player` holds the current target.
func _find_target() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	_retarget -= get_process_delta_time()
	var keep := is_instance_valid(player) and not player.is_queued_for_deletion() \
		and (player == p or player.is_in_group("allies"))
	if _retarget > 0.0 and keep:
		return
	_retarget = randf_range(0.4, 0.6)
	player = p
	var group := _ally_group()
	if group.is_empty() or not attacking or p == null:
		return
	if not hunts_allies and not _player_out_of_reach(p):
		return
	# Ally-hunters go for the nearest ally in range, even with the player
	# nearer, so they keep the allies busy; the rest only turn on allies
	# while the player can't be reached.
	var best := INF if hunts_allies else p.global_position.distance_to(global_position)
	for a in get_tree().get_nodes_in_group(group):
		var d := (a as Node3D).global_position.distance_to(global_position)
		if d < best and d < ally_target_range:
			best = d
			player = a


# True when even enemies that normally only hunt the player should take on
# allies as well (attacking whichever is nearest). Fighters do this while the
# player is down on the ground, so they strafe the troops and ships around
# them instead of only diving at the player.
func _player_out_of_reach(p: Node3D) -> bool:
	return Planet.instance != null and Planet.instance.altitude(p.global_position) < 5.0


# Which allies this kind of enemy fights ("" = only ever the player).
# Fighters take on any of them: ships in the air and troopers on the ground.
func _ally_group() -> String:
	return "allies"


func _fire() -> void:
	var origin := fire_point.global_position
	var dir := (player.global_position - origin).normalized()
	var spread_x := deg_to_rad(randf_range(-aim_spread, aim_spread))
	var spread_y := deg_to_rad(randf_range(-aim_spread, aim_spread))
	dir = Basis(Vector3.UP, spread_y) * (Basis(Vector3.RIGHT, spread_x) * dir)

	var bullet := bullet_scene.instantiate() as Bullet
	bullet.size = bullet_size
	bullet.ship_damage = bullet_ship_damage
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin
	bullet.launch(dir, bullet_speed)


# `bullet` is the shot that hit (null for other damage).
func hit(damage: int, hit_point: Vector3, bullet: Bullet = null) -> void:
	if dead:
		return
	health -= damage
	# Shot while patrolling: fight back (the spawner makes room for it).
	attacking = true
	if health <= 0:
		# Kills by allies don't count toward the player's score.
		die(bullet == null or not bullet.from_ally)
	else:
		Explosion.spawn(hit_point, explosion_color, 0.4)  # spark so non-lethal hits still register


func die(killed_by_player: bool) -> void:
	if dead:
		return
	dead = true

	# Goes up in a fireball with burning wreckage (Blast also shakes the camera).
	Blast.spawn(_blast_point(), blast_size)
	if killed_by_player and GameManager.instance != null:
		GameManager.instance.register_kill(score_value)

	remove_from_group("enemies")
	queue_free()
