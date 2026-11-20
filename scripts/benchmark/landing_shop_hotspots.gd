class_name LandingShopHotspots
extends Control

signal shop_requested(kind: String)

const AREAS := [Rect2(20, 218, 105, 65), Rect2(146, 225, 115, 58)]
var buttons: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 2:
		var button := Button.new()
		button.name = "CommodityShop" if i == 0 else "EquipmentShop"
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0, 0, 0, 0)
		button.add_theme_stylebox_override("normal", normal)
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.95, 0.65, 0.3, 0.09)
		hover.border_color = Color(0.95, 0.73, 0.43, 0.65)
		hover.set_border_width_all(1)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.pressed.connect(func() -> void: shop_requested.emit("commodities" if i == 0 else "equipment"))
		add_child(button)
		var label := Label.new()
		label.text = "COMMODITIES  ›" if i == 0 else "SHIP OUTFITTER  ›"
		label.position = Vector2(0, -24)
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color("f3d4a7"))
		var badge := StyleBoxFlat.new()
		badge.bg_color = Color(0.025, 0.06, 0.09, 0.85)
		badge.set_content_margin_all(5)
		label.add_theme_stylebox_override("normal", badge)
		button.add_child(label)
		buttons.append(button)


func sync_positions(view_size: Vector2, market_offset: Vector2) -> void:
	# The art uses KEEP_ASPECT_COVERED: account for both scaling and cropping.
	var scale_factor := maxf(view_size.x / 640.0, view_size.y / 360.0)
	var offset := (view_size - Vector2(640, 360) * scale_factor) * 0.5
	for i in buttons.size():
		buttons[i].position = offset + (AREAS[i].position + market_offset) * scale_factor
		buttons[i].size = AREAS[i].size * scale_factor
