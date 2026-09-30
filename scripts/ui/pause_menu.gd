class_name PauseMenu
extends Control

# Esc pauses the game and opens a bar across the middle of the screen asking
# whether to return to the main menu. Resume (or Esc again) closes it and
# recaptures the mouse. Losing window focus opens it too, so alt-tabbing out
# mid-fight doesn't leave the ship flying blind.

const MENU_SCENE := "res://scenes/menu.tscn"

var is_open := false

var _dim: ColorRect
var _bar: Control
var _buttons: Array[Button] = []
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if SceneFader.busy:
		return
	if is_open:
		close()
	else:
		open()


func _notification(what: int) -> void:
	# Not while the game is still being prepared behind the loading screen.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not SceneFader.busy \
			and get_tree().current_scene == owner:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	get_tree().paused = true
	var cam := get_viewport().get_camera_3d() as CameraFollow
	if cam != null:
		cam.release_mouse()
	for b in _buttons:
		b.disabled = false
		b.scale = Vector2.ONE
	if not visible:
		_dim.modulate.a = 0.0
		_bar.scale.y = 0.0
		visible = true
	_animate(1.0)


func close() -> void:
	if not is_open:
		return
	is_open = false
	get_tree().paused = false
	var cam := get_viewport().get_camera_3d() as CameraFollow
	if cam != null:
		cam.capture_mouse()
	_animate(0.0)
	_tween.chain().tween_callback(hide)


func _return_to_menu() -> void:
	if SceneFader.busy:
		return
	for b in _buttons:
		b.disabled = true
	# Stays paused under the fade; the fader unpauses once the menu is loaded.
	SceneFader.change_scene(MENU_SCENE)


# The bar opens out from its center line while the screen dims behind it.
func _animate(to: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_dim, "modulate:a", to, 0.2)
	_tween.tween_property(_bar, "scale:y", to, 0.2)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_bar = Control.new()
	add_child(_bar)
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 0.5
	_bar.anchor_bottom = 0.5
	_bar.offset_top = -105.0
	_bar.offset_bottom = 105.0
	_bar.resized.connect(func() -> void: _bar.pivot_offset = _bar.size * 0.5)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.08, 0.9)
	_bar.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in [Control.PRESET_TOP_WIDE, Control.PRESET_BOTTOM_WIDE]:
		var line := ColorRect.new()
		line.color = Color(UiStyle.ACCENT, 0.8)
		_bar.add_child(line)
		line.set_anchors_and_offsets_preset(edge)
		if edge == Control.PRESET_TOP_WIDE:
			line.offset_bottom = 2.0
		else:
			line.offset_top = -2.0

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	_bar.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	column.add_child(UiStyle.label("RETURN TO MAIN MENU?", 30, true, 3))
	column.add_child(UiStyle.label("Your current mission will be lost.", 16, false, 0, Color(1, 1, 1, 0.65)))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)

	var menu_button := UiStyle.button("MAIN MENU", 20)
	menu_button.custom_minimum_size = Vector2(210, 0)
	menu_button.pressed.connect(_return_to_menu)
	row.add_child(menu_button)

	var resume_button := UiStyle.button("RESUME", 20)
	resume_button.custom_minimum_size = Vector2(210, 0)
	resume_button.pressed.connect(close)
	row.add_child(resume_button)

	_buttons = [menu_button, resume_button]
