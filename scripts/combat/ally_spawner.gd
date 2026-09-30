class_name AllySpawner
extends Node3D

# The player's side: air_population allied fighters scattered through space
# around the planet, and ground_population troopers scattered over its
# surface. The nearest max_escorts fighters escort the player (see
# AllyFighter). As the player comes down toward the ground, the nearest
# max_deployed troopers are already at the spot below them, fighting the
# enemy robots gathered there (set up while the player is too high to see).
# Allies that are destroyed are gone for good.

var fighter_scene: PackedScene = load("res://scenes/ally_fighter.tscn")
var trooper_scene: PackedScene = load("res://scenes/ally_trooper.tscn")

@export var air_population := 50
@export var ground_population := 50
@export var max_escorts := 10
@export var max_deployed := 10
## Height range above the ground that allied fighters are scattered through.
@export var air_altitude_range := Vector2(40.0, 900.0)
## Troopers deploy to the spot below the player once they're lower than this...
@export var deploy_altitude := 250.0
## ...and any further than this (along the ground) - including ones left
## behind when the player moved on - are brought in...
@export var trooper_bring_distance := 10.0
## ...to about this far from the player.
@export var trooper_arrival_distance := 2.5

var fighters: Array[AllyFighter] = []
var troopers: Array[AllyTrooper] = []
var _assign_timer := 0.0

var air_alive: int:
	get:
		return fighters.size()
var ground_alive: int:
	get:
		return troopers.size()


func _ready() -> void:
	add_to_group("ally_spawner")
	_populate()


func _populate() -> void:
	var planet := Planet.instance
	for i in air_population:
		var alt := randf_range(air_altitude_range.x, air_altitude_range.y)
		var pos := planet.global_position + FxParticles.random_on_unit_sphere() * (planet.radius + alt)
		var f := fighter_scene.instantiate() as AllyFighter
		f.transform = Transform3D(Basis(Rotations.look_rotation(FxParticles.random_on_unit_sphere(), planet.up_at(pos))), pos)
		f.home = pos
		add_child(f)
		fighters.append(f)
	for i in ground_population:
		var up := FxParticles.random_on_unit_sphere()
		var pos := planet.global_position + up * planet.radius
		var t := trooper_scene.instantiate() as AllyTrooper
		t.transform = Transform3D(Basis.looking_at(up.cross(FxParticles.random_on_unit_sphere()).normalized(), up), pos)
		t.home = pos
		add_child(t)
		troopers.append(t)


func _process(delta: float) -> void:
	for i in range(fighters.size() - 1, -1, -1):
		if not is_instance_valid(fighters[i]) or fighters[i].dead:
			fighters.remove_at(i)
	for i in range(troopers.size() - 1, -1, -1):
		if not is_instance_valid(troopers[i]) or troopers[i].dead:
			troopers.remove_at(i)
	_assign_timer -= delta
	if _assign_timer > 0.0:
		return
	_assign_timer = 0.5
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var planet := Planet.instance
	if player == null or planet == null:
		return
	var center := player.global_position

	# Escorts: the nearest fighters.
	var by_dist := fighters.duplicate()
	by_dist.sort_custom(func(a: AllyFighter, b: AllyFighter) -> bool:
		return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	for i in by_dist.size():
		var f: AllyFighter = by_dist[i]
		var escort := i < max_escorts
		if f.escorting and not escort:
			f.home = f.global_position
		f.escorting = escort
		f.slot = i

	# Troopers: only while the player is down near the ground.
	var low := planet.altitude(center) <= deploy_altitude
	# Distances are measured from the spot on the ground under the player.
	center = planet.global_position + planet.up_at(center) * planet.radius
	var troops := troopers.duplicate()
	troops.sort_custom(func(a: AllyTrooper, b: AllyTrooper) -> bool:
		return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	for i in troops.size():
		var t: AllyTrooper = troops[i]
		var deploy := low and i < max_deployed
		if deploy and t.global_position.distance_to(center) > trooper_bring_distance:
			_bring_in(t, center)
		if t.deployed and not deploy:
			t.home = t.global_position
		t.deployed = deploy


# A trooper too far to walk is moved to the battle below the player (no
# flash: the player is still too high up to see it happen).
func _bring_in(t: AllyTrooper, center: Vector3) -> void:
	var planet := Planet.instance
	var up := planet.up_at(center)
	var side := FxParticles.random_on_unit_sphere()
	side = (side - up * side.dot(up)).normalized()
	var ground_up := up.rotated(up.cross(side).normalized(), trooper_arrival_distance / planet.radius)
	var pos := planet.global_position + ground_up * planet.radius
	var to := center - pos
	var facing := (to - ground_up * to.dot(ground_up)).normalized()
	t.global_transform = Transform3D(Basis.looking_at(facing, ground_up), pos)
	t.home = pos


# Restart: everyone back, full strength.
func reset() -> void:
	for a in fighters + troopers:
		if is_instance_valid(a):
			a.remove_from_group("allies")
			a.queue_free()
	fighters.clear()
	troopers.clear()
	_assign_timer = 0.0
	_populate()
