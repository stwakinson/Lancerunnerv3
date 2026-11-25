extends RefCounted
const Pilgrim = preload("res://assets/models/pilgrim/pilgrim.glb")

static func apply(ship: Node3D, id: String) -> void:
	if str(ship.get_meta("purchased_hull", "")) == id: return
	if not ship.has_meta("original_hull_meshes"):
		var originals: Array = []
		for child in ship.get_children():
			if child is MeshInstance3D and child not in ship.engines: originals.append(child)
		ship.set_meta("original_hull_meshes", originals)
	for child in ship.get_meta("original_hull_meshes"): child.visible = id not in ["pilgrim", "interceptor"]
	var previous: Node = ship.get_node_or_null("PurchasedHull")
	if previous != null: previous.free()
	if id == "pilgrim":
		var model: Node3D = Pilgrim.instantiate()
		model.name = "PurchasedHull"
		model.scale = Vector3.ONE * 0.27
		ship.add_child(model)
	elif id == "interceptor":
		var model := Node3D.new()
		model.name = "PurchasedHull"
		ship.add_child(model)
		var pieces := [
			[Vector3(0, 0, -0.5), Vector3(0.85, 0.55, 4.8), "ddd5bf"],
			[Vector3(0, 0.42, -1.0), Vector3(0.6, 0.45, 1.4), "e3a253"],
			[Vector3(-1.1, 0, 0.7), Vector3(1.7, 0.22, 1.6), "8d3429"],
			[Vector3(1.1, 0, 0.7), Vector3(1.7, 0.22, 1.6), "8d3429"]]
		for piece in pieces:
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = piece[1]
			mesh.mesh = box
			mesh.position = piece[0]
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color.html(piece[2])
			mesh.material_override = mat
			model.add_child(mesh)
	ship.set_meta("purchased_hull", id)
