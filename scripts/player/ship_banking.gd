class_name ShipBanking
extends Node3D

# Rolls the ship's visual (not the ship itself) into turns and strafes.
# Sits on a pivot between the ship and the model, so gameplay transforms are untouched.

## Largest roll angle in degrees.
@export var max_bank := 30.0
## Degrees of roll per degree/second of turning.
@export var turn_bank := 0.06
## Degrees of roll per unit/second of sideways movement.
@export var strafe_bank := 2.5
@export var responsiveness := 8.0

var last_position: Vector3
var last_forward: Vector3
var bank := 0.0


func _ready() -> void:
	process_priority = 50  # after gameplay movement, like LateUpdate
	var body := get_parent() as Node3D
	last_position = body.global_position
	last_forward = -body.global_basis.z


func _process(delta: float) -> void:
	if delta <= 0.0:
		return

	var body := get_parent() as Node3D
	var forward := -body.global_basis.z
	var yaw_rate := rad_to_deg(_heading_change(last_forward, forward, _up())) / delta
	var sideways := ((body.global_position - last_position) / delta).dot(body.global_basis.x)

	# Turning or moving right dips the right wing.
	var target_bank := clampf(-yaw_rate * turn_bank - sideways * strafe_bank, -max_bank, max_bank)
	bank = lerpf(bank, target_bank, 1.0 - exp(-responsiveness * delta))
	transform.basis = Basis(Vector3.BACK, deg_to_rad(bank))

	last_position = body.global_position
	last_forward = forward


# "Up" for measuring turns: the arena's up, or the ground's near the planet.
func _up() -> Vector3:
	var cam := get_viewport().get_camera_3d() as CameraFollow
	return cam.up_direction if cam != null else Vector3.UP


# Turn in radians from one heading to the next around `up` (turning right is positive).
static func _heading_change(from: Vector3, to: Vector3, up: Vector3) -> float:
	var a := from - up * from.dot(up)
	var b := to - up * to.dot(up)
	if a.length_squared() < 0.000001 or b.length_squared() < 0.000001:
		return 0.0
	return -a.signed_angle_to(b, up)
