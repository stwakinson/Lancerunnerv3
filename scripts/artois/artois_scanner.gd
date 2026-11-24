extends RefCounted
## Heading-relative Artois scope; world actors, not the original demo's groups.
const RANGE := 1800.0

static func project(ship: Node3D, position: Vector3) -> Vector3:
	return ship.global_basis.inverse() * (position - ship.global_position)

static func draw_scope(canvas: Control, world: ArtoisSpace, font: Font) -> void:
	var centre := Vector2(canvas.size.x - 130, canvas.size.y - 205)
	var radius := 82.0
	var green := Color("77dfbc")
	canvas.draw_circle(centre, radius + 4, Color(0.01, 0.04, 0.04, 0.85))
	for ring in [0.33, 0.66, 1.0]: canvas.draw_arc(centre, radius * ring, 0, TAU, 64, Color(green, 0.4), 1, true)
	canvas.draw_line(centre - Vector2(radius, 0), centre + Vector2(radius, 0), Color(green, 0.2))
	canvas.draw_line(centre - Vector2(0, radius), centre + Vector2(0, radius), Color(green, 0.2))
	var sweep := Vector2(sin(world.elapsed * 2), -cos(world.elapsed * 2))
	canvas.draw_line(centre, centre + sweep * radius, Color(green, 0.55), 1.5, true)
	var contacts: Array = []
	for entry in world.layout.targets():
		contacts.append({"id": entry.id, "position": world.target_position(entry.id), "colour": Color("a6b7b1")})
	for actor in world.traffic.actors.values():
		if actor.alive and actor.node.visible: contacts.append({"id": actor.id, "position": actor.node.position, "colour": Color("ff765f") if world.law.enemy(actor) else Color("83ceef")})
	for fighter in world.combat.enemies: contacts.append({"id": str(fighter.get_meta("id")), "position": fighter.position, "colour": Color("ff765f")})
	for crate in world.loot.canisters.values(): contacts.append({"id": crate.id, "position": crate.node.position, "colour": Color("b7e6a3")})
	for contact in contacts:
		var local := project(world.ship, contact.position)
		if local.length() > RANGE: continue
		var at := centre + Vector2(local.x, local.z) / RANGE * radius
		var colour: Color = Color("ffd18a") if contact.id == world.selected_id else contact.colour
		canvas.draw_circle(at, 3 if contact.id == world.selected_id else 2, colour)
		if absf(local.y) > 100: canvas.draw_line(at, at + Vector2(0, -5 if local.y > 0 else 5), colour)
	canvas.draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -5), centre + Vector2(-3, 4), centre + Vector2(3, 4)]), Color.WHITE)
	canvas.draw_string(font, centre + Vector2(-82, -91), "SCANNER / 1.8 km", HORIZONTAL_ALIGNMENT_LEFT, 180, 12, green)
