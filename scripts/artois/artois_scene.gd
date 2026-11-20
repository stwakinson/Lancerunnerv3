extends "res://scripts/benchmark/artois_visual.gd"

const Picking = preload("res://scripts/artois/artois_picking.gd")
const Chart = preload("res://scripts/artois/artois_chart.gd")
const TargetHud = preload("res://scripts/artois/artois_target_hud.gd")
var chart: ArtoisChart
var target_hud: ArtoisTargetHud
var _notice := ""
var _notice_time := 0.0


func _create_space_world() -> Node3D:
	return preload("res://scenes/artois_space.tscn").instantiate()


func _create_landing_world() -> Node2D:
	return preload("res://scenes/planet_landing.tscn").instantiate()


func _context_label() -> String:
	return "ARTOIS   /   SYSTEM FLIGHT"


func _build_ui() -> void:
	super._build_ui()
	target_hud = TargetHud.new()
	target_hud.world = space_world
	target_hud.source_view = space_view
	add_child(target_hud)
	move_child(target_hud, get_node("Interface").get_index())
	var ui := get_node("Interface") as Control
	var map_button := _button(ui, "M  SYSTEM CHART", Vector2(678, 634), 190, toggle_chart)
	map_button.name = "SystemChartButton"
	chart = Chart.new()
	ui.add_child(chart)
	chart.configure(space_world)
	chart.target_selected.connect(space_world.select_target)
	chart.navigation_requested.connect(space_world.navigate_to)
	# Chart and target presentation sit below the transition fade.
	_fade.move_to_front()


func _update_labels() -> void:
	super._update_labels()
	if not landed:
		_heading.text = "ARTOIS"
		_subheading.text = "VALOIS SPACE  /  SYSTEM NAVIGATION"
		_section.text = "SYSTEM FLIGHT"
		_dock_button.text = "ENTER  LAND AT PORT"
		_dock_button.disabled = not space_world.docking_error().is_empty()
		_dock_button.tooltip_text = space_world.docking_error()
		_status.text = "ARTOIS   /   " + space_world.docking_error()
		if space_world.docking_error().is_empty(): _status.text = "DOCKING AVAILABLE   /   ENTER TO LAND"
		_hint.text = "W/S thrust · A/D/Q/E strafe · RMB steer · Shift+W cruise (5× / no fire) · C exit · X brake · LMB select · M chart"
	else:
		_dock_button.text = "ENTER  LAUNCH TO ARTOIS"
	if target_hud != null: target_hud.visible = not landed
	var ui := get_node_or_null("Interface")
	if ui != null and ui.has_node("SystemChartButton"):
		ui.get_node("SystemChartButton").visible = not landed


func _process(delta: float) -> void:
	if chart != null and chart.visible: return
	super._process(delta)
	if not landed and not transitioning:
		target_hud.queue_redraw()
		var world := space_world as ArtoisSpace
		var target := world.layout.target(world.selected_id)
		var distance := world.ship.position.distance_to(world.target_position())
		_notice_time = maxf(0.0, _notice_time - delta)
		var mode := "NAVIGATING" if world.autopilot else ("CRUISE" if world.cruise else "FLIGHT")
		_status.text = "%s   /   %s  %d m   /   SPEED %d m/s" % [mode, target.name, roundi(distance), roundi(world.speed)]
		if _notice_time > 0: _status.text = _notice
		elif world.docking_error().is_empty(): _status.text = "DOCKING AVAILABLE   /   ENTER TO LAND AT AGINCOURT PLANET PORT"
		_dock_button.disabled = not world.docking_error().is_empty()
		_dock_button.tooltip_text = world.docking_error()


func toggle_chart() -> void:
	if landed or transitioning or shop_panel.visible: return
	if chart.visible: chart.close_chart()
	else: chart.open_chart()


func toggle_docking() -> void:
	if transitioning or shop_panel.visible or (chart != null and chart.visible): return
	var world := space_world as ArtoisSpace
	if not landed:
		var error := world.docking_error()
		if not error.is_empty():
			_notice = error
			_notice_time = 4.0
			return
		world.brake()
	else:
		world.prepare_launch()
	await super.toggle_docking()
	_update_labels()


func _unhandled_input(event: InputEvent) -> void:
	if landed or transitioning or shop_panel.visible or (chart != null and chart.visible): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var factor := maxf(size.x / space_view.size.x, size.y / space_view.size.y)
		var offset := (size - Vector2(space_view.size) * factor) * 0.5
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var id := Picking.pick(space_world, (local - offset) / factor)
		if not id.is_empty():
			space_world.select_target(id)
			get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or transitioning or shop_panel.visible: return
	if chart.visible:
		if event.physical_keycode in [KEY_M, KEY_ESCAPE]:
			chart.close_chart()
			get_viewport().set_input_as_handled()
		return
	if not landed:
		var world := space_world as ArtoisSpace
		if (event.physical_keycode == KEY_W and (event.shift_pressed or Input.is_physical_key_pressed(KEY_SHIFT))) or (event.physical_keycode == KEY_SHIFT and Input.is_physical_key_pressed(KEY_W)):
			world.engage_cruise()
			get_viewport().set_input_as_handled()
			return
		match event.physical_keycode:
			KEY_M: toggle_chart()
			KEY_C: world.toggle_cruise()
			KEY_X: world.brake()
			KEY_T: world.align_to_target()
			KEY_G: world.navigate_to(world.selected_id)
			KEY_TAB:
				var targets := world.layout.targets()
				var index := 0
				for i in targets.size():
					if targets[i].id == world.selected_id: index = i
				world.select_target(targets[(index + 1) % targets.size()].id)
			_:
				super._unhandled_key_input(event)
				return
		get_viewport().set_input_as_handled()
	else:
		super._unhandled_key_input(event)


func _menu() -> void:
	if chart != null and chart.visible:
		chart.close_chart()
		return
	super._menu()
