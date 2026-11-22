class_name ArtoisTrafficRoutes
extends RefCounted
## Small authored filament graph; ships keep local harbour/field legs between trips.
var world: Node3D
var nodes: Array[Vector3] = []
var costs: Array = []
var next_hop: Array = []
var filaments := {}


func configure(space: Node3D) -> void:
	world = space
	for route in world.highways.routes:
		var prefix: String = "highway_" + str(route.id)
		for suffix in ["_a", "_b_exit", "_b", "_a_exit"]:
			nodes.append(world.highways.gates[prefix + suffix].position)
	for i in nodes.size():
		var row := []
		var next := []
		for j in nodes.size():
			var distance := nodes[i].distance_to(nodes[j])
			var opposite_ends := i / 4 == j / 4 and ((i % 4 in [0, 3]) != (j % 4 in [0, 3]))
			if opposite_ends: distance = INF
			row.append(0.0 if i == j else (distance / 35.0 if distance < 600 else INF))
			next.append(j if i != j and distance < 600 else -1)
		costs.append(row)
		next_hop.append(next)
	for i in world.highways.routes.size():
		for offset in [0, 2]:
			var a: int = i * 4 + offset
			var b: int = a + 1
			costs[a][b] = nodes[a].distance_to(nodes[b]) / 350.0 + 1.5
			next_hop[a][b] = b
			filaments[Vector2i(a, b)] = {"route": i, "sign": 1.0 if offset == 0 else -1.0}
	for k in nodes.size():
		for i in nodes.size():
			for j in nodes.size():
				if float(costs[i][k]) + float(costs[k][j]) < float(costs[i][j]):
					costs[i][j] = float(costs[i][k]) + float(costs[k][j])
					next_hop[i][j] = next_hop[i][k]


func harbour(id: String) -> Vector3:
	return world.layout.world(world.layout.target(id)) + Vector3(0, 20, 95)


func plan(from: Vector3, destination: Vector3) -> Array:
	var best := from.distance_to(destination) / 50.0
	var start := -1
	var end := -1
	for i in nodes.size():
		for j in nodes.size():
			var cost := from.distance_to(nodes[i]) / 50.0 + float(costs[i][j]) + nodes[j].distance_to(destination) / 50.0
			if cost < best:
				best = cost
				start = i
				end = j
	var result := []
	if start >= 0:
		# Approach from outside the entrance, so NPC travel visibly enters a ring.
		var next: int = next_hop[start][end]
		if next >= 0 and filaments.has(Vector2i(start, next)):
			result.append({"position": nodes[start] - nodes[start].direction_to(nodes[next]) * 50, "mode": "flight"})
		result.append({"position": nodes[start], "mode": "flight"})
		var cursor := start
		for guard in nodes.size():
			if cursor == end: break
			var step: int = next_hop[cursor][end]
			if step < 0: break
			var leg := {"position": nodes[step], "mode": "flight"}
			if filaments.has(Vector2i(cursor, step)):
				leg.mode = "filament"
				leg.merge(filaments[Vector2i(cursor, step)])
			result.append(leg)
			cursor = step
	result.append({"position": destination, "mode": "flight"})
	return result
