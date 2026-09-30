class_name Bullet
extends Area3D

@export var lifetime := 3.0
@export var damage := 1
## Damage to the player's ship, if different (-1 = same as damage). Ground
## robots' small shots barely scratch the ship's hull.
@export var ship_damage := -1
## Fired by the pilot on foot (weaker against armour than the ship's guns).
@export var from_pilot := false
## Fired by an allied fighter or trooper (their kills aren't the player's).
@export var from_ally := false
## Player bullets damage enemies; enemy bullets damage the player.
@export var from_player := true
@export var trail_start := Color(1.0, 0.95, 0.5)
@export var trail_end := Color(1.0, 0.6, 0.1)
## Scales the shot and its trail (smaller for person-sized shooters on foot).
## Set before the bullet enters the tree.
@export var size := 1.0

var velocity := Vector3.ZERO
var timer := 0.0
var _spent := false


func _ready() -> void:
	add_to_group("bullets")
	area_entered.connect(_on_area_entered)
	scale = Vector3.ONE * size

	var trail := Trail.new()
	trail.time = 0.12
	trail.min_vertex_distance = 0.05
	trail.width = 0.2 * size
	trail.start_color = trail_start
	trail.end_color = trail_end
	add_child(trail)


func launch(direction: Vector3, speed: float) -> void:
	velocity = direction.normalized() * speed
	timer = lifetime


func _process(delta: float) -> void:
	# Sweep the shot along this frame's path before moving it, so it can't
	# skip past something thin (a robot is 0.08 wide; a shot moves ~0.7 a
	# frame) between collision checks.
	var from := global_position
	var motion := velocity * delta
	var hit: Variant = _sweep(from, motion)
	if hit != null:
		global_position = hit[1]
		_on_area_entered(hit[0])
		if _spent:
			return
	global_position = from + motion
	timer -= delta
	var planet := Planet.instance
	if timer <= 0.0 or (planet != null and planet.altitude(global_position) < 0.0):
		queue_free()


var _sweep_query: PhysicsShapeQueryParameters3D


# The first thing a sphere the size of this shot would touch moving by
# `motion` from `from`: [area, where], or null.
func _sweep(from: Vector3, motion: Vector3) -> Variant:
	if _spent or motion.length_squared() < 0.000001:
		return null
	if _sweep_query == null:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.125 * size
		_sweep_query = PhysicsShapeQueryParameters3D.new()
		_sweep_query.shape = sphere
		_sweep_query.collision_mask = collision_mask
		_sweep_query.collide_with_areas = true
		_sweep_query.collide_with_bodies = false
	var space := get_world_3d().direct_space_state
	_sweep_query.transform = Transform3D(Basis.IDENTITY, from)
	_sweep_query.motion = motion
	var fractions := space.cast_motion(_sweep_query)
	if fractions.is_empty() or fractions[1] >= 1.0:
		return null
	var at := from + motion * fractions[1]
	_sweep_query.transform = Transform3D(Basis.IDENTITY, at)
	_sweep_query.motion = Vector3.ZERO
	for h in space.intersect_shape(_sweep_query, 4):
		var area := h.collider as Area3D
		if area != null:
			return [area, at]
	return null


func _on_area_entered(other: Area3D) -> void:
	if _spent:
		return
	if from_player:
		var enemy := other as Enemy
		if enemy == null:
			return
		enemy.hit(damage, global_position, self)
	else:
		var pilot := other as PlayerOnFoot
		var player := other as PlayerShipController
		if other.is_in_group("allies"):
			other.call("take_hit", damage, global_position)
		elif pilot != null:
			pilot.health.take_hit(damage)
		elif player != null and not player.on_foot:
			player.health.take_hit(ship_damage if ship_damage >= 0 else damage)
		else:
			return
	_spent = true
	queue_free()
