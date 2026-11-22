extends Node3D
## Brief branching light from a lane ahead to a joining player or local ship.
const LIFETIME := 1.0
var highways: Node3D
var branches: Array[Dictionary] = []

func emit_join(ship: Node3D, route: int, sign: float) -> void:
	var node := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color("ffe0a0")
	material.emission_enabled = true
	material.emission = Color("ffd083")
	material.emission_energy_multiplier = 3.0
	node.material_override = material
	add_child(node)
	branches.append({"ship": ship, "route": route, "sign": sign, "age": 0.0, "node": node})
	_rebuild(branches.back())

func advance(delta: float) -> void:
	for i in range(branches.size() - 1, -1, -1):
		var branch := branches[i]
		branch.age += delta
		if not is_instance_valid(branch.ship) or branch.age >= LIFETIME:
			branch.node.queue_free()
			branches.remove_at(i)
			continue
		_rebuild(branch)

func clear_ship(ship: Node3D) -> void:
	for i in range(branches.size() - 1, -1, -1):
		if branches[i].ship == ship:
			branches[i].node.queue_free()
			branches.remove_at(i)

func _rebuild(branch: Dictionary) -> void:
	var route: Dictionary = highways.routes[branch.route]
	var ship: Node3D = branch.ship
	var along: float = (ship.global_position - route.start).dot(route.axis)
	var origin: Vector3 = highways.lane_point(branch.route, along + branch.sign * 48, branch.sign)
	var end := ship.global_position + ship.global_basis.x * 1.2
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	for j in 17:
		var t := float(j) / 16
		var bend := sin(PI * t)
		points.append(origin.lerp(end, t) + (Vector3.UP * sin(t * 12 + branch.age * 8) + ship.global_basis.x * cos(t * 9 - branch.age * 7)) * bend * 2.6)
	for j in 16: _tube(surface, points[j], points[j + 1], 0.18)
	for j in [4, 8, 11]:
		var tip: Vector3 = points[j] + ship.global_basis.x * (4.0 if j % 2 == 0 else -4.0) + Vector3.UP * 3
		_tube(surface, points[j], tip, 0.09)
	branch.node.mesh = surface.commit()
	var colour := Color("ffe0a0")
	colour.a = minf(1.0, (LIFETIME - float(branch.age)) * 4)
	branch.node.material_override.albedo_color = colour

func _tube(surface: SurfaceTool, a: Vector3, b: Vector3, radius: float) -> void:
	var axis := a.direction_to(b)
	var right := axis.cross(Vector3.UP if absf(axis.y) < 0.98 else Vector3.RIGHT).normalized() * radius
	var up := axis.cross(right).normalized() * radius
	for i in 6:
		var v := right * cos(i * TAU / 6) + up * sin(i * TAU / 6)
		var w := right * cos((i + 1) * TAU / 6) + up * sin((i + 1) * TAU / 6)
		for point in [a + v, b + v, b + w, a + v, b + w, a + w]: surface.add_vertex(point)
