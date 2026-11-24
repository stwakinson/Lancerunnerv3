extends "res://scripts/benchmark/artois_visual.gd"

const Sortie = preload("res://scripts/artois/artois_sortie.gd")
const ContractPanel = preload("res://scripts/artois/artois_contract_panel.gd")
const Contact = preload("res://scripts/artois/artois_contact.gd")
const Picking = preload("res://scripts/artois/artois_picking.gd")
const Chart = preload("res://scripts/artois/artois_chart.gd")
const TargetHud = preload("res://scripts/artois/artois_target_hud.gd")
var free_mouse := false
var pause_menu: Control
var docked_id := "planet_dock"
var _landing_cache := {}
var mission := Sortie.new()
var contract_panel: Control
var contact_button: Button
var contact_hotspot: Button
var radio_label: Label
var contact_label: Label
var mission_label: Label
var _recovering := false
var chart: ArtoisChart
var target_hud: ArtoisTargetHud
var _notice := ""
var _notice_time := 0.0


func _ready() -> void:
	super._ready()
	_landing_cache["planet_dock"] = landing_world
	space_world.combat.configure(space_world, market_state)
	mission.configure(space_world)
	mission.changed.connect(_mission_changed)
	space_world.combat.player_destroyed.connect(func() -> void: _recover_from_defeat.call_deferred())
	shop_panel.closed.connect(_apply_loadout)
	var contact := Contact.new()
	contact.position = Vector2(330, 268)
	landing_world.layers[4].add_child(contact)
	_mission_changed()
	_sync_shop_hotspots()
	pause_menu = preload("res://scripts/artois/artois_pause_menu.gd").new()
	add_child(pause_menu)
	pause_menu.resumed.connect(_resume_game)
	pause_menu.quit_requested.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	_centre_cursor()
	_sync_mouse_mode()


func _apply_loadout() -> void:
	space_world.combat.configure(space_world, market_state)


func _mission_changed() -> void:
	if mission_label != null: mission_label.text = mission.summary()
	if contract_panel != null and contract_panel.visible: contract_panel.refresh()


func open_contract() -> void:
	if not landed or docked_id != "planet_dock" or transitioning or shop_panel.visible or contract_panel.visible: return
	space_world.reset_taps()
	contract_panel.open_panel()
	_sync_shop_hotspots()


func open_shop(kind: String) -> void:
	if contract_panel != null and contract_panel.visible: return
	space_world.reset_taps()
	super.open_shop(kind)


func _sync_shop_hotspots() -> void:
	super._sync_shop_hotspots()
	if contact_hotspot == null: return
	var available := landed and not transitioning and not shop_panel.visible and not contract_panel.visible
	shop_hotspots.visible = available
	contact_hotspot.visible = available and docked_id == "planet_dock"
	var factor := maxf(size.x / 640.0, size.y / 360.0)
	var offset := (size - Vector2(640, 360) * factor) * 0.5
	contact_hotspot.position = offset + (Vector2(314, 226) + landing_world.layers[3].position) * factor
	contact_hotspot.size = Vector2(32, 48) * factor


func _recover_from_defeat() -> void:
	if _recovering: return
	_recovering = true
	mission.fail()
	space_world.highways.reset()
	space_world.brake()
	space_world.ship.position = space_world.target_position(space_world.DOCK_ID) + Vector3(0, 0, 50)
	space_world.select_target(space_world.DOCK_ID)
	await toggle_docking()
	space_world.combat.repair()
	_recovering = false
	_notice = "SHIP RECOVERED AT PORT / REPAIRED / CONTACT FLUELLEN TO RETRY"
	_notice_time = 6.0


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
	for child in ui.get_children():
		if child is Button and child.text == "ESC  MAIN MENU": child.text = "ESC  PAUSE"
	var map_button := _button(ui, "M  SYSTEM CHART", Vector2(678, 634), 190, toggle_chart)
	map_button.name = "SystemChartButton"
	chart = Chart.new()
	ui.add_child(chart)
	chart.configure(space_world)
	chart.target_selected.connect(space_world.select_target)
	chart.navigation_requested.connect(space_world.navigate_to)
	radio_label = _text(ui, "", Vector2(38, 265), 12, Color("aacbd1"))
	contact_label = _text(ui, "", Vector2(38, 288), 11, Color("b5c4ca"))
	contact_label.size = Vector2(850, 46)
	contact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_label = _text(ui, "", Vector2(38, 238), 12, ACCENT)
	contact_button = _button(ui, "3  FLUELLEN / CONTRACT", Vector2(954, 200), 238, open_contract)
	contact_button.name = "PlanetContactButton"
	contact_hotspot = Button.new()
	contact_hotspot.name = "PlanetContactHotspot"
	contact_hotspot.tooltip_text = "Captain Fluellen / Test sortie contract (3)"
	contact_hotspot.focus_mode = Control.FOCUS_NONE
	contact_hotspot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var transparent := StyleBoxEmpty.new()
	contact_hotspot.add_theme_stylebox_override("normal", transparent)
	contact_hotspot.add_theme_stylebox_override("hover", transparent)
	contact_hotspot.add_theme_stylebox_override("pressed", transparent)
	contact_hotspot.pressed.connect(open_contract)
	add_child(contact_hotspot)
	move_child(contact_hotspot, ui.get_index())
	var badge := Label.new()
	badge.text = "FLUELLEN / CONTRACT"
	badge.position = Vector2(-55, -23)
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", ACCENT)
	contact_hotspot.add_child(badge)
	contract_panel = ContractPanel.new()
	ui.add_child(contract_panel)
	contract_panel.mission = mission
	contract_panel.market = market_state
	contract_panel.closed.connect(_sync_shop_hotspots)
	shop_panel.move_to_front()
	chart.move_to_front()
	contract_panel.move_to_front()
	# Chart and target presentation sit below the transition fade.
	_fade.move_to_front()


func _update_labels() -> void:
	super._update_labels()
	if not landed:
		_heading.text = "ARTOIS"
		_subheading.text = "VALOIS SPACE  /  SYSTEM NAVIGATION"
		_section.text = "SYSTEM FLIGHT"
		_dock_button.text = "J  LAND AT PORT" if space_world.docking_port() == "planet_dock" else "J  DOCK AT STATION"
		_dock_button.disabled = not space_world.docking_error().is_empty()
		_dock_button.tooltip_text = space_world.docking_error()
		_status.text = "ARTOIS   /   " + space_world.docking_error()
		if space_world.docking_error().is_empty(): _status.text = "DOCKING AVAILABLE   /   J TO LAND"
		_hint.text = "Mouse steer · LMB guns · RMB shield · Space cursor · H cargo · J dock · Tab boost · F missile · B repair · N ward · Shift+W cruise / S cancel · T target · M chart"
	else:
		_dock_button.text = "ENTER  LAUNCH TO ARTOIS"
		if docked_id != "planet_dock":
			var profile: Dictionary = market_state.markets.profile(docked_id)
			_heading.text = str(profile.name).to_upper()
			_subheading.text = "%s / STATION MARKET DECK" % str(profile.faction).to_upper()
			_status.text = "DOCKED / " + str(profile.notes)
			_hint.text = "Mouse: look around · A/D: pan · R: centre · C: drift · L: depth · F: vent mist · 1/2: shops"
			_weather_button.text = "F  VENT MIST: " + ("ON" if landing_world.weather_enabled else "OFF")
	if radio_label != null: radio_label.visible = not landed
	if contact_label != null: contact_label.visible = not landed
	if contact_button != null: contact_button.visible = landed and docked_id == "planet_dock"
	if target_hud != null: target_hud.visible = not landed
	var ui := get_node_or_null("Interface")
	if ui != null and ui.has_node("SystemChartButton"):
		ui.get_node("SystemChartButton").visible = not landed


func _boost_held() -> bool:
	return Input.is_physical_key_pressed(KEY_TAB)


func _fire_held() -> bool:
	return not free_mouse and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _process(delta: float) -> void:
	if pause_menu != null and pause_menu.visible: return
	_sync_mouse_mode()
	space_world.combat.guard_requested = not free_mouse and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not (landed or transitioning or _recovering or chart.visible or shop_panel.visible or contract_panel.visible)
	if not space_world.combat.guard_requested: space_world.combat.defence.guard_active = false
	if space_world.traffic != null:
		space_world.traffic.player_present = not landed and not transitioning and not _recovering
		if landed and not transitioning:
			space_world.traffic.advance(delta)
			space_world.loot.advance(delta)
	if _recovering: return
	if contract_panel != null and contract_panel.visible:
		landing_world.advance(delta, Vector2.ZERO, 0.0, true)
		_sync_shop_hotspots()
		return
	if chart != null and chart.visible: return
	if not landed and not transitioning:
		space_world.combat.ordnance.set_cursor(_space_pixel(get_local_mouse_position()))
		if not free_mouse and not space_world.autopilot:
			var offset := (get_local_mouse_position() / size - Vector2(0.5, 0.5)) * 2.0
			if offset.length() > 0.08: space_world.orbit(offset * delta * 170.0)
	super._process(delta)
	if not landed and not transitioning:
		radio_label.text = space_world.traffic.radio_line
		var contact: Dictionary = space_world.traffic.target_entry(space_world.selected_id)
		contact_label.text = str(contact.get("notes", ""))
		target_hud.queue_redraw()
		var world := space_world as ArtoisSpace
		var target := world.target_entry()
		var distance := world.ship.position.distance_to(world.target_position())
		_notice_time = maxf(0.0, _notice_time - delta)
		var mode := "NAVIGATING" if world.autopilot else ("CRUISE" if world.cruise else ("SPOOLING %.1fs" % world.cruise_spool if world.cruise_spool > 0 else "FLIGHT"))
		_status.text = "%s   /   %s  %d m   /   SPEED %d m/s" % [mode, target.name, roundi(distance), roundi(world.speed)]
		if world.highways.attached(): _status.text = world.highways.status()
		elif _notice_time > 0: _status.text = _notice
		elif world.docking_error().is_empty() and not world.cruise and world.cruise_spool == 0: _status.text = "DOCKING AVAILABLE / J AT " + str(world.port_catalog.profile(world.docking_port()).name).to_upper()
		if not world.loot.nearby_ids(world.loot.RANGE).is_empty() and not world.cruise and world.cruise_spool == 0 and not world.highways.attached(): _status.text = "H / COLLECT NEARBY CARGO   /   HOLD %d / %d" % [market_state.cargo_used(), market_state.capacity()]
		if world.combat.ordnance.message_time > 0: _status.text = world.combat.ordnance.message
		_dock_button.disabled = not world.docking_error().is_empty()
		_dock_button.tooltip_text = world.docking_error()


func toggle_chart() -> void:
	if landed or transitioning or shop_panel.visible: return
	space_world.reset_taps()
	if chart.visible: chart.close_chart()
	else: chart.open_chart()


func toggle_docking() -> void:
	if transitioning or shop_panel.visible or (contract_panel != null and contract_panel.visible) or (chart != null and chart.visible): return
	var world := space_world as ArtoisSpace
	if not landed:
		var error := world.docking_error()
		if not error.is_empty():
			_notice = error
			_notice_time = 4.0
			return
		world.brake()
		docked_id = world.docking_port()
		world.active_port = docked_id
		market_state.set_market(docked_id)
		_switch_landing(docked_id)
	else:
		world.prepare_launch()
		world.combat.configure(world, market_state)
		if mission.phase == "active": world.select_target(mission.TARGET_ID)
		elif mission.phase == "return": world.select_target(world.DOCK_ID)
	world.reset_taps()
	await super.toggle_docking()
	if landed: world.combat.repair()
	_update_labels()


func _switch_landing(id: String) -> void:
	landing_world.visible = false
	if not _landing_cache.has(id):
		var resource: PackedScene = load(market_state.markets.scene_path(id))
		var room := resource.instantiate()
		landing_view.add_child(room)
		_landing_cache[id] = room
	landing_world = _landing_cache[id]
	landing_world.visible = true
	landing_world.reset_camera()


func toggle_weather() -> void:
	super.toggle_weather()
	if landed and docked_id != "planet_dock":
		_weather_button.text = "F  VENT MIST: " + ("ON" if landing_world.weather_enabled else "OFF")


func _space_pixel(local: Vector2) -> Vector2:
	var factor := maxf(size.x / space_view.size.x, size.y / space_view.size.y)
	var offset := (size - Vector2(space_view.size) * factor) * 0.5
	return (local - offset) / factor


func _unhandled_input(event: InputEvent) -> void:
	if landed or transitioning or shop_panel.visible or (chart != null and chart.visible) or (pause_menu != null and pause_menu.visible): return
	if event is InputEventMouseMotion:
		if not free_mouse and event.relative.length_squared() > 0: space_world.autopilot = false
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		space_world.combat.ordnance.set_cursor(_space_pixel(local))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and free_mouse:
		var factor := maxf(size.x / space_view.size.x, size.y / space_view.size.y)
		var offset := (size - Vector2(space_view.size) * factor) * 0.5
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var id := Picking.pick(space_world, (local - offset) / factor)
		if not id.is_empty():
			space_world.select_target(id)
			get_viewport().set_input_as_handled()
		return
	# RMB is the active shield; mouse steering is sampled in _process.


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or transitioning or shop_panel.visible or _recovering or contract_panel.visible or (pause_menu != null and pause_menu.visible): return
	if chart.visible:
		if event.physical_keycode in [KEY_M, KEY_ESCAPE]:
			chart.close_chart()
			get_viewport().set_input_as_handled()
		return
	if not landed:
		var world := space_world as ArtoisSpace
		if (event.physical_keycode == KEY_W and (event.shift_pressed or Input.is_physical_key_pressed(KEY_SHIFT))) or (event.physical_keycode == KEY_SHIFT and Input.is_physical_key_pressed(KEY_W)):
			world.reset_taps()
			world.engage_cruise()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_S: world.cancel_cruise()
		if event.physical_keycode in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_Q, KEY_E]:
			world.tap_direction(event.physical_keycode, Time.get_ticks_msec() / 1000.0)
		match event.physical_keycode:
			KEY_SPACE:
				free_mouse = not free_mouse
				if not free_mouse: _centre_cursor()
				space_world.reset_taps()
				_sync_mouse_mode()
			KEY_J, KEY_ENTER: toggle_docking()
			KEY_H:
				var result: Dictionary = world.loot.pickup()
				if not str(result.error).is_empty(): world.combat.ordnance.notify(str(result.error))
			KEY_F: world.combat.ordnance.launch()
			KEY_Z: world.combat.ordnance.cycle_missile()
			KEY_B: world.combat.ordnance.use_recovery("armourer_mites")
			KEY_N: world.combat.ordnance.use_recovery("ward_phial")
			KEY_V:
				var contacts := world.traffic.nearby_ids()
				if not contacts.is_empty(): world.select_target(contacts[(contacts.find(world.selected_id) + 1) % contacts.size()])
			KEY_M: toggle_chart()
			KEY_C: world.toggle_cruise()
			KEY_X: world.brake()
			KEY_Y: world.align_to_target()
			KEY_G: world.navigate_to(world.selected_id)
			KEY_T:
				var targets := world.layout.targets()
				for fighter in world.combat.enemies: targets.append({"id": str(fighter.get_meta("id"))})
				for id in world.traffic.nearby_ids(): targets.append({"id": id})
				for id in world.loot.nearby_ids(): targets.append({"id": id})
				var index := 0
				for i in targets.size():
					if targets[i].id == world.selected_id: index = i
				world.select_target(targets[(index + 1) % targets.size()].id)
			_:
				super._unhandled_key_input(event)
				return
		get_viewport().set_input_as_handled()
	else:
		if event.physical_keycode == KEY_3:
			open_contract()
			get_viewport().set_input_as_handled()
		else: super._unhandled_key_input(event)


func _input(event: InputEvent) -> void:
	if pause_menu != null and pause_menu.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE: _resume_game()
		if event is InputEventKey or event is InputEventMouse:
			if event is InputEventKey: get_viewport().set_input_as_handled()
		return
	if contract_panel != null and contract_panel.visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		contract_panel.close_panel()
		get_viewport().set_input_as_handled()
		return
	super._input(event)


func _menu() -> void:
	if contract_panel != null and contract_panel.visible:
		contract_panel.close_panel()
		return
	if chart != null and chart.visible:
		chart.close_chart()
		return
	if shop_panel.visible:
		shop_panel.close_shop()
		return
	if not transitioning:
		pause_menu.show()
		space_world.process_mode = Node.PROCESS_MODE_DISABLED
		target_hud.queue_redraw()
		space_world.reset_taps()
		space_world.combat.guard_requested = false
		space_world.combat.defence.guard_active = false
		space_world.combat.defence.update_visual(space_world.cruise_spool / space_world.CRUISE_SPOOL_TIME)
		_sync_mouse_mode()


func _resume_game() -> void:
	pause_menu.hide()
	space_world.process_mode = Node.PROCESS_MODE_INHERIT
	_sync_mouse_mode()


func _sync_mouse_mode() -> void:
	var interactive := landed or free_mouse or transitioning or chart.visible or shop_panel.visible or contract_panel.visible or (pause_menu != null and pause_menu.visible)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if interactive else Input.MOUSE_MODE_HIDDEN
	var ui := get_node_or_null("Interface")
	if ui != null:
		for child in ui.get_children():
			if child is Button: child.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _centre_cursor() -> void:
	Input.warp_mouse(get_viewport().get_final_transform() * (get_global_transform_with_canvas() * (size * 0.5)))
