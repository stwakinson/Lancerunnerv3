class_name ArtoisTargetHud
extends Control

var world: ArtoisSpace
var source_view: SubViewport
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func _draw() -> void:
	if world == null: return
	_draw_combat()
	var target := world.target_position()
	var camera := world.camera
	var factor := maxf(size.x / source_view.size.x, size.y / source_view.size.y)
	var offset := (size - Vector2(source_view.size) * factor) * 0.5
	var point := camera.unproject_position(target) * factor + offset
	var safe := Rect2(30, 110, size.x - 60, size.y - 245)
	var colour := Color("f57059") if world.target_entry().kind == "hostile" else Color("f1c78b")
	if camera.is_position_behind(target) or not safe.has_point(point):
		var local := camera.global_transform.affine_inverse() * target
		var direction := Vector2(local.x, -local.y)
		if direction.length_squared() < 0.01: direction = Vector2.DOWN
		direction = direction.normalized()
		var centre := safe.get_center()
		var kx := safe.size.x * 0.5 / absf(direction.x) if absf(direction.x) > 0.001 else INF
		var ky := safe.size.y * 0.5 / absf(direction.y) if absf(direction.y) > 0.001 else INF
		point = centre + direction * minf(kx, ky)
		var side := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([point + direction * 8, point - direction * 6 + side * 6, point - direction * 6 - side * 6]), colour)
	else:
		draw_arc(point, 13, 0, TAU, 32, colour, 1.5, true)
		draw_line(point + Vector2(-20, 0), point + Vector2(-14, 0), colour)
		draw_line(point + Vector2(14, 0), point + Vector2(20, 0), colour)
	var entry := world.target_entry()
	var text := "%s  ·  %d m" % [entry.name, roundi(world.ship.position.distance_to(target))]
	if entry.kind == "hostile": text += "  /  " + str(entry.notes)
	var label_x := clampf(point.x - 140, 12, maxf(12, size.x - 330))
	draw_string(_font, Vector2(label_x, point.y + 30), text, HORIZONTAL_ALIGNMENT_LEFT, 320, 14, colour)


func _draw_combat() -> void:
	var combat := world.combat
	var origin := Vector2(size.x - 280, 122)
	for i in 2:
		var value: float = combat.shield if i == 0 else combat.hull
		var maximum: float = combat.shield_max if i == 0 else combat.HULL_MAX
		var colour := Color("78c9e9") if i == 0 else Color("e8b879")
		var at := origin + Vector2(0, i * 35)
		draw_string(_font, at, ("SHIELD %d / %d" if i == 0 else "HULL %d / %d") % [roundi(value), roundi(maximum)], HORIZONTAL_ALIGNMENT_LEFT, 240, 13, colour)
		draw_rect(Rect2(at + Vector2(0, 7), Vector2(230, 5)), Color("182c38"))
		draw_rect(Rect2(at + Vector2(0, 7), Vector2(230 * value / maximum, 5)), colour)
	var weapon_text := "WEAPONS LOCKED / CRUISE" if world.cruise else "SPACE / " + (" + ".join(combat.weapons).replace("_", " ").to_upper())
	draw_string(_font, origin + Vector2(0, 84), weapon_text, HORIZONTAL_ALIGNMENT_LEFT, 260, 12, Color("bdd4dc"))
	var factor := maxf(size.x / source_view.size.x, size.y / source_view.size.y)
	var offset := (size - Vector2(source_view.size) * factor) * 0.5
	var aim: Vector3 = world.ship.position - world.ship.basis.z * 150
	var cross := world.camera.unproject_position(aim) * factor + offset
	draw_line(cross - Vector2(5, 0), cross + Vector2(5, 0), Color("8db4be"))
	draw_line(cross - Vector2(0, 5), cross + Vector2(0, 5), Color("8db4be"))
	for fighter in combat.enemies:
		if world.camera.is_position_behind(fighter.position): continue
		if world.ship.position.distance_to(fighter.position) > 900: continue
		var at := world.camera.unproject_position(fighter.position) * factor + offset
		var colour := Color("ef715b")
		draw_rect(Rect2(at - Vector2(10, 10), Vector2(20, 20)), colour, false, 1)
		draw_rect(Rect2(at + Vector2(-14, 15), Vector2(28 * float(fighter.get_meta("hull")) / 65.0, 3)), colour)
		draw_rect(Rect2(at + Vector2(-14, 20), Vector2(28 * float(fighter.get_meta("shield")) / 20.0, 2)), Color("78c9e9"))
