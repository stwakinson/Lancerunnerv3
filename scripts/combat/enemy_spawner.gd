class_name EnemySpawner
extends Node3D

# Keeps a standing population of enemies around the planet:
#   - fighter_population fighters scattered through space all around the
#     world, cruising on patrol. Only the nearest few hunt the player at once
#     (starting_attackers, one more every add_attacker_every seconds, up to
#     max_attackers); the rest keep patrolling until a slot opens.
#   - robot_population walking robots scattered over the planet's surface,
#     wandering where they stand. As the player comes down toward the ground,
#     a battle is already under way at the spot below them: up to
#     max_robot_attackers robots are gathered there (quietly, while the player
#     is still too high to see them) fighting the player's troopers, and they
#     turn on the player once they land.
#   - turret_population missile turrets planted around the planet's surface.
#     Each locks onto the ship when it flies into its lock zone (MissileTurret).
# In Infinite mode anything destroyed is replaced somewhere far from the
# player, so the populations stay full. In Classic mode (GameMode) nothing
# comes back: destroy them all to win, and once only a few are left they all
# come after the player. Enemies recruited later are tougher (difficulty
# rises every difficulty_step_time seconds).

var enemy_scene: PackedScene = load("res://scenes/enemy.tscn")
var robot_scene: PackedScene = load("res://scenes/ground_robot.tscn")
var turret_scene: PackedScene = load("res://scenes/missile_turret.tscn")

@export_group("Fighters")
@export var fighter_population := 50
## Height range above the ground that fighters are scattered through.
@export var fighter_altitude_range := Vector2(40.0, 900.0)
@export var starting_attackers := 4
## One more fighter joins the hunt every this many seconds...
@export var add_attacker_every := 10.0
## ...up to this many at once.
@export var max_attackers := 10
## Hunters left this far behind go back to patrolling (a nearer one takes over).
@export var give_up_distance := 900.0
## Replacements for destroyed enemies appear at least this far from the player.
@export var respawn_min_distance := 400.0
## Enemies level up (faster, sharper, quicker to shoot) every this many seconds.
@export var difficulty_step_time := 30.0

@export_group("Ground Robots")
@export var robot_population := 50
## Once the player comes lower than this over the planet, a ground battle is
## set up at the spot below them (they're too high to see it being set up).
@export var robot_altitude := 250.0
@export var starting_robots := 8
## One more robot joins every this many seconds spent down near the ground...
@export var add_robot_every := 10.0
## ...up to this many at once.
@export var max_robot_attackers := 10
## Recruited robots further than this from the battle spot are moved there...
@export var robot_warp_distance := 30.0
## ...this far from its centre.
@export var robot_arrival_distance := 8.0
@export var warp_flash_color := Color(0.6, 0.8, 1.0)

@export_group("Missile Turrets")
@export var turret_population := 30
## Turrets are never placed closer than this to the player's starting point.
@export var turret_start_clearance := 400.0
## Each turret is placed at the best of this many random spots: the one
## farthest from every other turret, so they spread out evenly with no clumps.
@export var turret_placement_tries := 40

## Classic mode: with this many enemies (or fewer) left, every one of them hunts.
@export var classic_endgame := 10

var fighters: Array[Enemy] = []
var robots: Array[Enemy] = []
var turrets: Array[Enemy] = []
var player: Node3D
var elapsed := 0.0
# Seconds the player has spent down near the ground (drives the robot count).
var _ground_time := 0.0
var _assign_timer := 0.0

# Fighters and robots still alive: the enemies that must be destroyed to win
# Classic mode. Missile turrets are a hazard to avoid or take out, but don't
# count toward winning.
var enemies_left: int:
	get:
		var n := 0
		for list in [fighters, robots]:
			for e in list:
				if is_instance_valid(e) and not e.dead:
					n += 1
		return n

# Classic mode, down to the last few: they all hunt the player.
var endgame: bool:
	get:
		return GameMode.is_classic and enemies_left <= classic_endgame

# 1 at the start, +1 every difficulty_step_time seconds (fed to Enemy.configure).
var difficulty_level: int:
	get:
		return 1 + int(elapsed / difficulty_step_time)


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	_populate()


func _process(delta: float) -> void:
	if GameManager.instance != null and GameManager.instance.is_game_over:
		return
	elapsed += delta
	var center := _target_position()
	var planet := Planet.instance
	if planet != null and planet.altitude(center) <= robot_altitude:
		_ground_time += delta

	_refill()
	# Re-picking hunters twice a second is plenty.
	_assign_timer -= delta
	if _assign_timer <= 0.0:
		_assign_timer = 0.5
		_assign_fighters(center)
		_assign_robots(center)


# The ship, or the pilot while they're out on foot.
func _target_position() -> Vector3:
	var target := get_tree().get_first_node_in_group("player") as Node3D
	if target != null:
		return target.global_position
	return player.global_position if player != null else Vector3.ZERO


func _populate() -> void:
	var center := _target_position()
	for i in fighter_population:
		_spawn_fighter(center, 60.0)
	for i in robot_population:
		_spawn_robot(center, 20.0)
	for i in turret_population:
		_spawn_turret(center, turret_start_clearance)


# Replace anything destroyed, far from the player.
func _refill() -> void:
	for list in [fighters, robots, turrets]:
		for i in range(list.size() - 1, -1, -1):
			if not is_instance_valid(list[i]) or list[i].dead:
				list.remove_at(i)
	# Classic mode: the dead stay dead.
	if GameMode.is_classic:
		return
	var center := _target_position()
	if fighters.size() < fighter_population:
		_spawn_fighter(center, respawn_min_distance)
	if robots.size() < robot_population:
		_spawn_robot(center, respawn_min_distance)
	if turrets.size() < turret_population:
		_spawn_turret(center, respawn_min_distance)


# Somewhere random in the space around the planet, at least min_distance from the player.
func _spawn_fighter(center: Vector3, min_distance: float) -> void:
	var planet := Planet.instance
	var pos := Vector3.ZERO
	for attempt in 12:
		var alt := randf_range(fighter_altitude_range.x, fighter_altitude_range.y)
		pos = planet.global_position + FxParticles.random_on_unit_sphere() * (planet.radius + alt)
		if pos.distance_to(center) >= min_distance:
			break
	var enemy := enemy_scene.instantiate() as Enemy
	enemy.transform = Transform3D(Basis(Rotations.look_rotation(FxParticles.random_on_unit_sphere(), planet.up_at(pos))), pos)
	enemy.configure(difficulty_level)
	enemy.home = pos
	add_child(enemy)
	fighters.append(enemy)


# Somewhere random on the planet's surface, at least min_distance from the player.
func _spawn_robot(center: Vector3, min_distance: float) -> void:
	var planet := Planet.instance
	var up := Vector3.UP
	var pos := Vector3.ZERO
	for attempt in 12:
		up = FxParticles.random_on_unit_sphere()
		pos = planet.global_position + up * planet.radius
		if pos.distance_to(center) >= min_distance:
			break
	var facing := up.cross(FxParticles.random_on_unit_sphere()).normalized()
	var robot := robot_scene.instantiate() as Enemy
	robot.transform = Transform3D(Basis.looking_at(facing, up), pos)
	robot.configure(difficulty_level)
	robot.home = pos
	add_child(robot)
	robots.append(robot)


# Planted on the surface at least min_distance from the player, in whichever
# of turret_placement_tries random spots is farthest from all other turrets
# (best-candidate sampling): the turrets spread out evenly instead of
# clumping, and a replacement fills the biggest gap.
func _spawn_turret(center: Vector3, min_distance: float) -> void:
	var planet := Planet.instance
	var up := Vector3.UP
	var best_gap := -1.0
	for attempt in turret_placement_tries:
		var candidate := FxParticles.random_on_unit_sphere()
		var pos := planet.global_position + candidate * planet.radius
		if pos.distance_to(center) < min_distance:
			continue
		var gap := INF
		for other in turrets:
			if is_instance_valid(other) and not other.dead:
				gap = minf(gap, pos.distance_to(other.global_position))
		if gap > best_gap:
			best_gap = gap
			up = candidate
	var facing := up.cross(FxParticles.random_on_unit_sphere()).normalized()
	var turret := turret_scene.instantiate() as Enemy
	turret.transform = Transform3D(Basis.looking_at(facing, up), planet.global_position + up * planet.radius)
	turret.configure(difficulty_level)
	add_child(turret)
	turrets.append(turret)


# Keep the current hunters (unless they've been left far behind), drop any over
# the limit, and fill free slots with the nearest patrolling fighters.
func _assign_fighters(center: Vector3) -> void:
	var target := mini(starting_attackers + int(elapsed / add_attacker_every), max_attackers)
	if endgame:
		target = fighters.size()
	_assign(fighters, center, target, give_up_distance, false)


# Robots only hunt while the player is down near the ground.
func _assign_robots(center: Vector3) -> void:
	var planet := Planet.instance
	var low := planet != null and planet.altitude(center) <= robot_altitude
	var target := mini(starting_robots + int(_ground_time / add_robot_every), max_robot_attackers) if low else 0
	if endgame and low:
		target = robots.size()
	# Distances are measured from the spot on the ground under the player.
	var ground := planet.global_position + planet.up_at(center) * planet.radius
	_assign(robots, ground, target, robot_warp_distance * 2.0, true)


func _assign(list: Array[Enemy], center: Vector3, target: int, give_up: float, warp_in: bool) -> void:
	var hunters: Array[Enemy] = []
	var idle: Array = []
	for e in list:
		var d := e.global_position.distance_to(center)
		# (Ones still racing in from afar are given time to arrive.)
		if e.attacking and d > give_up and not e.arriving:
			_stand_down(e)
		if e.attacking:
			hunters.append(e)
		else:
			idle.append([d, e])
	# Too many (the limit is still ramping, or the player left the ground):
	# the farthest go back to patrolling.
	hunters.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	while hunters.size() > target:
		_stand_down(hunters.pop_back())
	if hunters.size() >= target:
		return
	idle.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for pair in idle:
		if hunters.size() >= target:
			break
		var e := pair[1] as Enemy
		if warp_in and (pair[0] as float) > robot_warp_distance:
			_warp_robot_near(e, center)
		e.configure(difficulty_level)
		e.attacking = true
		# Fighters far away race in at speed, then ease into the fight.
		e.arriving = not warp_in and (pair[0] as float) > 120.0
		hunters.append(e)


func _stand_down(e: Enemy) -> void:
	e.attacking = false
	e.arriving = false
	e.home = e.global_position


# A robot too far away to walk is moved to the battle below the player (no
# flash: the player is still too high up to see it happen).
func _warp_robot_near(robot: Enemy, center: Vector3) -> void:
	var planet := Planet.instance
	var up := planet.up_at(center)
	var side := FxParticles.random_on_unit_sphere()
	side = (side - up * side.dot(up)).normalized()
	if side.length_squared() < 0.01:
		side = up.cross(Vector3.RIGHT).normalized()
	var angle := robot_arrival_distance / planet.radius
	var ground_up := up.rotated(up.cross(side).normalized(), angle)
	var pos := planet.global_position + ground_up * planet.radius
	var to_player := center - pos
	var facing := (to_player - ground_up * to_player.dot(ground_up)).normalized()
	robot.global_transform = Transform3D(Basis.looking_at(facing, ground_up), pos)
	robot.home = pos


# Clears the field and starts over (used by restart).
func reset() -> void:
	for e in fighters + robots + turrets:
		if is_instance_valid(e):
			e.remove_from_group("enemies")
			e.queue_free()
	fighters.clear()
	robots.clear()
	turrets.clear()
	for m in Missile.active.duplicate():
		m.queue_free()
	elapsed = 0.0
	_ground_time = 0.0
	_assign_timer = 0.0
	_populate()
