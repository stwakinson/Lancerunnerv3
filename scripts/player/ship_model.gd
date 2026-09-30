class_name ShipModel
extends RefCounted

# Puts the Spacecraft_1 model under a ship's visual pivot the same way the Unity
# scene builder did: scaled so its longest horizontal side is SHIP_LENGTH,
# centered on the ship horizontally, plus one exhaust emitter behind each
# "engine_glow" part (or "Thruster*" marker node). The model's nose already
# faces -Z (Godot's forward). Pass `scene` to use a different model, such as
# the enemy robot.

const SHIP_SCENE := preload("res://assets/models/Spacecraft_1.glb")
const SHIP_LENGTH := 2.4

const PLAYER_THRUST_CORE := Color(0.55, 0.85, 1.0)
const PLAYER_THRUST_TAIL := Color(0.25, 0.55, 1.0)
const ENEMY_THRUST_CORE := Color(1.0, 0.6, 0.45)
const ENEMY_THRUST_TAIL := Color(1.0, 0.15, 0.1)

static var _tinted_materials := {}


static func attach(visual: Node3D, thrust_core: Color, thrust_tail: Color, tint: Variant = null,
		scene: PackedScene = SHIP_SCENE) -> Node3D:
	var model := scene.instantiate() as Node3D
	model.name = "ShipModel"
	visual.add_child(model)

	var meshes := _meshes(model)
	var bounds := _bounds(meshes, model)
	var horizontal := maxf(bounds.size.x, bounds.size.z)
	var scale := SHIP_LENGTH / horizontal if horizontal > 0.001 else 1.0
	model.scale = Vector3.ONE * scale
	var center := bounds.get_center() * scale
	model.position = Vector3(-center.x, 0.0, -center.z)

	if tint != null:
		for mi in meshes:
			_apply_tint(mi, tint)

	# Thrusters behind each engine glow (back of the ship is +Z).
	var points: Array[Vector3] = []
	for mi in meshes:
		if not String(mi.name).contains("engine_glow"):
			continue
		var b := _to_local_of(visual, mi) * mi.get_aabb()
		points.append(Vector3(b.get_center().x, b.get_center().y, b.end.z))
	# ...or at marker nodes placed on the nozzles in the model.
	for marker in model.find_children("Thruster*", "Node3D", true, false):
		points.append(_to_local_of(visual, marker as Node3D).origin)
	if points.is_empty():
		points.append(Vector3(0.0, 0.0, SHIP_LENGTH * 0.5))

	var size := SHIP_LENGTH / 2.4
	for p in points:
		var holder := Node3D.new()
		holder.name = "Thruster"
		holder.position = p
		holder.rotation_degrees = Vector3(0.0, 180.0, 0.0)  # emit backwards
		visual.add_child(holder)

		var ps := FxParticles.new()
		ps.rate = 90.0
		ps.max_particles = 100
		ps.lifetime = Vector2(0.15, 0.3)
		ps.speed = Vector2(3.0 * size, 4.5 * size)
		ps.size = Vector2(0.22 * size, 0.34 * size)
		ps.start_color_a = thrust_core
		ps.start_color_b = thrust_core
		ps.shape = FxParticles.Shape.CONE
		ps.cone_angle = 6.0
		ps.shape_radius = 0.04 * size
		ps.color_keys = [[0.0, Color.WHITE], [1.0, thrust_tail]]
		ps.alpha_keys = [[0.0, 1.0], [1.0, 0.0]]
		ps.size_end = 0.1
		ps.lod_distance = 250.0
		holder.add_child(ps)

	return model


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


# Transform from `node` into `ancestor`'s local space (works before the first frame).
static func _to_local_of(ancestor: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _bounds(meshes: Array[MeshInstance3D], model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in meshes:
		var b := _to_local_of(model, mi) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


# Multiplies the hull color by `tint` so enemies read differently from the player.
static func _apply_tint(mi: MeshInstance3D, tint: Color) -> void:
	for s in mi.mesh.get_surface_count():
		var base := mi.get_active_material(s)
		if base == null:
			continue
		var key := [base.get_instance_id(), tint]
		if not _tinted_materials.has(key):
			var mat := base.duplicate() as Material
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).albedo_color = tint
			_tinted_materials[key] = mat
		mi.set_surface_override_material(s, _tinted_materials[key])
