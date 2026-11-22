extends ColorRect
signal resumed
signal quit_requested
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.015, 0.025, 0.045, 0.92)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.position = Vector2(-160, -110)
	column.custom_minimum_size = Vector2(320, 220)
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	var title := Label.new()
	title.text = "LANCERUNNER / PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for caption in ["RESUME", "QUIT TO MAIN MENU"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size = Vector2(320, 58)
		button.pressed.connect(func() -> void:
			if caption == "RESUME": resumed.emit()
			else: quit_requested.emit())
		column.add_child(button)
	hide()
