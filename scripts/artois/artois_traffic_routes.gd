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
		nodes.append(route.start)
		nodes.append(route.end)
	for i in nodes.size():
		var row := []
		var next := []
		for j in nodes.size():
			var distance := nodes[i].distance_to(nodes[j])
			row.append(0.0 if i == j else (distance / 50.0 if distance < 600 else INF))
			next.append(j if i != j and distance < 600 else -1)
		costs.append(row)
		next_hop.append(next)
	for i in world.highways.routes.size():
		var a: int = i * 2
		var b: int = a + 1
		costs[a][b] = nodes[a].distance_to(nodes[b]) / 350.0
		costs[b][a] = costs[a][b]
		next_hop[a][b] = b
		next_hop[b][a] = a
		filaments[Vector2i(a, b)] = true
		filaments[Vector2i(b, a)] = true
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
			result.append({"position": nodes[step], "mode": "filament" if filaments.has(Vector2i(cursor, step)) else "flight"})
			cursor = step
	result.append({"position": destination, "mode": "flight"})
	return result
