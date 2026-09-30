class_name WalkerRig
extends RefCounted

# Walk animation shared by the enemy GroundRobot and the friendly AllyTrooper.
# Both models use the same joint names, and each joint swings about its local
# X axis (positive = forward/up). The legs stride with the knee lifting on
# the forward swing and the feet kept flat, the body bobs, the left arm swings
# against the legs, and the weapon arm (right) and head track the aim height.

const JOINTS := ["Pelvis", "Torso", "Head", "UpperArm_L", "UpperArm_R", "LowerArm_L",
	"Thigh_L", "Thigh_R", "Shin_L", "Shin_R", "Foot_L", "Foot_R"]

## Stride cycles (in radians) per unit walked.
var stride_rate := 24.0
var hip_swing := 26.0
var knee_bend := 45.0
var arm_swing := 18.0
## The weapon's muzzle (the model's FirePoint node).
var muzzle: Node3D

var _joints := {}
var _pelvis_rest := Vector3.ZERO
var _phase := 0.0
var _walk_blend := 0.0
var _aim_pitch := 0.0


func _init(model: Node3D) -> void:
	for joint in JOINTS:
		_joints[joint] = model.find_child(joint, true, false) as Node3D
	_pelvis_rest = (_joints["Pelvis"] as Node3D).position
	muzzle = model.find_child("FirePoint", true, false) as Node3D


# `stride_speed` is how fast it's walking; `aim` points at what the weapon
# is aimed at (only its height above/below level matters).
func animate(delta: float, walking: bool, stride_speed: float, aim: Vector3, up: Vector3) -> void:
	_walk_blend = move_toward(_walk_blend, 1.0 if walking else 0.0, delta * 4.0)
	_phase = fmod(_phase + delta * stride_speed * stride_rate * _walk_blend, TAU)
	var swing := sin(_phase) * _walk_blend
	var lift := cos(_phase) * _walk_blend

	# Legs: the knee bends while that leg swings forward; feet stay flat.
	var hip_l := deg_to_rad(hip_swing) * swing
	var hip_r := -hip_l
	var knee_l := -deg_to_rad(knee_bend) * maxf(lift, 0.0)
	var knee_r := -deg_to_rad(knee_bend) * maxf(-lift, 0.0)
	_set_pitch("Thigh_L", hip_l)
	_set_pitch("Thigh_R", hip_r)
	_set_pitch("Shin_L", knee_l)
	_set_pitch("Shin_R", knee_r)
	_set_pitch("Foot_L", -(hip_l + knee_l))
	_set_pitch("Foot_R", -(hip_r + knee_r))

	# Body bobs twice per stride; the free arm swings with the opposite leg.
	(_joints["Pelvis"] as Node3D).position = _pelvis_rest + Vector3.DOWN * absf(swing) * 0.03
	_set_pitch("Torso", deg_to_rad(6.0) * _walk_blend)
	_set_pitch("UpperArm_L", -deg_to_rad(arm_swing) * swing)

	# Weapon arm and head track the aim height.
	var elevation := asin(clampf(aim.normalized().dot(up), -1.0, 1.0))
	elevation = clampf(elevation, deg_to_rad(-30.0), deg_to_rad(80.0))
	_aim_pitch = lerp_angle(_aim_pitch, elevation, minf(delta * 6.0, 1.0))
	_set_pitch("UpperArm_R", _aim_pitch - deg_to_rad(6.0) * _walk_blend)
	_set_pitch("Head", _aim_pitch * 0.5)


func _set_pitch(joint: String, angle: float) -> void:
	var n := _joints[joint] as Node3D
	if n != null:
		n.rotation.x = angle
