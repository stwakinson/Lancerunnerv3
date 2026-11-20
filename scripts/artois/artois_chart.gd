class_name ArtoisChart
extends Control

signal target_selected(id: String)
signal navigation_requested(id: String)
signal closed

const MAP_RECT := Rect2(78, 159, 810, 448)
var world: ArtoisSpace
var _targets: Array
var _picker: OptionButton
var _title: Label
var _description: Label
var _distance: Label
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	_build()
	visible = false


func configure(space: ArtoisSpace) -> void:
	world = space
	_targets = world.layout.targets()
	for entry in _targets: _picker.add_item(entry.name)


func open_chart() -> void:
	visible = true
	_refresh()


func close_chart() -> void:
	visible = false
	closed.emit()


func _label(text: String, at: Vector2, dimensions: Vector2, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	add_child(label)
	return label


func _button(text: String, at: Vector2, dimensions: Vector2, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("183441")
	style.border_color = Color("71828b")
	style.set_border_width_all(1)
	button.add_theme_stylebox_override("normal", style)
	button.pressed.connect(action)
	add_child(button)


func _build() -> void:
	_label("ARTOIS  /  SYSTEM CHART", Vector2(78, 94), Vector2(750, 35), 27, Color("e4ded0"))
	_label("Click a location or choose a destination. North is up. Flight pauses while this chart is open.", Vector2(80, 135), Vector2(1000, 22), 12, Color("92afbe"))
	_button("CLOSE  /  M", Vector2(1060, 95), Vector2(140, 32), close_chart)
	_label("DESTINATION", Vector2(930, 182), Vector2(270, 25), 12, Color("e8bb82"))
	_picker = OptionButton.new()
	_picker.position = Vector2(930, 216)
	_picker.size = Vector2(270, 38)
	_picker.clip_text = true
	_picker.item_selected.connect(func(index: int) -> void: _select(str(_targets[index].id)))
	add_child(_picker)
	_title = _label("", Vector2(932, 278), Vector2(262, 60), 21, Color("e5c18e"))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description = _label("", Vector2(932, 355), Vector2(260, 100), 15, Color("a4bac3"))
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_distance = _label("", Vector2(932, 469), Vector2(260, 35), 17, Color("e4ded0"))
	_button("NAVIGATE", Vector2(930, 520), Vector2(270, 40), func() -> void:
		navigation_requested.emit(world.selected_id)
		close_chart())
	_button("TRACK ONLY", Vector2(930, 571), Vector2(270, 34), close_chart)
	_label("GATES   /   SETTLEMENTS   /   RUINS   /   FIELDS      •      GOLD: PLANET PORT", Vector2(80, 627), Vector2(1000, 25), 12, Color("92afbe"))


func map_point(point: Vector2) -> Vector2:
	var factor := minf(MAP_RECT.size.x / world.layout.map_size.x, MAP_RECT.size.y / world.layout.map_size.y)
	return MAP_RECT.position + (MAP_RECT.size - world.layout.map_size * factor) * 0.5 + point * factor


func _select(id: String) -> void:
	target_selected.emit(id)
	_refresh()


func _refresh() -> void:
	var entry := world.layout.target(world.selected_id)
	_title.text = entry.name
	_description.text = str(entry.kind).replace("_", " ").to_upper() + "\n" + str(entry.notes)
	_distance.text = "%s m from ship" % str(roundi(world.ship.position.distance_to(world.target_position())))
	for i in _targets.size():
		if _targets[i].id == world.selected_id: _picker.select(i)
	queue_redraw()


func _draw() -> void:
	if world == null: return
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.005, 0.015, 0.025, 0.94))
	draw_rect(Rect2(54, 78, 1172, 588), Color("0a1b27"))
	draw_rect(MAP_RECT, Color("07131f"))
	for i in range(1, 9):
		var x := MAP_RECT.position.x + MAP_RECT.size.x * i / 9.0
		draw_line(Vector2(x, MAP_RECT.position.y), Vector2(x, MAP_RECT.end.y), Color(0.3, 0.46, 0.55, 0.12))
	for i in range(1, 6):
		var y := MAP_RECT.position.y + MAP_RECT.size.y * i / 6.0
		draw_line(Vector2(MAP_RECT.position.x, y), Vector2(MAP_RECT.end.x, y), Color(0.3, 0.46, 0.55, 0.12))
	var factor := minf(MAP_RECT.size.x / world.layout.map_size.x, MAP_RECT.size.y / world.layout.map_size.y)
	for field in world.layout.fields:
		var centre := map_point(ArtoisLayout.point(field.map))
		var radii := ArtoisLayout.point(field.radii) * factor
		draw_set_transform(centre, 0, radii)
		draw_circle(Vector2.ZERO, 1.0, Color(0.42, 0.43, 0.59, 0.11))
		draw_set_transform(Vector2.ZERO)
		var points := PackedVector2Array()
		for i in 65:
			var angle := i * TAU / 64.0
			points.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
		draw_polyline(points, Color("647182"), 1.2, true)
		draw_string(_font, map_point(ArtoisLayout.point(field.label_map)), str(field.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8a99ad"))
	var player := map_point(world.layout.to_map(world.ship.position))
	var target := map_point(world.layout.to_map(world.target_position()))
	if MAP_RECT.has_point(player):
		draw_line(player, target, Color(0.85, 0.68, 0.4, 0.35), 1, true)
		draw_colored_polygon(PackedVector2Array([player + Vector2(0, -6), player + Vector2(-4, 4), player + Vector2(4, 4)]), Color("d8f0f4"))
	for entry in world.layout.locations:
		var at := map_point(ArtoisLayout.point(entry.map))
		var colour := Color("d6b37d")
		if "gate" in str(entry.kind): colour = Color("83c9dc")
		if entry.kind in ["ruin_gate", "ruin_castle", "shipyard", "guild", "wreck", "pirate_base"]: colour = Color("c18786")
		if entry.kind == "planet_dock": colour = Color("ffd18a")
		draw_circle(at, 3.5, colour)
		if entry.id == world.selected_id: draw_arc(at, 7, 0, TAU, 24, Color("ffd18a"), 1.5, true)
		var offset := Vector2(8, 14) if entry.kind == "planet_dock" else Vector2(8, 3)
		var name: String = entry.name
		if entry.id == "arras": name = "Arras (Ruined Gate)"
		if entry.id == "southern_outpost": name = "Unnamed Outpost"
		if entry.id == "southern_ship": name = "Unnamed Capital Ship"
		draw_string(_font, at + offset, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, colour)
	if world.layout.target(world.selected_id).kind == "field": draw_arc(target, 7, 0, TAU, 24, Color("ffd18a"), 1.5, true)
	draw_rect(MAP_RECT, Color("4b6475"), false, 1)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	if not MAP_RECT.has_point(event.position): return
	var nearest := ""
	var distance := 14.0
	for entry in world.layout.locations:
		var candidate := map_point(ArtoisLayout.point(entry.map)).distance_to(event.position)
		if candidate < distance:
			distance = candidate
			nearest = entry.id
	if not nearest.is_empty():
		_select(nearest)
		accept_event()
		return
	for field in world.layout.fields:
		var centre := map_point(ArtoisLayout.point(field.map))
		var factor := minf(MAP_RECT.size.x / world.layout.map_size.x, MAP_RECT.size.y / world.layout.map_size.y)
		var relative: Vector2 = (event.position - centre) / (ArtoisLayout.point(field.radii) * factor)
		if relative.length_squared() <= 1:
			_select(field.id)
			accept_event()
			return
