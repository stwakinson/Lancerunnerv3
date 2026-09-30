class_name LandingGear
extends Node3D

# The player ship's landing gear: a nose leg that folds back into the nose
# and two main legs that fold in under the wings, each behind a pair of bay
# doors. Coming in low over the ground the doors swing open and the legs
# lower smoothly; after lifting off and climbing away they fold back up and
# the doors close. Sized so the wheels sit exactly on the ground when the
# ship is parked (the ship's center rests landing_clearance above it).
#
# Built in code under the ship's visual (which is in ship space: +Y up, -Z
# forward, hull bottom at y = 0.07), so it banks and blinks with the hull.

## Lowered when the ship is this low and not climbing...
@export var deploy_altitude := 8.0
## ...and raised once it's climbing above retract_altitude, or above this at all.
@export var retract_altitude := 4.0
@export var always_up_altitude := 11.0
## Seconds for the full sequence either way (doors, then legs).
@export var travel_time := 1.4

# 0 = stowed, 1 = down and locked.
var extension := 0.0
var _target := 0.0
var _legs: Array[Dictionary] = []


func _ready() -> void:
	var clearance: float = (get_parent().get_parent() as PlayerShipController).landing_clearance
	var ground_y := -clearance
	# Nose leg: hinged under the front fuselage, folds back (+Z).
	_build_leg(Vector3(0.0, 0.07, -0.52), ground_y, 0.04, Vector3(deg_to_rad(-90.0), 0.0, 0.0), 1)
	# Main legs: hinged under the wings, fold in toward the fuselage.
	_build_leg(Vector3(-0.46, 0.14, 0.22), ground_y, 0.05, Vector3(0.0, 0.0, deg_to_rad(90.0)), 2)
	_build_leg(Vector3(0.46, 0.14, 0.22), ground_y, 0.05, Vector3(0.0, 0.0, deg_to_rad(-90.0)), 2)
	_apply()


# Whether the gear should be heading down, from the ship's state and height.
func update_target(ship: PlayerShipController, altitude: float, climb_speed: float) -> void:
	if ship.state != PlayerShipController.State.FLYING:
		# Parked or still lifting off: down until clear of the ground.
		_target = 1.0 if ship.state == PlayerShipController.State.LANDED or altitude < retract_altitude else 0.0
	elif altitude > always_up_altitude or (altitude > retract_altitude and climb_speed > 0.5):
		_target = 0.0
	elif altitude < deploy_altitude and climb_speed <= 0.5:
		_target = 1.0


# Jump straight to stowed or down (restart, first frame).
func snap(down: bool) -> void:
	_target = 1.0 if down else 0.0
	extension = _target
	_apply()


func _process(delta: float) -> void:
	if is_equal_approx(extension, _target):
		return
	extension = move_toward(extension, _target, delta / travel_time)
	_apply()


# Doors swing open over the first 35%, the legs swing down over the rest,
# eased in and out so they start and settle gently.
func _apply() -> void:
	var doors := smoothstep(0.0, 0.35, extension)
	var legs := smoothstep(0.25, 1.0, extension)
	for leg in _legs:
		(leg.hinge as Node3D).rotation = (leg.stowed as Vector3).lerp(Vector3.ZERO, legs)
		for door in leg.doors:
			var d := door as Dictionary
			(d.node as Node3D).rotation = (d.axis as Vector3) * (d.open as float) * doors
	visible = extension > 0.001


func _build_leg(hinge_pos: Vector3, ground_y: float, wheel_radius: float, stowed: Vector3, wheels: int) -> void:
	var metal := _material(Color(0.2, 0.21, 0.23), 0.8, 0.4)
	var chrome := _material(Color(0.75, 0.77, 0.8), 1.0, 0.2)
	var rubber := _material(Color(0.04, 0.04, 0.04), 0.0, 0.9)

	var hinge := Node3D.new()
	hinge.position = hinge_pos
	add_child(hinge)
	# Strut from the hinge down to the axle, so the tyre just touches the ground.
	var axle_y := ground_y + wheel_radius - hinge_pos.y
	var length := -axle_y
	_part(hinge, _cylinder(0.022, length * 0.55), Vector3(0, -length * 0.275, 0), Vector3.ZERO, metal)       # upper strut
	_part(hinge, _cylinder(0.014, length * 0.5), Vector3(0, -length * 0.7, 0), Vector3.ZERO, chrome)         # oleo piston
	_part(hinge, _cylinder(0.028, 0.03), Vector3(0, -0.01, 0), Vector3.ZERO, metal)                          # hinge collar
	# Axle and wheel(s), side by side across the axle.
	var axle := Vector3(0, axle_y, 0)
	var spread := wheel_radius * 0.7 if wheels > 1 else 0.0
	_part(hinge, _cylinder(0.008, spread * 2.0 + wheel_radius * 0.8), axle, Vector3(0, 0, deg_to_rad(90.0)), chrome)
	for i in wheels:
		var x := (i - (wheels - 1) * 0.5) * spread * 2.0
		_part(hinge, _cylinder(wheel_radius, wheel_radius * 0.6), axle + Vector3(x, 0, 0), Vector3(0, 0, deg_to_rad(90.0)), rubber)
		_part(hinge, _cylinder(wheel_radius * 0.55, wheel_radius * 0.64), axle + Vector3(x, 0, 0), Vector3(0, 0, deg_to_rad(90.0)), chrome)

	# Two bay doors either side of the leg, hinged along their outer edges,
	# swinging down and out. The nose bay runs fore-aft; the main bays run
	# across the wing (the direction each leg folds).
	var doors: Array[Dictionary] = []
	var door_len := minf(length + wheel_radius, 0.3)
	var along_z := absf(stowed.x) > 0.0
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		var panel_size: Vector3
		var panel_offset: Vector3
		var axis: Vector3
		var open_angle: float
		if along_z:
			pivot.position = hinge_pos + Vector3(side * 0.035, 0.0, door_len * 0.5)
			panel_size = Vector3(0.03, 0.006, door_len)
			panel_offset = Vector3(-side * 0.015, -0.004, 0.0)
			axis = Vector3(0, 0, 1)
			open_angle = side * deg_to_rad(80.0)
		else:
			var inward := -signf(hinge_pos.x)
			pivot.position = hinge_pos + Vector3(inward * door_len * 0.5, 0.0, side * 0.035)
			panel_size = Vector3(door_len, 0.006, 0.03)
			panel_offset = Vector3(0.0, -0.004, -side * 0.015)
			axis = Vector3(1, 0, 0)
			open_angle = -side * deg_to_rad(80.0)
		add_child(pivot)
		_part(pivot, _box(panel_size), panel_offset, Vector3.ZERO, metal)
		doors.append({"node": pivot, "axis": axis, "open": open_angle})

	_legs.append({"hinge": hinge, "stowed": stowed, "doors": doors})


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 14
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m
