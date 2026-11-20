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
	var target := world.target_position()
	var camera := world.camera
	var factor := maxf(size.x / source_view.size.x, size.y / source_view.size.y)
	var offset := (size - Vector2(source_view.size) * factor) * 0.5
	var point := camera.unproject_position(target) * factor + offset
	var safe := Rect2(30, 110, size.x - 60, size.y - 245)
	var colour := Color("f1c78b")
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
	var entry := world.layout.target(world.selected_id)
	var text := "%s  ·  %d m" % [entry.name, roundi(world.ship.position.distance_to(target))]
	var label_x := clampf(point.x - 140, 12, maxf(12, size.x - 330))
	draw_string(_font, Vector2(label_x, point.y + 30), text, HORIZONTAL_ALIGNMENT_LEFT, 320, 14, colour)
