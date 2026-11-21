class_name ArtoisPlaceholders
extends RefCounted

# Shared simple geometry is deliberately separate from locations and flight.
# These are visual landmarks, not combat/docking interiors or final assets.
var _materials := {}


func material(hex: String, glow := false) -> StandardMaterial3D:
	var key := hex + str(glow)
	if not _materials.has(key):
		var result := StandardMaterial3D.new()
		result.albedo_color = Color.html(hex)
		result.roughness = 0.85
		if glow:
			result.emission_enabled = true
			result.emission = Color.html(hex)
			result.emission_energy_multiplier = 1.4
		_materials[key] = result
	return _materials[key]


func block(parent: Node3D, at: Vector3, dimensions: Vector3, hex: String, glow := false) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.material_override = material(hex, glow)
	node.position = at
	parent.add_child(node)


func ring(parent: Node3D, radius: float, hex: String) -> void:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 2
	mesh.outer_radius = radius + 2
	mesh.rings = 32
	mesh.ring_segments = 8
	node.mesh = mesh
	node.rotation.x = PI * 0.5
	node.material_override = material(hex)
	parent.add_child(node)


func make(entry: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = entry.id
	var kind: String = entry.kind
	match kind:
		"hyper_gate":
			# A larger dormant frame, visually distinct from golden highway rings.
			ring(node, 60, "526174")
			ring(node, 69, "75634b")
			for i in 4:
				var direction := Vector3(cos(i * PI / 2), sin(i * PI / 2), 0)
				block(node, direction * 65, Vector3(13, 13, 19), "333e54")
				block(node, direction * 65 + Vector3(0, 0, 10), Vector3(5, 5, 1), "d3974e", true)
			var facing: Array = entry.get("facing", [0, 0, -1])
			node.rotation.y = atan2(-float(facing[0]), -float(facing[2]))
		"gate", "planet_dock":
			var radius := 38.0 if kind == "gate" else 18.0
			ring(node, radius, "556c83")
			for side in [-1.0, 1.0]:
				block(node, Vector3(side * radius, 0, 0), Vector3(7, 25, 9), "333e54")
				block(node, Vector3(side * radius, 0, 5), Vector3(1.4, 17, 0.4), "81d4e3", true)
			if kind == "planet_dock":
				for z in range(10, 61, 10):
					block(node, Vector3(-6, -9, z), Vector3(0.5, 0.3, 1.0), "ecc28b", true)
					block(node, Vector3(6, -9, z), Vector3(0.5, 0.3, 1.0), "ecc28b", true)
		"ruin_gate":
			for i in 10:
				if i in [1, 2, 7]: continue
				var angle := i * TAU / 10.0
				block(node, Vector3(cos(angle), sin(angle), 0) * 28, Vector3(9, 8, 7), "54495c")
		"castle", "ruin_castle", "cathedral":
			var ruined := kind == "ruin_castle"
			block(node, Vector3(0, -5, 0), Vector3(37, 5, 28), "343947")
			block(node, Vector3(0, 2, 0), Vector3(25, 10, 16), "62647a")
			for x in [-15.0, 15.0]:
				for z in [-10.0, 10.0]:
					if ruined and x > 0 and z > 0: continue
					block(node, Vector3(x, 8, z), Vector3(6, 25 if not ruined else 12, 6), "61637b")
					block(node, Vector3(x, 10, z + 3.1), Vector3(1.2, 4, 0.2), "e5b77a" if not ruined else "9d574f", true)
			if kind == "cathedral":
				block(node, Vector3(0, 21, 0), Vector3(3, 26, 3), "8791a3")
				block(node, Vector3(0, 29, 0), Vector3(14, 3, 3), "8791a3")
		"shipyard":
			for x in [-18.0, 18.0]:
				block(node, Vector3(x, 0, 0), Vector3(4, 5, 70), "525463")
				for z in [-25.0, 0.0, 25.0]: block(node, Vector3(x, 11, z), Vector3(3, 22, 3), "525463")
			block(node, Vector3(0, -3, 20), Vector3(40, 4, 5), "3d3946")
		"capital_ship", "wreck":
			block(node, Vector3.ZERO, Vector3(14, 10, 75), "675a68")
			block(node, Vector3(0, 9, -18), Vector3(8, 10, 17), "858397")
			block(node, Vector3(0, -2, 10), Vector3(37, 4, 20), "5b586e")
			if kind == "wreck": node.rotation_degrees = Vector3(18, 35, -25)
			else: block(node, Vector3(0, 0, 38), Vector3(9, 5, 1), "80ccdf", true)
		_:
			var hex := "80616b" if kind in ["pirate_base", "guild"] else "617386"
			block(node, Vector3(0, -2, 0), Vector3(30, 4, 25), "323d4e")
			for x in [-9.0, 0.0, 9.0]:
				block(node, Vector3(x, 3, 0), Vector3(7, 10 + absf(x) * 0.3, 14), hex)
				block(node, Vector3(x, 4, 7.1), Vector3(3, 2, 0.2), "e3b483" if kind != "pirate_base" else "d56f66", true)
	return node
