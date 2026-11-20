class_name ShipHull
extends StaticBody3D

# Collision geometry follows the banking visual. The parked skirt closes the
# gap under the fuselage so the pilot walks around the hull, not beneath it.

var top_height := 0.5
var _skirt: CollisionShape3D


# A solid copy of the model's triangles (following the visual as it banks).
func build(visual: Node3D, landing_clearance: float) -> void:
	var model := visual.get_node_or_null("ShipModel") as Node3D
	var to_visual := visual.global_transform.affine_inverse()
	var faces := PackedVector3Array()
	if model != null:
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf := to_visual * mi.global_transform
			for f in mi.mesh.get_faces():
				faces.append(xf * f)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var bounds := AABB()
	if not faces.is_empty():
		bounds = AABB(faces[0], Vector3.ZERO)
		for f in faces:
			bounds = bounds.expand(f)
		top_height = bounds.end.y
	name = "Hull"
	collision_layer = Layers.SHIP_HULL
	collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	# Parked, the gap under the belly is about the pilot's height: fill it in
	# (under the fuselage, not the wings) so they walk round the ship, not under it.
	var skirt := BoxShape3D.new()
	var depth := landing_clearance + 0.3
	skirt.size = Vector3(bounds.size.x * 0.35, depth, bounds.size.z * 0.8)
	_skirt = CollisionShape3D.new()
	_skirt.name = "Skirt"
	_skirt.shape = skirt
	_skirt.position = Vector3(bounds.get_center().x, bounds.position.y - depth * 0.5 + 0.05, bounds.get_center().z)
	_skirt.disabled = true
	add_child(_skirt)
	visual.add_child(self)


func update_parked(parked: bool) -> void:
	if _skirt.disabled == parked:
		_skirt.disabled = not parked


func set_solid(solid: bool) -> void:
	collision_layer = Layers.SHIP_HULL if solid else 0
