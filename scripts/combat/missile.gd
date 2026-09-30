class_name Missile
extends Node3D

# A homing missile fired by a MissileTurret at the player's ship. It speeds up
# off the rail and steers after the ship with a limited turn rate: faster than
# the ship cruises, slower than it boosts, so the way out is to boost away
# (straight up works best) or out-turn it. It only has fuel for fuel_time (20)
# seconds of chasing; then the motor cuts out, it coasts to a stop with the
# flame sputtering out and the smoke drifting off behind it, and it fizzles.
# Reaching the ship destroys it outright (game over); hitting the ground just
# sets the missile off.

static var active: Array[Missile] = []

@export var start_speed := 8.0
@export var top_speed := 19.0
@export var acceleration := 9.0
## Degrees per second it can turn toward the ship.
@export var turn_rate := 60.0
## Seconds of chasing before the motor burns out.
@export var fuel_time := 20.0
## Seconds it drifts, dead, before it's gone.
@export var dead_time := 3.5
## Goes off this close to the ship.
@export var proximity := 2.0

var target: Node3D
var velocity := Vector3.ZERO
var burning := true
var age := 0.0
var _dead_age := 0.0
var _flame: FxParticles
var _smoke: FxParticles
var _light: OmniLight3D


# `body` is a copy of the launcher's missile mesh (nose along -Z).
static func launch(from: Transform3D, body: Node3D, at: Node3D) -> Missile:
	var tree := Engine.get_main_loop() as SceneTree
	var m := Missile.new()
	m.name = "Missile"
	m.target = at
	tree.current_scene.add_child(m)
	# The tube's transform carries the turret's scale; the missile itself
	# stays unscaled and only its mesh is sized to match.
	m.global_transform = Transform3D(from.basis.orthonormalized(), from.origin)
	m.velocity = -from.basis.z.normalized() * m.start_speed
	var scale := from.basis.get_scale().x
	var body_scale := Vector3.ONE * scale
	if body != null:
		# Keep the rack's own stretch (longer missiles), times the turret's size.
		body_scale = body.scale * scale
		body.transform = Transform3D.IDENTITY
		body.scale = body_scale
		m.add_child(body)
	m._build_exhaust(body_scale.z)
	# The launch itself: a flash and a puff of smoke at the tube.
	Explosion.spawn(from.origin, Color(1.0, 0.7, 0.3), 0.5)
	return m


func _enter_tree() -> void:
	active.append(self)


func _exit_tree() -> void:
	active.erase(self)


# True if some missile is chasing `who` right now.
static func chasing(who: Node3D) -> bool:
	for m in active:
		if m.homing and m.target == who:
			return true
	return false


# Chasing the player right now (for the HUD's warning, radar and camera).
var homing: bool:
	get:
		return burning and is_instance_valid(target)


# `scale` is the missile mesh's lengthwise scale (its body is ~0.44 long at 1).
func _build_exhaust(scale: float) -> void:
	var tail := Node3D.new()
	tail.position = Vector3(0, 0, 0.25 * scale)
	tail.rotation_degrees = Vector3(0, 180, 0)   # emit backwards
	add_child(tail)
	_flame = FxParticles.new()
	_flame.rate = 70.0
	_flame.max_particles = 50
	_flame.lifetime = Vector2(0.12, 0.25)
	_flame.speed = Vector2(4.0, 7.0)
	_flame.size = Vector2(0.35, 0.6)
	_flame.shape = FxParticles.Shape.CONE
	_flame.cone_angle = 8.0
	_flame.start_color_a = Color(1.0, 0.85, 0.5)
	_flame.start_color_b = Color(1.0, 0.5, 0.15)
	_flame.color_keys = [[0.0, Color.WHITE], [1.0, Color(1.0, 0.3, 0.05)]]
	_flame.alpha_keys = [[0.0, 1.0], [1.0, 0.0]]
	_flame.size_end = 0.3
	tail.add_child(_flame)
	_smoke = FxParticles.new()
	_smoke.additive = false
	_smoke.rate = 40.0
	_smoke.max_particles = 120
	_smoke.lifetime = Vector2(1.5, 2.5)
	_smoke.speed = Vector2(0.5, 1.2)
	_smoke.size = Vector2(0.5, 0.9)
	_smoke.shape = FxParticles.Shape.CONE
	_smoke.cone_angle = 20.0
	_smoke.start_color_a = Color(0.55, 0.55, 0.55)
	_smoke.start_color_b = Color(0.35, 0.35, 0.35)
	_smoke.alpha_keys = [[0.0, 0.0], [0.1, 0.55], [1.0, 0.0]]
	_smoke.size_end = 3.0
	_smoke.drag = 1.0
	tail.add_child(_smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 2.0
	_light.omni_range = 5.0
	tail.add_child(_light)


func _process(delta: float) -> void:
	age += delta
	var planet := Planet.instance
	var game_over := GameManager.instance != null and GameManager.instance.is_game_over
	var ship := target as PlayerShipController
	if burning and (age >= fuel_time or game_over or not is_instance_valid(target) or (ship != null and ship.wrecked)):
		_burn_out()

	if burning:
		_steer(delta)
	else:
		_coast(delta)

	global_position += velocity * delta
	if velocity.length_squared() > 0.01:
		global_basis = Basis.looking_at(velocity.normalized(), _up_hint())

	if planet != null and planet.altitude(global_position) < 0.3:
		_detonate(false)
		return
	if burning and target.global_position.distance_to(global_position) < proximity:
		_detonate(true)


func _steer(delta: float) -> void:
	var speed := minf(velocity.length() + acceleration * delta, top_speed)
	var to_target := (target.global_position - global_position).normalized()
	var heading := velocity.normalized()
	var angle := heading.angle_to(to_target)
	var step := deg_to_rad(turn_rate) * delta
	if angle > 0.0001:
		var axis := heading.cross(to_target)
		if axis.length_squared() < 0.000001:
			axis = heading.cross(Vector3.UP if absf(heading.y) < 0.9 else Vector3.RIGHT)
		heading = heading.rotated(axis.normalized(), minf(angle, step))
	velocity = heading * speed


# Motor out: slows to a halt while the last of the flame gutters and the
# smoke it left behind drifts off; then it's gone with a small pop.
func _burn_out() -> void:
	burning = false
	_flame.rate = 25.0
	_flame.speed = Vector2(1.0, 3.0)
	_smoke.rate = 12.0


func _coast(delta: float) -> void:
	_dead_age += delta
	velocity = velocity.move_toward(Vector3.ZERO, top_speed * 0.7 * delta)
	var t := _dead_age / dead_time
	_flame.rate = 25.0 * maxf(0.0, 1.0 - t * 2.0) * (0.3 + 0.7 * float(randf() < 0.6))
	_smoke.rate = 12.0 * maxf(0.0, 1.0 - t)
	_light.light_energy = 2.0 * maxf(0.0, 1.0 - t * 2.0) * randf_range(0.4, 1.0)
	if _dead_age >= dead_time:
		Explosion.spawn(global_position, Color(0.8, 0.8, 0.8), 0.3)
		_leave_smoke()
		queue_free()


func _detonate(hit_player: bool) -> void:
	Blast.spawn(global_position, 1.0)
	_leave_smoke()
	if hit_player and target is PlayerShipController and (target as PlayerShipController).on_foot:
		# The pilot bailed out in time: only the empty ship is lost.
		(target as PlayerShipController).wreck()
	elif hit_player and target is PlayerShipController:
		# A direct hit is fatal: the ship blows up and the game is over.
		var gm := GameManager.instance
		if gm != null and not gm.is_game_over:
			gm.death_reason = "SHOT DOWN BY A MISSILE"
			gm.player_hit(gm.health)
	elif hit_player and is_instance_valid(target) and target.has_method("take_hit"):
		# An allied fighter: destroyed too.
		target.call("take_hit", 1000, global_position)
	queue_free()


# The smoke trail stays hanging in the air and fades on its own.
func _leave_smoke() -> void:
	_smoke.emitting = false
	_smoke.reparent(get_tree().current_scene)
	var timer := Timer.new()
	timer.wait_time = 2.6
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(_smoke.queue_free)
	_smoke.add_child(timer)


func _up_hint() -> Vector3:
	var up := Planet.instance.up_at(global_position) if Planet.instance != null else Vector3.UP
	return up if absf(velocity.normalized().dot(up)) < 0.98 else global_basis.x
