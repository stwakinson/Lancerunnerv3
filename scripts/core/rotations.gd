class_name Rotations
extends RefCounted


# Unity's Quaternion.RotateTowards: step from `from` toward `to` by at most max_degrees.
static func rotate_towards(from: Quaternion, to: Quaternion, max_degrees: float) -> Quaternion:
	var angle := rad_to_deg(from.angle_to(to))
	if angle <= 0.0001:
		return to
	return from.slerp(to, minf(1.0, max_degrees / angle)).normalized()


# Unity's Quaternion.LookRotation(forward, up), with Godot's -Z as forward.
static func look_rotation(forward: Vector3, up: Vector3 = Vector3.UP) -> Quaternion:
	if forward.length_squared() < 0.000001:
		return Quaternion.IDENTITY
	var f := forward.normalized()
	if absf(f.dot(up.normalized())) > 0.9999:
		up = Vector3.BACK if f.y > 0.0 else Vector3.FORWARD
	return Basis.looking_at(f, up).get_rotation_quaternion()
