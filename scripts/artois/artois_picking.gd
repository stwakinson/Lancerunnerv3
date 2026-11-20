extends RefCounted
## Selection-only ray tests. No physics bodies are added to the blockout.

static func pick(world: ArtoisSpace, pixel: Vector2) -> String:
	var origin := world.camera.project_ray_origin(pixel)
	var direction := world.camera.project_ray_normal(pixel)
	var nearest := INF
	var selected := ""
	# A planet click tracks its landing port and blocks objects behind the planet.
	var planet_distance := _sphere(origin, direction, world.layout.world(world.layout.planet), float(world.layout.planet.radius))
	if planet_distance >= 0:
		nearest = planet_distance
		selected = world.DOCK_ID
	for fighter in world.combat.enemies:
		var distance := _sphere(origin, direction, fighter.global_position, 6.0)
		if distance >= 0 and distance < nearest:
			nearest = distance
			selected = str(fighter.get_meta("id"))
	if world.traffic != null:
		for actor in world.traffic.actors.values():
			if not actor.alive or not actor.node.visible: continue
			var distance := _sphere(origin, direction, actor.node.global_position, actor.radius)
			if distance >= 0 and distance < nearest:
				nearest = distance
				selected = actor.id
	for id in world.landmarks:
		var meshes: Array[Node] = world.landmarks[id].find_children("*", "MeshInstance3D", true, false)
		var bounds := AABB()
		var first := true
		for mesh in meshes:
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		if first: continue
		# Include gate openings and a small forgiving border around structures.
		var hit: Variant = bounds.grow(2.0).intersects_ray(origin, direction)
		if hit == null: continue
		var distance: float = (hit - origin).dot(direction)
		if distance >= 0 and distance < nearest:
			nearest = distance
			selected = id
	# Rocks select their named field; use each instance, never the empty volume.
	for id in world.field_nodes:
		var node: MultiMeshInstance3D = world.field_nodes[id]
		for i in node.multimesh.instance_count:
			var transform := node.global_transform * node.multimesh.get_instance_transform(i)
			var radius := maxf(transform.basis.x.length(), maxf(transform.basis.y.length(), transform.basis.z.length()))
			var distance := _sphere(origin, direction, transform.origin, radius)
			if distance >= 0 and distance < nearest:
				nearest = distance
				selected = id
	return selected


static func _sphere(origin: Vector3, direction: Vector3, centre: Vector3, radius: float) -> float:
	var offset := origin - centre
	var b := offset.dot(direction)
	var discriminant := b * b - offset.length_squared() + radius * radius
	if discriminant < 0: return -1.0
	var near := -b - sqrt(discriminant)
	var far := -b + sqrt(discriminant)
	return near if near >= 0 else far
