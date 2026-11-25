class_name ArtoisTargetHud
extends Control

const Scanner = preload("res://scripts/artois/artois_scanner.gd")
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
	Scanner.draw_scope(self, world, _font)
	draw_string(_font, Vector2(24, 280), "F2 / FACTION STANDINGS", HORIZONTAL_ALIGNMENT_LEFT, 340, 13, Color("edc38d"))
	if world.law.ledger_visible:
		draw_rect(Rect2(16, 294, 460, 220), Color(0.02, 0.04, 0.06, 0.95))
		var row := 0
		for id in world.law.Factions.data.factions:
			draw_string(_font, Vector2(28, 320 + row * 27), world.law.description(id), HORIZONTAL_ALIGNMENT_LEFT, 440, 14, Color("ff765f") if world.law.hostile(id) else Color("8ed4d7"))
			row += 1
		draw_string(_font, Vector2(28, 495), "Hostile at -50 / Assault -8 / Destruction -30", HORIZONTAL_ALIGNMENT_LEFT, 440, 13, Color("edc38d"))
	for crate in world.loot.canisters.values():
		if crate.id == world.selected_id or world.camera.is_position_behind(crate.node.position): continue
		if world.ship.position.distance_to(crate.node.position) > 500: continue
		var factor := maxf(size.x / source_view.size.x, size.y / source_view.size.y)
		var offset := (size - Vector2(source_view.size) * factor) * 0.5
		var at := world.camera.unproject_position(crate.node.position) * factor + offset
		draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color("b7e6a3"), false, 1)
	var target := world.target_position()
	var camera := world.camera
	var factor := maxf(size.x / source_view.size.x, size.y / source_view.size.y)
	var offset := (size - Vector2(source_view.size) * factor) * 0.5
	var point := camera.unproject_position(target) * factor + offset
	var safe := Rect2(30, 110, size.x - 60, size.y - 245)
	var colour := Color("f57059") if world.target_entry().kind == "hostile" else (Color("8ed4d7") if world.target_entry().kind == "local" else Color("f1c78b"))
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
	if entry.kind == "hostile" and not entry.has("pilot"): text += "  /  " + str(entry.notes)
	if entry.kind == "cargo": text += "  /  %d units" % int(world.loot.canisters[world.selected_id].quantity)
	var label_x := clampf(point.x - 140, 12, maxf(12, size.x - 330))
	draw_string(_font, Vector2(label_x, point.y + 30), text, HORIZONTAL_ALIGNMENT_LEFT, 320, 14, colour)


func _draw_combat() -> void:
	var combat := world.combat
	var origin := Vector2(size.x - 280, 122)
	draw_rect(Rect2(origin + Vector2(-12, -20), Vector2(272, 298)), Color(0.025, 0.06, 0.09, 0.7))
	var values := [combat.shield, combat.defence.armour, combat.hull, combat.defence.energy]
	var maxima := [combat.shield_max, combat.defence.armour_max, combat.hull_max, combat.defence.ENERGY_MAX]
	var names := ["WARD", "ARMOUR", "HULL", "ENERGY"]
	for i in 4:
		var colour := Color("78c9e9") if i == 0 else (Color("85dfbf") if i == 3 else Color("e8b879"))
		var at := origin + Vector2(0, i * 28)
		var caption := "%s %d / %d" % [names[i], roundi(values[i]), roundi(maxima[i])]
		if i == 3: caption += "   HOLD %d / %d" % [combat.ordnance.market.cargo_used(), combat.ordnance.market.capacity()]
		draw_string(_font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, 240, 13, colour)
		draw_rect(Rect2(at + Vector2(0, 7), Vector2(230, 5)), Color("182c38"))
		draw_rect(Rect2(at + Vector2(0, 7), Vector2(230 * values[i] / maxima[i], 5)), colour)
	draw_string(_font, origin + Vector2(0, 119), "RMB / KNIGHT SHIELD " + ("RAISED" if combat.defence.guard_active else "LOWERED"), HORIZONTAL_ALIGNMENT_LEFT, 260, 12, Color("edc38d"))
	var fitted := PackedStringArray()
	for id in combat.weapons:
		if not str(id).is_empty() and id != "missile_rack": fitted.append(str(id).replace("_", " ").to_upper())
	var weapon_text := "WEAPONS LOCKED / TRANSIT" if world.cruise or world.cruise_spool > 0 or world.highways.attached() else "LMB / " + (" + ".join(fitted) if not fitted.is_empty() else "NO GUNS FITTED")
	draw_string(_font, origin + Vector2(0, 152), weapon_text, HORIZONTAL_ALIGNMENT_LEFT, 260, 12, Color("bdd4dc"))
	var factor := maxf(size.x / source_view.size.x, size.y / source_view.size.y)
	var offset := (size - Vector2(source_view.size) * factor) * 0.5
	var aim: Vector3 = combat.ordnance.aim_point()
	var cross := world.camera.unproject_position(aim) * factor + offset
	draw_line(cross - Vector2(14, 0), cross + Vector2(14, 0), Color("eeb76b") if combat.ordnance.aim_clamped else Color("8de4e5"))
	draw_line(cross - Vector2(0, 14), cross + Vector2(0, 14), Color("eeb76b") if combat.ordnance.aim_clamped else Color("8de4e5"))
	draw_arc(cross, 10, 0, TAU, 32, Color("8de4e5"), 1.5, true)
	if combat.defence.guard_active:
		var guard_at := world.camera.unproject_position(world.ship.position + combat.defence.guard_direction * 350) * factor + offset
		draw_arc(guard_at, 20, 0, TAU, 40, Color("ffd18a"), 2.0, true)
	var ordnance := combat.ordnance
	var count := ordnance.market.owned(ordnance.selected_missile)
	draw_string(_font, origin + Vector2(0, 174), "F / %s  x%d     Z: CYCLE" % [ordnance.MISSILES[ordnance.selected_missile].name, count], HORIZONTAL_ALIGNMENT_LEFT, 270, 12, Color("edc38d"))
	var lock_text := "NO MISSILE RACK" if not combat.weapons.has("missile_rack") else ("LOCKED / F TO LAUNCH" if ordnance.lock_progress >= ordnance.LOCK_TIME else ("ACQUIRING %.1f / 1.5s" % ordnance.lock_progress if ordnance.lock_progress > 0 else "SELECT HOSTILE / WITHIN 20°"))
	draw_string(_font, origin + Vector2(0, 194), lock_text, HORIZONTAL_ALIGNMENT_LEFT, 270, 12, Color("8de4e5"))
	draw_rect(Rect2(origin + Vector2(0, 202), Vector2(230, 4)), Color("182c38"))
	draw_rect(Rect2(origin + Vector2(0, 202), Vector2(230 * ordnance.lock_progress / ordnance.LOCK_TIME, 4)), Color("8de4e5"))
	draw_string(_font, origin + Vector2(0, 228), "B / MITES %d    N / PHIALS %d" % [ordnance.market.owned("armourer_mites"), ordnance.market.owned("ward_phial")], HORIZONTAL_ALIGNMENT_LEFT, 270, 12, Color("edc38d"))
	if ordnance.recovery_cooldown > 0:
		draw_string(_font, origin + Vector2(0, 247), "RECOVERY READY IN %.1fs" % ordnance.recovery_cooldown, HORIZONTAL_ALIGNMENT_LEFT, 270, 12, Color("8babb9"))
	if world.disruption_remaining > 0:
		draw_string(_font, origin + Vector2(0, 268), "FETTERED / %.1fs" % world.disruption_remaining, HORIZONTAL_ALIGNMENT_LEFT, 270, 12, Color("ff926c"))
	if world.traffic != null:
		for actor in world.traffic.actors.values():
			if not actor.alive or not actor.node.visible or world.camera.is_position_behind(actor.node.position): continue
			if world.ship.position.distance_to(actor.node.position) > 1000: continue
			var at := world.camera.unproject_position(actor.node.position) * factor + offset
			if Rect2(origin + Vector2(-12, -20), Vector2(272, 298)).has_point(at): continue
			var colour := Color("e28262") if world.law.enemy(actor) else Color("8ed4d7")
			draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), colour, false, 1)
	for fighter in combat.enemies:
		if world.camera.is_position_behind(fighter.position): continue
		if world.ship.position.distance_to(fighter.position) > 900: continue
		var at := world.camera.unproject_position(fighter.position) * factor + offset
		if Rect2(origin + Vector2(-12, -20), Vector2(272, 298)).has_point(at): continue
		var colour := Color("ef715b")
		draw_rect(Rect2(at - Vector2(10, 10), Vector2(20, 20)), colour, false, 1)
		draw_rect(Rect2(at + Vector2(-14, 15), Vector2(28 * float(fighter.get_meta("hull")) / 65.0, 3)), colour)
		draw_rect(Rect2(at + Vector2(-14, 20), Vector2(28 * float(fighter.get_meta("shield")) / 20.0, 2)), Color("78c9e9"))
