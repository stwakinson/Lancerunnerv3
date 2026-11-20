extends Control

# Isolated visual benchmark. Neither scene uses the combat mission's state,
# spawners or player controller. Enter is a preview transition, not real docking.

const Space = preload("res://scripts/benchmark/benchmark_space.gd")
const MarketState = preload("res://scripts/benchmark/landing_market_state.gd")
const ShopPanel = preload("res://scripts/benchmark/landing_shop_panel.gd")
const Hotspots = preload("res://scripts/benchmark/landing_shop_hotspots.gd")
const Landing = preload("res://scripts/benchmark/benchmark_landing.gd")
const PIXEL_SIZE := Vector2i(640, 360)
const INK := Color("0b1724")
const PAPER := Color("e0e5e5")
const MUTED := Color("8babb9")
const ACCENT := Color("e8b879")

var space_view: SubViewport
var landing_view: SubViewport
var space_world: Node3D
var landing_world: Node2D
var landed := false
var pixel_mode := true
var transitioning := false
var _space_image: TextureRect
var _landing_image: TextureRect
var _heading: Label
var _subheading: Label
var _status: Label
var _render_label: Label
var _dock_button: Button
var _pixel_button: Button
var _weather_button: Button
var _depth_button: Button
var _motion_button: Button
var _hint: Label
var _section: Label
var _fade: ColorRect
var _smoke := false
var market_state := MarketState.new()
var shop_panel: LandingShopPanel
var shop_hotspots: LandingShopHotspots
var _commodity_service: Button
var _equipment_service: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_smoke = "--benchmark-smoke" in OS.get_cmdline_user_args()
	market_state.load_state()
	_build_views()
	_build_ui()
	_update_labels()
	if _smoke:
		_run_smoke.call_deferred()


func _build_views() -> void:
	space_view = SubViewport.new()
	space_view.name = "SpaceViewport"
	space_view.size = PIXEL_SIZE
	space_view.own_world_3d = true
	space_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	space_view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(space_view)
	space_world = Space.new()
	space_view.add_child(space_world)
	_space_image = _image(space_view)
	landing_view = SubViewport.new()
	landing_view.name = "LandingViewport"
	landing_view.size = PIXEL_SIZE
	landing_view.disable_3d = true
	landing_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(landing_view)
	landing_world = Landing.new()
	landing_view.add_child(landing_world)
	_landing_image = _image(landing_view)
	_landing_image.visible = false
	shop_hotspots = Hotspots.new()
	add_child(shop_hotspots)
	shop_hotspots.shop_requested.connect(open_shop)
	shop_hotspots.visible = false


func _image(view: SubViewport) -> TextureRect:
	var image := TextureRect.new()
	image.texture = view.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return image


func _font(weight: int = 400) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["DejaVu Sans", "Liberation Sans", "sans-serif"])
	font.font_weight = weight
	return font


func _text(parent: Control, text: String, at: Vector2, font_size: int, colour: Color, weight := 400) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", _font(weight))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(INK, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, at: Vector2, width: float, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = Vector2(width, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", _font(600))
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", PAPER)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("132b3a")
	normal.border_color = Color("47606c")
	normal.set_border_width_all(1)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("254555")
	hover.border_color = ACCENT
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _build_ui() -> void:
	# Keep the interface at 1280x720 logical pixels and fit it to the window.
	var ui := Control.new()
	ui.name = "Interface"
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	ui.size = Vector2(1280, 720)
	var bar := ColorRect.new()
	bar.position = Vector2(0, 0)
	bar.size = Vector2(1280, 86)
	bar.color = Color(INK, 0.85)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar)
	_text(ui, "L A N C E R U N N E R", Vector2(36, 20), 24, PAPER, 700)
	_text(ui, "ARTOIS   /   ART DIRECTION BENCHMARK", Vector2(38, 55), 10, MUTED)
	_text(ui, "1415   /   THE ROAD TO AGINCOURT", Vector2(916, 28), 11, ACCENT, 600)
	_render_label = _text(ui, "", Vector2(916, 51), 10, MUTED)
	_section = _text(ui, "01  /  ATMOSPHERE & SILHOUETTE", Vector2(38, 118), 11, ACCENT, 600)
	_heading = _text(ui, "", Vector2(34, 139), 42, PAPER, 700)
	_subheading = _text(ui, "", Vector2(38, 194), 13, MUTED)
	_commodity_service = _button(ui, "1  COMMODITIES", Vector2(954, 108), 238, open_shop.bind("commodities"))
	_equipment_service = _button(ui, "2  SHIP OUTFITTER", Vector2(954, 154), 238, open_shop.bind("equipment"))
	var footer := ColorRect.new()
	footer.position = Vector2(0, 615)
	footer.size = Vector2(1280, 105)
	footer.color = Color(INK, 0.92)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(footer)
	_status = _text(ui, "", Vector2(38, 588), 11, ACCENT)
	_dock_button = _button(ui, "", Vector2(36, 634), 220, toggle_docking)
	_pixel_button = _button(ui, "", Vector2(270, 634), 190, toggle_pixels)
	_motion_button = _button(ui, "C  DRIFT: ON", Vector2(270, 634), 190, toggle_motion)
	_depth_button = _button(ui, "L  DEPTH: ON", Vector2(678, 634), 190, toggle_depth)
	_weather_button = _button(ui, "F  LANDING RAIN: ON", Vector2(474, 634), 190, toggle_weather)
	_button(ui, "ESC  MAIN MENU", Vector2(1044, 634), 200, _menu)
	_hint = _text(ui, "W/S thrust   ·   A/D strafe   ·   Q/E climb   ·   Shift boost   ·   Space fire   ·   RMB drag: look   ·   R: reset view", Vector2(38, 689), 11, MUTED)
	shop_panel = ShopPanel.new()
	ui.add_child(shop_panel)
	shop_panel.configure(market_state)
	shop_panel.closed.connect(_sync_shop_hotspots)
	_fade = ColorRect.new()
	_fade.color = Color(INK, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_resize_ui.bind(ui))
	_resize_ui(ui)


func _resize_ui(ui: Control) -> void:
	var factor := minf(size.x / 1280.0, size.y / 720.0)
	ui.scale = Vector2.ONE * factor
	ui.position = (size - Vector2(1280, 720) * factor) * 0.5
	if not pixel_mode:
		space_view.size = Vector2i(maxi(640, roundi(size.x)), maxi(360, roundi(size.y)))


func _process(delta: float) -> void:
	if _smoke or transitioning:
		return
	var pointer := get_local_mouse_position() / size * 2.0 - Vector2.ONE
	if landed:
		var pan := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		landing_world.advance(delta, pointer.clamp(Vector2(-1, -1), Vector2.ONE), pan, shop_panel.visible)
		_sync_shop_hotspots()
	else:
		var steering := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)))
		var thrust := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		space_world.advance(delta, steering, thrust, Input.is_physical_key_pressed(KEY_SHIFT), Input.is_physical_key_pressed(KEY_SPACE))
		_status.text = "EMBRY FIELD EDGE   /   AGINCOURT CASTLE %03d m   /   SPEED %02d" % [roundi(space_world.ship.position.distance_to(space_world.station.position) * 10), roundi(absf(space_world.speed) * 10)]


func toggle_pixels() -> void:
	pixel_mode = not pixel_mode
	space_view.size = PIXEL_SIZE if pixel_mode else Vector2i(maxi(640, roundi(size.x)), maxi(360, roundi(size.y)))
	space_view.msaa_3d = Viewport.MSAA_DISABLED if pixel_mode else Viewport.MSAA_2X
	_space_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_mode else CanvasItem.TEXTURE_FILTER_LINEAR
	# Landing art stays at its authored pixel grid in both space-render modes.
	_update_labels()


func toggle_depth() -> void:
	if landed:
		landing_world.parallax_enabled = not landing_world.parallax_enabled
		_update_labels()


func toggle_motion() -> void:
	if landed:
		landing_world.cinematic_motion = not landing_world.cinematic_motion
		_update_labels()


func toggle_weather() -> void:
	landing_world.weather_enabled = not landing_world.weather_enabled
	_weather_button.text = "F  LANDING RAIN: " + ("ON" if landing_world.weather_enabled else "OFF")


func toggle_docking() -> void:
	if transitioning or shop_panel.visible:
		return
	transitioning = true
	_sync_shop_hotspots()
	_dock_button.disabled = true
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.35)
	await tween.finished
	landed = not landed
	_space_image.visible = not landed
	_landing_image.visible = landed
	space_view.render_target_update_mode = SubViewport.UPDATE_DISABLED if landed else SubViewport.UPDATE_ALWAYS
	landing_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if landed else SubViewport.UPDATE_DISABLED
	if landed:
		landing_world.advance(0.0, Vector2.ZERO)
	_update_labels()
	tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 0.45)
	await tween.finished
	transitioning = false
	_dock_button.disabled = false
	_sync_shop_hotspots()


func _update_labels() -> void:
	_heading.text = "THE LOWER MARKET" if landed else "AGINCOURT APPROACH"
	_heading.position = Vector2(36, 102) if landed else Vector2(34, 139)
	_heading.add_theme_font_size_override("font_size", 28 if landed else 42)
	_subheading.position = Vector2(38, 142) if landed else Vector2(38, 194)
	_subheading.add_theme_font_size_override("font_size", 11 if landed else 13)
	_section.visible = not landed
	_commodity_service.visible = landed
	_equipment_service.visible = landed
	_pixel_button.visible = not landed
	_motion_button.visible = landed
	_depth_button.visible = landed
	_depth_button.text = "L  DEPTH: " + ("ON" if landing_world.parallax_enabled else "OFF")
	_motion_button.text = "C  DRIFT: " + ("ON" if landing_world.cinematic_motion else "OFF")
	_hint.text = "Mouse: look around   ·   A/D: pan   ·   R: centre view   ·   C: cinematic drift   ·   L: depth   ·   F: rain" if landed else "W/S thrust   ·   A/D strafe   ·   Q/E climb   ·   Shift boost   ·   Space fire   ·   RMB drag: look   ·   R: reset view"
	_subheading.text = "AGINCOURT CASTLE  /  ARTOIS  /  VALOIS SPACE" if landed else "ARTOIS SYSTEM  /  EMBRY FIELD EDGE  /  VALOIS SPACE"
	_dock_button.text = "ENTER  LAUNCH TO SPACE" if landed else "ENTER  PREVIEW DOCKING"
	_pixel_button.text = "P  SPACE: " + ("PIXEL" if pixel_mode else "SMOOTH")
	_render_label.text = "SPACE 640 × 360 · NEAREST" if pixel_mode else "SPACE NATIVE RESOLUTION · MSAA"
	_status.text = "DOCKED   /   CLICK COMMODITIES OR SHIP OUTFITTER TO TRADE" if landed else "EMBRY FIELD EDGE   /   DOCKING PREVIEW AVAILABLE"


func open_shop(kind: String) -> void:
	if not landed or transitioning or shop_panel.visible:
		return
	shop_panel.open_shop(kind)
	_sync_shop_hotspots()


func _sync_shop_hotspots() -> void:
	shop_hotspots.visible = landed and not transitioning and not shop_panel.visible
	shop_hotspots.sync_positions(size, landing_world.layers[3].position)


func _input(event: InputEvent) -> void:
	if shop_panel != null and shop_panel.visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		shop_panel.close_shop()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not landed and not transitioning and event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		space_world.orbit(event.relative)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or transitioning or shop_panel.visible:
		return
	var key := event as InputEventKey
	if key == null:
		return
	match key.physical_keycode:
		KEY_1: open_shop("commodities")
		KEY_2: open_shop("equipment")
		KEY_ENTER: toggle_docking()
		KEY_R:
			if landed:
				landing_world.reset_camera()
			else:
				space_world.reset_view()
		KEY_L: toggle_depth()
		KEY_C: toggle_motion()
		KEY_P: toggle_pixels()
		KEY_F: toggle_weather()
		KEY_ESCAPE: _menu()


func _menu() -> void:
	if shop_panel.visible:
		shop_panel.close_shop()
		return
	if not transitioning:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _run_smoke() -> void:
	while SceneFader.busy:
		await get_tree().process_frame
	var capture_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	for i in 8:
		space_world.advance(1.0 / 60, Vector2.ZERO, 0.0, false, false)
		await get_tree().process_frame
	var before: Vector3 = space_world.ship.position
	space_world.advance(0.25, Vector2(1, 1), 1.0, true, true)
	assert(space_world.ship.position.x > before.x, "Steering must move the ship")
	assert(space_world.speed > 0 and space_world.shots.size() == 1, "Thrust and firing must work")
	assert(space_world.asteroid_count == 355, "Near and distant asteroid populations must be present")
	assert(space_world.sky_material.get_shader_parameter("panorama") != null, "Generated nebula must be assigned")
	for i in 20:
		space_world.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true, false)
		await get_tree().process_frame
	assert(space_world.get_node("EngineTrails").get_child(0).mesh != null, "Exhaust ribbon must build geometry")
	await _capture(capture_dir, "artois-space.png")
	toggle_pixels()
	assert(space_view.size.x >= 640 and not pixel_mode)
	await _capture(capture_dir, "artois-space-smooth.png")
	toggle_pixels()
	assert(space_view.size == PIXEL_SIZE and pixel_mode)
	await toggle_docking()
	assert(landed and _landing_image.visible and not _space_image.visible)
	landing_world.advance(0.1, Vector2(1, 0.5))
	assert(landing_world.layers[3].position.x != landing_world.layers[1].position.x)
	assert(landing_world.layers.size() == 6, "Landing must have independent art and ambience planes")
	assert(landing_world.layers[3].texture.get_image().detect_alpha() != Image.ALPHA_NONE, "Market art must retain transparent cutouts")
	assert(landing_world.layers[5].texture.get_image().detect_alpha() != Image.ALPHA_NONE, "Foreground art must retain transparent cutouts")
	var prior_drift: bool = landing_world.cinematic_motion
	toggle_motion()
	assert(landing_world.cinematic_motion != prior_drift, "Drift control must toggle")
	toggle_motion()
	toggle_depth()
	landing_world.advance(0.1, Vector2.ONE, 1.0)
	for layer in landing_world.layers:
		assert(layer.position == Vector2.ZERO, "Depth off must flatten every plane")
	toggle_depth()
	for i in 60:
		landing_world.advance(1.0 / 60.0, Vector2.ONE, 1.0)
	assert(landing_world.manual_pan > 0.0, "Keyboard pan must move the viewpoint")
	assert(absf(landing_world.camera_position.x) <= landing_world.MAX_PAN.x, "Camera must stay inside overscan bounds")
	assert(landing_world.layers[3].position == landing_world.layers[4].position, "Street actors must stay attached to their ground plane")
	landing_world.reset_camera()
	assert(landing_world.manual_pan == 0.0 and landing_world.camera_position == Vector2.ZERO)
	landing_world.advance(0.1, Vector2.ZERO)

	toggle_weather()
	assert(not landing_world.weather_enabled)
	toggle_weather()
	assert(landing_world.weather_enabled)
	for i in 3:
		await get_tree().process_frame
	await _capture(capture_dir, "artois-landing.png")
	await toggle_docking()
	assert(not landed and _space_image.visible and not transitioning)
	var camera_before: Vector3 = space_world.camera.position
	space_world.orbit(Vector2(120, 20))
	space_world.advance(0.1, Vector2.ZERO, 0.0, false, false)
	assert(not space_world.camera.position.is_equal_approx(camera_before), "Orbit must change the camera")
	space_world.reset_view()
	for i in 180:
		space_world.advance(1.0 / 60.0, Vector2.ZERO, 0.0, false, false)
	var effects := space_world.get_node("EngineTrails")
	for lane in effects._samples:
		assert(lane.size() <= effects.CAPACITY, "Exhaust history must remain bounded")
		for sample in lane:
			assert(sample.age <= effects.LIFETIME, "Expired exhaust samples must be removed")
	print("PASS: benchmark movement, weapons, rendering modes, docking, parallax, weather and launch")
	get_tree().quit()


func _capture(directory: String, filename: String) -> void:
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	var error := get_viewport().get_texture().get_image().save_png(directory.path_join(filename))
	assert(error == OK, "Screenshot must save successfully")
