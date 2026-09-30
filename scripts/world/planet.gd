class_name Planet
extends MeshInstance3D

# The planet below the arena. Solid: ships, the camera and bullets can't pass
# through its surface, and the player can land on it.

static var instance: Planet

var radius: float:
	get:
		return (mesh as SphereMesh).radius * global_basis.get_scale().x


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


# Height of a point above the surface (negative when inside).
func altitude(point: Vector3) -> float:
	return point.distance_to(global_position) - radius


# Straight up from the ground at the point below `point`.
func up_at(point: Vector3) -> Vector3:
	return (point - global_position).normalized()


# `point` moved out to `clearance` above the surface if it's any lower.
func push_out(point: Vector3, clearance: float) -> Vector3:
	var offset := point - global_position
	var min_distance := radius + clearance
	if offset.length() < min_distance:
		return global_position + offset.normalized() * min_distance
	return point
