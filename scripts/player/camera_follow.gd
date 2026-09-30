class_name CameraFollow
extends Camera3D

# Third-person chase camera for free 3D flight. The mouse sets the view
# direction (left/right = yaw, up/down = pitch); the camera sits behind and a
# little above the ship along that direction, so the ship is always in shot
# and the screen-center crosshair points where the ship is heading.
# On foot (first_person) the camera sits at the pilot's eyes instead.
# Press Z to toggle zoom for aiming (or hold right mouse), in the ship or on foot.
# The pause menu (Esc) frees the cursor; clicking in the game window captures it again.
# [ and ] change mouse sensitivity (remembered between sessions).

const SETTINGS_PATH := "user://settings.cfg"

@export var target: Node3D

@export_group("Placement")
@export var distance := 9.0
## How far above the ship (in view space) the camera sits, so the ship is below the crosshair.
@export var height := 2.2

@export_group("Mouse Look")
## Degrees, clockwise from above (Unity convention: positive turns right).
@export var yaw := 0.0
## Degrees, positive looks down (Unity convention).
@export var pitch := 10.0
## Kept short of +-90 so the view never flips over the top.
@export var pitch_limit := 80.0
## Degrees of rotation per pixel of mouse movement. Adjust in play with [ and ].
@export var mouse_sensitivity := 0.25
@export var invert_y := false
@export var lock_cursor := true
@export var follow_smooth_time := 0.08

@export_group("First Person")
## Height of the eyes above the pilot's center.
@export var eye_height := 0.07
@export var first_person_fov := 75.0
## Near clip plane on foot, small enough that the gun in hand isn't cut off.
@export var first_person_near := 0.005

@export_group("Zoom")
## Field of view while holding right mouse, in the ship and on foot.
@export var zoom_fov_ship := 22.0
@export var zoom_fov_on_foot := 32.0
@export var zoom_speed := 8.0

@export_group("Boost")
## Extra field of view (degrees) at full boost, for a sense of speed.
@export var boost_fov_kick := 10.0

@export_group("Aiming")
## Aim distance used when the crosshair isn't over anything.
@export var default_aim_distance := 100.0

@export_group("Shake")
@export var max_shake_offset := 0.35
@export var shake_decay := 2.5
@export var shake_frequency := 25.0

var sensitivity_message_timer := 0.0
## Eyes-of-the-pilot view (set while on foot).
var first_person := false
## 0..1, smoothed while zoomed in.
var zoom_blend := 0.0
## Zoom switched on with Z (stays on until Z is pressed again).
var zoom_toggled := false

var _follow_target := Vector3.ZERO
var _velocity := Vector3.ZERO
var _trauma := 0.0
var _captured := false
var _capture_frame := -1
var _just_captured := false
var _noise := FastNoiseLite.new()
var _time := 0.0
# Tilts the whole view so that level means level with the ground below,
# anywhere around the planet. Carried along as the player moves (never rebuilt
# from the world's up), so the heading stays steady all the way round.
var _up_frame := Quaternion.IDENTITY
var _base_fov := 55.0
var _base_near := 0.3


# Where the player is looking; movement and the ship's nose both follow it.
var view_rotation: Basis:
	get:
		return Basis(_up_frame) * Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(-yaw), 0.0))

# The view's up direction: straight up from the ground below.
var up_direction: Vector3:
	get:
		return _up_frame * Vector3.UP

var is_captured: bool:
	get:
		return _captured

# False on the frame the cursor was captured, so that click doesn't also fire.
var mouse_can_fire: bool:
	get:
		return not lock_cursor or (_captured and not _just_captured)


func _ready() -> void:
	process_priority = 100  # after the ship moves, like LateUpdate
	_base_fov = fov
	_base_near = near
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0
	if target != null:
		_follow_target = target.global_position

	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)

	if lock_cursor:
		_set_captured(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_captured(false)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_BRACKETLEFT:
				_change_sensitivity(1.0 / 1.25)
			KEY_BRACKETRIGHT:
				_change_sensitivity(1.25)
			KEY_Z:
				zoom_toggled = not zoom_toggled

	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		var game_over := GameManager.instance != null and GameManager.instance.is_game_over
		if not _captured and lock_cursor and not game_over:
			_set_captured(true)

	var motion := event as InputEventMouseMotion
	if motion != null and _captured:
		# Mouse up looks up (negative pitch), unless inverted. Slower while zoomed.
		var delta := motion.screen_relative * mouse_sensitivity * (fov / _normal_fov())
		yaw = fposmod(yaw + delta.x, 360.0)
		pitch = clampf(pitch + (-delta.y if invert_y else delta.y), -pitch_limit, pitch_limit)


func capture_mouse() -> void:
	if lock_cursor:
		_set_captured(true)


func release_mouse() -> void:
	_set_captured(false)


func _set_captured(capture: bool) -> void:
	if capture == _captured:
		return
	_captured = capture
	if capture:
		_capture_frame = Engine.get_process_frames()
		_just_captured = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _change_sensitivity(factor: float) -> void:
	mouse_sensitivity = clampf(mouse_sensitivity * factor, 0.02, 3.0)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.save(SETTINGS_PATH)
	sensitivity_message_timer = 1.5


func _process(delta: float) -> void:
	_time += delta
	if sensitivity_message_timer > 0.0:
		sensitivity_message_timer -= delta

	# The OS/browser can release the capture on its own (e.g. Esc on web).
	if _captured and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and Engine.get_process_frames() - _capture_frame > 30:
		_set_captured(false)

	# Runs after the ship (process_priority), so the ship saw the flag this frame.
	_just_captured = false

	if target == null:
		return

	_update_up_frame()

	var zooming := zoom_toggled or (_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	zoom_blend = move_toward(zoom_blend, 1.0 if zooming else 0.0, zoom_speed * delta)
	var zoomed_fov := zoom_fov_on_foot if first_person else zoom_fov_ship
	fov = lerpf(_normal_fov(), zoomed_fov, smoothstep(0.0, 1.0, zoom_blend))
	near = first_person_near if first_person else _base_near

	# Only the ship's position is smoothed; rotation follows the mouse directly,
	# so looking around stays crisp while movement still feels soft.
	if first_person:
		_follow_target = target.global_position
	else:
		_follow_target = _smooth_damp(_follow_target, target.global_position, follow_smooth_time, delta)
	_apply_transform()

	if _trauma > 0.0:
		# On foot the world is person-sized, so the same shake is much smaller.
		var strength := _trauma * _trauma * max_shake_offset * (0.1 if first_person else 1.0)
		var t := _time * shake_frequency
		var shake := Vector3(_noise.get_noise_2d(t, 0.0) * 0.5, _noise.get_noise_2d(0.0, t) * 0.5, 0.0) * (2.0 * strength)
		global_position += global_basis * shake
		_trauma = move_toward(_trauma, 0.0, shake_decay * delta)

	_keep_above_ground()


# Field of view before zooming: wider on foot, and kicked out while boosting.
func _normal_fov() -> float:
	if first_person:
		return first_person_fov
	var ship := target as PlayerShipController
	return _base_fov + (boost_fov_kick * ship.boost_blend if ship != null else 0.0)


func _apply_transform() -> void:
	var rot := view_rotation
	if first_person:
		global_transform = Transform3D(rot, _follow_target + up_direction * eye_height)
	else:
		global_transform = Transform3D(rot, _follow_target + rot.z * distance + rot.y * height)


# Tip the frame by however much "up" changed since last frame. Tipping by the
# smallest rotation each frame adds no twist, so what was straight ahead stays
# straight ahead as the player travels around the planet.
func _update_up_frame(snap := false) -> void:
	var planet := Planet.instance
	if planet == null:
		_up_frame = Quaternion.IDENTITY
		return
	var ground := planet.up_at(target.global_position)
	if snap:
		_up_frame = Quaternion(Vector3.UP, ground)
		return
	var current := _up_frame * Vector3.UP
	if current.dot(ground) < 0.9999999:
		_up_frame = (Quaternion(current, ground) * _up_frame).normalized()


# Looking up while landed would swing the camera under the surface; hold it just above.
# (On foot the eyes are already just above the ground, so only a sliver is kept.)
func _keep_above_ground() -> void:
	if Planet.instance != null:
		global_position = Planet.instance.push_out(global_position, 0.015 if first_person else 1.0)


# The world point under the screen-center crosshair: the first enemy it's over,
# or a far point straight ahead.
func aim_point() -> Vector3:
	var from := global_position
	var forward := -global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * 500.0, Layers.ENEMY)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	return from + forward * default_aim_distance


# amount is 0..1; repeated calls stack up to full strength.
func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func snap_to_target() -> void:
	if target == null:
		return
	_follow_target = target.global_position
	_velocity = Vector3.ZERO
	zoom_toggled = false
	_update_up_frame(true)
	_apply_transform()
	_keep_above_ground()


# Unity's Vector3.SmoothDamp (critically damped spring).
func _smooth_damp(current: Vector3, goal: Vector3, smooth_time: float, dt: float) -> Vector3:
	smooth_time = maxf(0.0001, smooth_time)
	var omega := 2.0 / smooth_time
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - goal
	var original_to := goal
	goal = current - change
	var temp := (_velocity + omega * change) * dt
	_velocity = (_velocity - omega * temp) * e
	var output := goal + (change + temp) * e
	if (original_to - current).dot(output - original_to) > 0.0:
		output = original_to
		_velocity = (output - original_to) / dt if dt > 0.0 else Vector3.ZERO
	return output
