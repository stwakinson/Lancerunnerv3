class_name PlayerShipController
extends Area3D

# Free 3D flight: the mouse sets the view (see CameraFollow) and the ship turns
# and pitches to point the same way. W/S fly forward/back along the view (so
# looking down and pressing W dives), A/D strafe, Shift boosts, left click (or
# Space) fires toward the screen-center crosshair. The ship has momentum: it
# speeds up smoothly and drifts to a stop. Touching the planet lands it; W
# takes off again. E climbs out when parked, or bails out in flight (see
# PlayerOnFoot). Left empty inside the atmosphere the ship drifts and falls
# (landing if it comes down gently, wrecked if not); out in space it brakes
# and holds position. If the empty ship is destroyed (a missile catching it,
# or crashing) the pilot lives on. Out of the ship, R brings a new ship
# (or the old one, if it's still in one piece) to the pilot with them already
# inside: parked if they're on land, hovering still if they're in the air.
# After a ship is lost or called there's a replacement_cooldown wait.
#
# Q in flight under gravity opens the ship's parachute from the top of its
# tail: it slows the fall to a safe landing speed and cuts away on touchdown
# (or with C), left lying on the ground. A new one is ready Parachute.COOLDOWN seconds later.
#
# The whole planet is the map. Inside its atmosphere the ship follows the
# curve of the ground (level flight goes around the world, not off into
# space), and gravity pulls it down whenever it's too slow to stay up.

@export_group("Movement")
## Top cruising speed.
@export var move_speed := 8.0
## How quickly thrust builds speed, in units per second per second.
@export var acceleration := 16.0
## With no keys held the ship keeps drifting and slows by this much per second.
@export var coast_deceleration := 2.5
## Highest the ship can climb above the planet.
@export var max_altitude := 1500.0

@export_group("Gravity")
## Height of the atmosphere above the ground. Gravity and the curve-following
## only apply inside it; above it (out in space) nothing pulls the ship down.
@export var atmosphere_height := 120.0
## Downward pull when stopped at ground level, in units per second per second.
## It weakens with height, to nothing at the top of the atmosphere.
@export var gravity_pull := 6.0
## At or above this speed the ship holds its height; slower, it sinks.
@export var stall_speed := 5.0
## Fastest the ship falls.
@export var max_fall_speed := 25.0

@export_group("Boost")
## Top speed while holding Shift.
@export var boost_speed := 22.0
@export var boost_acceleration := 30.0
## Seconds of boost from a full meter.
@export var boost_duration := 10.0
## Seconds to refill an empty meter.
@export var boost_recharge_time := 20.0
## Refilling starts this long after boosting stops.
@export var boost_recharge_delay := 1.0

@export_group("Aiming")
@export var aim_camera: CameraFollow
## How fast the nose swings to follow the view, in degrees per second.
@export var turn_speed := 540.0

@export_group("Landing")
## Height of the ship's center above the ground when touching down.
@export var landing_clearance := 0.15
## After touching down the ship slides and slows by this much per second.
@export var ground_friction := 5.0
## How quickly the ship picks up climbing speed when taking off.
@export var takeoff_acceleration := 5.0
## Takeoff hands back control after this long (or once high enough).
@export var takeoff_time := 1.6
@export var takeoff_height := 6.0
## Forward drift while lifting off, as a fraction of the climb speed.
@export var takeoff_forward := 0.3
## Hitting the ground faster than this straight into it destroys the ship:
## a steep or straight-down dive at full speed (about 8) or a boost dive
## steeper than about 18 degrees. Gentle descents (about 2), falling after
## stopping (about 5) and shallow boost landings touch down safely.
@export var crash_speed := 7.0
## Touching down faster than this overall destroys it too. Kept above boost
## speed so a shallow boost landing skids to a stop instead of exploding.
@export var crash_skid_speed := 28.0

@export_group("Parachute")
## With the parachute open the ship sinks at this speed (under crash_speed)...
@export var chute_fall_speed := 3.0
## ...and drifts sideways no faster than this.
@export var chute_glide_speed := 4.0
## How hard the open parachute slows the ship, per second.
@export var chute_drag := 15.0
@export var chute_color := Color(1.0, 0.45, 0.1)

@export_group("On Foot")
## Walks around as this while out of the ship.
@export var pilot: PlayerOnFoot
## Left empty out in space, the ship slows by this much per second until it hovers.
@export var empty_brake := 8.0
## Seconds after the ship is lost or called before R can bring a new one.
@export var replacement_cooldown := 20.0
## The empty ship's explosion hurts a pilot closer than this...
@export var wreck_blast_radius := 3.0
## ...by this much.
@export var wreck_blast_damage := 35

@export_group("Shooting")
@export var fire_point: Node3D
@export var fire_rate := 6.0
@export var bullet_speed := 30.0

enum State { FLYING, LANDED, TAKING_OFF }

@onready var health: PlayerHealth = $Health
@onready var visual: Node3D = $ShipVisual
var gear: LandingGear
# Solid body in the shape of the hull, so the pilot can't walk through the
# ship but can stand on it.
var _hull: ShipHull
## Height of the top of the hull above the ship's center.
var hull_top: float:
	get:
		return _hull.top_height if _hull != null else 0.5

var _weapons := ShipWeapons.new()
var enabled := true
var state := State.FLYING
var velocity := Vector3.ZERO
var boost_energy := 1.0
var boosting := false
# 0.3 = parked, 0.4 = coasting, 1.5 = thrusting, 2 = full boost; smoothed, drives the plumes.
var engine_level := 0.4
# 0..1, smoothed while boosting; drives the camera's field of view.
var boost_blend := 0.0

# Resting on the planet (or lifting off): the ship sits level with the ground.
var landed: bool:
	get:
		return state != State.FLYING

# The pilot is out of the ship: walking, or flying on the suit's boosters.
var on_foot := false
# Destroyed while empty; R calls a replacement.
var wrecked := false
# Seconds left until a new ship can be called.
var replacement_wait := 0.0
# A called-in ship holds still in the air until the pilot starts flying.
var _hover_hold := false

# The ship's parachute while it's open, and the wait before a new one.
var chute: Parachute
var chute_cooldown := 0.0

# In the air under gravity, parachute packed and ready.
var can_deploy_chute: bool:
	get:
		return chute == null and chute_cooldown <= 0.0 and state == State.FLYING \
			and gravity_weight(global_position) > 0.0

# Parked with the engines settled, or anywhere in flight (bailing out).
var can_exit: bool:
	get:
		if pilot == null:
			return false
		return state == State.FLYING or (state == State.LANDED and velocity.length() < 0.5)

var _boost_locked := false
var boost_locked: bool:
	get:
		return _boost_locked
var _recharge_wait := 0.0
var _takeoff_timer := 0.0
# Takeoff needs a fresh press of W, so holding W while diving in doesn't bounce off.
var _takeoff_armed := false
# Heading frozen at touchdown: parked ships don't turn to follow the mouse.
var _landed_forward := Vector3.FORWARD
var _thrusting := false
var _thrusters: Array[FxParticles] = []
var _thruster_base: Array = []


func _ready() -> void:
	add_to_group("player")
	if aim_camera == null:
		aim_camera = get_viewport().get_camera_3d() as CameraFollow
	ShipModel.attach(visual, ShipModel.PLAYER_THRUST_CORE, ShipModel.PLAYER_THRUST_TAIL)
	_hull = ShipHull.new()
	_hull.build(visual, landing_clearance)
	gear = LandingGear.new()
	gear.name = "LandingGear"
	visual.add_child(gear)
	for ps in visual.find_children("*", "FxParticles", true, false):
		var p := ps as FxParticles
		_thrusters.append(p)
		_thruster_base.append([p.rate, p.speed, p.size])


func view_rotation() -> Basis:
	return aim_camera.view_rotation if aim_camera != null else global_basis


func reset_motion() -> void:
	state = State.FLYING
	velocity = Vector3.ZERO
	boost_energy = 1.0
	boosting = false
	_boost_locked = false
	engine_level = 0.4
	boost_blend = 0.0
	if chute != null:
		chute.queue_free()
		chute = null
	chute_cooldown = 0.0
	_hover_hold = false
	if gear != null:
		gear.snap(false)


func _process(delta: float) -> void:
	if not enabled:
		return
	replacement_wait = maxf(0.0, replacement_wait - delta)
	if on_foot:
		_process_empty(delta)
	else:
		_handle_movement(delta)
		_update_gear()
		_handle_aiming(delta)
		_weapons.update(self, delta)
		_update_engines(delta)
	_hull.update_parked(state == State.LANDED)
	_update_chute(delta)


func _read_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): input.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): input.x += 1.0
	return input.limit_length(1.0)


func _handle_movement(delta: float) -> void:
	var input := _read_input()
	_thrusting = state == State.FLYING and input != Vector2.ZERO
	var planet := Planet.instance
	match state:
		State.FLYING:
			_fly(input, delta)
		State.LANDED:
			_slide_to_stop(delta)
			var w_held := input.y > 0.0
			if not w_held:
				_takeoff_armed = true
			elif _takeoff_armed:
				state = State.TAKING_OFF
				_takeoff_timer = 0.0
				DustPuff.spawn(global_position, planet.up_at(global_position))
		State.TAKING_OFF:
			_take_off(delta)
	update_boost_meter(delta)
	if state == State.FLYING and planet != null:
		_apply_gravity(planet, delta)
		_apply_chute(planet, delta)
	_integrate(delta)


# Moves by the velocity, following the planet's curve, and touches down (or
# crashes) on reaching the ground.
func _integrate(delta: float) -> void:
	var planet := Planet.instance
	var pos := global_position + velocity * delta
	if planet != null:
		# Level flight bends with the ground: turn the velocity by however much
		# "up" turned over this step.
		var old_up := planet.up_at(global_position)
		var new_up := planet.up_at(pos)
		var bend := _atmosphere_weight(planet, pos)
		if bend > 0.0 and old_up.dot(new_up) < 0.9999999:
			velocity = Quaternion.IDENTITY.slerp(Quaternion(old_up, new_up), bend) * velocity
		pos = _clamp_altitude(planet, pos)
		pos = planet.push_out(pos, landing_clearance)
		var up := planet.up_at(pos)
		var touching := planet.altitude(pos) <= landing_clearance + 0.01
		if touching:
			if state == State.FLYING and (-velocity.dot(up) > crash_speed or velocity.length() > crash_skid_speed):
				global_position = pos
				if on_foot:
					wreck()
				else:
					health.crash()
				return
			# Never keep speed pointing into the ground.
			var into := velocity.dot(up)
			if into < 0.0:
				velocity -= up * into
			if state == State.FLYING:
				state = State.LANDED
				_landed_forward = -global_basis.z
				_takeoff_armed = false
				boosting = false
				DustPuff.spawn(pos, up)
	global_position = pos


# With nobody aboard: inside the atmosphere the ship drifts to a stop
# sideways while gravity pulls it down; out in space it brakes to a hover
# and waits where it was left. On the ground it slides to a stop.
func _process_empty(delta: float) -> void:
	if wrecked:
		return
	_thrusting = false
	boosting = false
	var planet := Planet.instance
	match state:
		State.FLYING:
			if planet != null and gravity_weight(global_position) > 0.0:
				var up := planet.up_at(global_position)
				var vertical := up * velocity.dot(up)
				velocity = vertical + (velocity - vertical).move_toward(Vector3.ZERO, coast_deceleration * delta)
				_apply_gravity(planet, delta)
				_apply_chute(planet, delta)
			else:
				velocity = velocity.move_toward(Vector3.ZERO, empty_brake * delta)
		State.LANDED:
			velocity = velocity.move_toward(Vector3.ZERO, ground_friction * delta)
		State.TAKING_OFF:
			state = State.FLYING
	_integrate(delta)
	if wrecked:
		return
	_update_gear()
	_update_engines(delta)


# The empty ship is destroyed (a missile caught it, or it hit the ground too
# hard). The pilot survives unless they're still right next to it.
func wreck() -> void:
	if wrecked or not on_foot:
		return
	wrecked = true
	replacement_wait = replacement_cooldown
	cut_chute()
	_hull.set_solid(false)
	Blast.spawn(global_position, 2.0)
	visual.visible = false
	velocity = Vector3.ZERO
	var cam := get_viewport().get_camera_3d() as CameraFollow
	if cam != null:
		cam.shake(0.8)
	var gm := GameManager.instance
	if gm != null and not gm.is_game_over:
		gm.show_banner("SHIP LOST", 2.5)
	if pilot.active and pilot.global_position.distance_to(global_position) < wreck_blast_radius:
		if gm != null:
			gm.death_reason = "CAUGHT IN YOUR SHIP'S EXPLOSION"
		health.take_hit(wreck_blast_damage)
		if gm != null and not gm.is_game_over:
			gm.death_reason = ""


# Called with R while out of the ship: a new ship (or the old one, if it's
# still intact) appears where the pilot is, with them already inside, level
# and stationary. Parked on the ground if they're standing; otherwise hovering
# in place until they start flying.
func _deliver_replacement() -> void:
	var planet := Planet.instance
	cut_chute()
	wrecked = false
	replacement_wait = replacement_cooldown
	velocity = Vector3.ZERO
	boosting = false
	engine_level = 0.4
	if pilot.on_ground and planet != null:
		var ground := planet.up_at(pilot.global_position)
		global_position = planet.global_position + ground * (planet.radius + landing_clearance)
		state = State.LANDED
		_landed_forward = -pilot.global_basis.z
		global_basis = Basis(_ground_rotation())
		gear.snap(true)
	else:
		global_position = pilot.global_position
		var up := planet.up_at(global_position) if planet != null else Vector3.UP
		var forward := -view_rotation().z
		forward -= up * forward.dot(up)
		if forward.length_squared() < 0.0001:
			forward = -pilot.global_basis.z
		global_basis = Basis(Rotations.look_rotation(forward.normalized(), up))
		state = State.FLYING
		_hover_hold = true
		gear.snap(false)
	visual.visible = true
	_hull.set_solid(true)
	pilot.climb_in()
	var gm := GameManager.instance
	if gm != null and not gm.is_game_over:
		gm.show_banner("NEW SHIP", 2.0)


# Thrust toward the input direction; with no input, drift and slowly coast to
# a stop (in the atmosphere only the sideways drift slows; falling is gravity's job).
func _fly(input: Vector2, delta: float) -> void:
	if input != Vector2.ZERO:
		_hover_hold = false
	var wants_boost := Input.is_physical_key_pressed(KEY_SHIFT) and input != Vector2.ZERO
	boosting = wants_boost and not _boost_locked

	if input == Vector2.ZERO:
		var planet := Planet.instance
		if planet != null and _atmosphere_weight(planet, global_position) > 0.0:
			var up := planet.up_at(global_position)
			var vertical := up * velocity.dot(up)
			velocity = vertical + (velocity - vertical).move_toward(Vector3.ZERO, coast_deceleration * delta)
		else:
			velocity = velocity.move_toward(Vector3.ZERO, coast_deceleration * delta)
		return

	var top_speed := boost_speed if boosting else move_speed
	var target := view_rotation() * Vector3(input.x, 0.0, -input.y) * top_speed
	if chute != null:
		# Hanging under the parachute: no boost, and thrust can only steer the drift.
		boosting = false
		var up := Planet.instance.up_at(global_position)
		target -= up * maxf(target.dot(up), 0.0)
		target = target.limit_length(chute_glide_speed)
	var rate := boost_acceleration if boosting else acceleration
	# Coming down from boost speed eases off gently instead of braking hard.
	if velocity.length() > top_speed and velocity.dot(target) > 0.0:
		rate = coast_deceleration * 2.0
	velocity = velocity.move_toward(target, rate * delta)


# On the ground: no driving; whatever speed is left bleeds off to a stop.
func _slide_to_stop(delta: float) -> void:
	boosting = false
	velocity = velocity.move_toward(Vector3.ZERO, ground_friction * delta)


# Lift straight up, speeding up as it climbs, then hand control back.
func _take_off(delta: float) -> void:
	boosting = false
	_takeoff_timer += delta
	var up := Planet.instance.up_at(global_position)
	var climb := takeoff_acceleration * _takeoff_timer
	# Mostly up, easing forward a little along the ground toward where the nose points.
	var forward := -global_basis.z
	forward -= up * forward.dot(up)
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	velocity = up * climb + forward * climb * takeoff_forward
	if _takeoff_timer >= takeoff_time or Planet.instance.altitude(global_position) >= takeoff_height:
		state = State.FLYING


# Wheels come down near the ground and fold away once climbing clear.
func _update_gear() -> void:
	var planet := Planet.instance
	if gear == null or planet == null:
		return
	var up := planet.up_at(global_position)
	gear.update_target(self, planet.altitude(global_position) - landing_clearance, velocity.dot(up))


# Too slow to stay up: sink, faster the slower the ship is going.
func _apply_gravity(planet: Planet, delta: float) -> void:
	if _hover_hold:
		return
	var weight := gravity_weight(global_position)
	if weight <= 0.0:
		return
	var up := planet.up_at(global_position)
	# Under a parachute the ship isn't flying any more: speed gives no lift.
	var lift := 0.0 if chute != null else clampf(velocity.length() / stall_speed, 0.0, 1.0)
	var pull := gravity_pull * weight * (1.0 - lift * lift)
	if pull <= 0.0:
		return
	var fall_speed := -velocity.dot(up)
	if fall_speed < max_fall_speed:
		velocity -= up * minf(pull * delta, max_fall_speed - fall_speed)


# How strongly gravity pulls at a point: 1 at the ground, fading evenly to 0
# at the top of the atmosphere, 0 out in space.
func gravity_weight(point: Vector3) -> float:
	var planet := Planet.instance
	if planet == null:
		return 0.0
	return clampf(1.0 - planet.altitude(point) / atmosphere_height, 0.0, 1.0)


# For following the curve of the ground: 1 through most of the atmosphere,
# fading to 0 over its top quarter.
func _atmosphere_weight(planet: Planet, point: Vector3) -> float:
	var alt := planet.altitude(point)
	return clampf((atmosphere_height - alt) / (atmosphere_height * 0.25), 0.0, 1.0)


# Running the meter dry locks boost until it refills to a quarter.
# Also drives the pilot's sprint while on foot (same meter).
func update_boost_meter(delta: float) -> void:
	if boost_energy <= 0.0:
		_boost_locked = true
		boosting = false
	elif _boost_locked and boost_energy >= 0.25:
		_boost_locked = false
	if boosting:
		boost_energy = maxf(0.0, boost_energy - delta / boost_duration)
		_recharge_wait = boost_recharge_delay
	elif _recharge_wait > 0.0:
		_recharge_wait -= delta
	else:
		boost_energy = minf(1.0, boost_energy + delta / boost_recharge_time)


# The only edge of the map is a ceiling high above the planet.
func _clamp_altitude(planet: Planet, pos: Vector3) -> Vector3:
	if planet.altitude(pos) <= max_altitude:
		return pos
	var up := planet.up_at(pos)
	var outward := velocity.dot(up)
	if outward > 0.0:
		velocity -= up * outward
	return planet.global_position + up * (planet.radius + max_altitude)


# Climb out (parked) or bail out (in flight): the camera goes first person.
# A parked ship stops dead; in flight the pilot keeps the ship's speed and the
# empty ship brakes to a hover.
func exit_ship() -> void:
	if not can_exit:
		return
	on_foot = true
	boosting = false
	if state == State.LANDED:
		velocity = Vector3.ZERO
	remove_from_group("player")
	pilot.step_out(self)


# Called by the pilot on climbing back in.
func board() -> void:
	on_foot = false
	_takeoff_armed = false
	if not is_in_group("player"):
		add_to_group("player")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_E:
		if enabled and not on_foot and can_exit:
			exit_ship()
			get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.physical_keycode == KEY_Q:
		if enabled and not on_foot and can_deploy_chute:
			deploy_chute()
			get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.physical_keycode == KEY_C:
		if enabled and not on_foot and chute != null:
			cut_chute()
			get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.physical_keycode == KEY_R:
		var gm := GameManager.instance
		if enabled and on_foot and replacement_wait <= 0.0 and pilot.active and not (gm != null and gm.is_game_over):
			_deliver_replacement()
			get_viewport().set_input_as_handled()


# Solid again (restarting the game).
func restore_hull() -> void:
	_hull.set_solid(true)


func deploy_chute() -> void:
	_hover_hold = false
	var up := Planet.instance.up_at(global_position)
	chute = Parachute.deploy(_chute_anchor(), up, 2.6, 4.2, chute_color, 0.012)


# Let the parachute go (it drifts down and stays on the ground); a new one is
# ready after the cooldown.
func cut_chute() -> void:
	if chute == null:
		return
	chute.cut()
	chute = null
	chute_cooldown = Parachute.COOLDOWN


# The open parachute slows the fall to chute_fall_speed and the drift to
# chute_glide_speed.
func _apply_chute(planet: Planet, delta: float) -> void:
	if chute != null:
		velocity = Parachute.drag(chute, velocity, planet.up_at(global_position),
			chute_fall_speed, chute_glide_speed, chute_drag, delta)


# Keeps the canopy over the tail; cuts it on touchdown, out of gravity, or when
# the ship is destroyed. Counts down the cooldown while packed.
func _update_chute(delta: float) -> void:
	if chute == null:
		chute_cooldown = maxf(0.0, chute_cooldown - delta)
		return
	if wrecked or state != State.FLYING or gravity_weight(global_position) <= 0.0:
		cut_chute()
		return
	chute.hold(_chute_anchor(), Planet.instance.up_at(global_position), velocity)


# The top of the tail, where the lines are attached.
func _chute_anchor() -> Vector3:
	return global_position + global_basis.y * 0.35 + global_basis.z * 1.0


# Plumes burn big while thrusting, shrink back while coasting to a stop or
# parked, and flare biggest while boosting or lifting off.
func _update_engines(delta: float) -> void:
	var goal := 0.4  # coasting / stopped in space
	if state == State.LANDED:
		goal = 0.3
	elif state == State.TAKING_OFF or boosting:
		goal = 2.0
	elif _thrusting:
		goal = 1.5
	engine_level = move_toward(engine_level, goal, delta * 3.0)
	boost_blend = move_toward(boost_blend, 1.0 if boosting else 0.0, delta * 3.0)
	var flare := maxf(engine_level - 1.0, 0.0)
	var idle := minf(engine_level, 1.0)
	for i in _thrusters.size():
		var ps := _thrusters[i]
		var base: Array = _thruster_base[i]
		ps.rate = base[0] * idle * (1.0 + 0.8 * flare)
		ps.speed = (base[1] as Vector2) * (0.5 + 0.5 * idle) * (1.0 + 0.8 * flare)
		ps.size = (base[2] as Vector2) * (0.6 + 0.4 * idle) * (1.0 + 0.5 * flare)


func _handle_aiming(delta: float) -> void:
	var from := global_basis.get_rotation_quaternion()
	var to := view_rotation().get_rotation_quaternion()
	if state == State.LANDED:
		to = _ground_rotation()
	elif state == State.TAKING_OFF:
		# Nose comes up from level toward the view as the ship climbs out.
		to = _ground_rotation().slerp(to, clampf(_takeoff_timer / takeoff_time, 0.0, 1.0))
	global_basis = Basis(Rotations.rotate_towards(from, to, turn_speed * delta))


# Level with the ground under the ship, nose kept on the heading it landed with.
func _ground_rotation() -> Quaternion:
	var up := Planet.instance.up_at(global_position)
	var forward := _landed_forward - up * _landed_forward.dot(up)
	if forward.length_squared() < 0.0001:
		# Came straight down nose-first: use the ship's up (its belly faced the ground) as the heading.
		forward = global_basis.y - up * global_basis.y.dot(up)
	if forward.length_squared() < 0.0001:
		forward = up.cross(Vector3.RIGHT)
	return Rotations.look_rotation(forward, up)
