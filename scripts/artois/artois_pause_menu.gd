extends ColorRect
signal character_requested
signal resumed
signal quit_requested
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.015, 0.025, 0.045, 0.92)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.position = Vector2(-160, -145)
	column.name = "MenuOptions"
	column.custom_minimum_size = Vector2(320, 300)
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	var title := Label.new()
	title.text = "LANCERUNNER / PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for caption in ["RESUME", "CHARACTER / FACTIONS", "QUIT TO MAIN MENU"]:
		var button := Button.new()
		button.text = caption
		button.name = {"RESUME": "Resume", "CHARACTER / FACTIONS": "Character", "QUIT TO MAIN MENU": "Quit"}[caption]
		button.custom_minimum_size = Vector2(320, 58)
		button.pressed.connect(func() -> void:
			if caption == "RESUME": resumed.emit()
			elif caption == "CHARACTER / FACTIONS": character_requested.emit()
			else: quit_requested.emit())
		column.add_child(button)
	hide()
