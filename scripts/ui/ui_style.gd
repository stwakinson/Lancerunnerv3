class_name UiStyle
extends RefCounted

# Shared look for the menu screens: the HUD's Arial, and outlined buttons in
# the player's thruster blue that grow a little on hover.

const ACCENT := Color(0.55, 0.85, 1.0)


static func font(bold: bool, spacing := 0) -> Font:
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Arial", "Helvetica", "Liberation Sans", "sans-serif"])
	if bold:
		base.font_weight = 700
	var f := FontVariation.new()
	f.base_font = base
	f.spacing_glyph = spacing
	return f


static func label(text: String, font_size: int, bold: bool, spacing := 0, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font(bold, spacing))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	# Soft drop shadow so text reads over bright stars and the planet.
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func button(text: String, font_size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font(true, 4))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
	b.add_theme_stylebox_override("normal", _box(Color(ACCENT, 0.08), Color(ACCENT, 0.7)))
	b.add_theme_stylebox_override("hover", _box(Color(ACCENT, 0.22), ACCENT))
	b.add_theme_stylebox_override("pressed", _box(Color(ACCENT, 0.35), Color.WHITE))
	b.add_theme_stylebox_override("disabled", _box(Color(ACCENT, 0.05), Color(ACCENT, 0.35)))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color(ACCENT, 0.9)))

	# Grow from the center on hover.
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void: _scale_to(b, 1.05))
	b.mouse_exited.connect(func() -> void: _scale_to(b, 1.0))
	return b


static func _scale_to(b: Button, s: float) -> void:
	if b.disabled:
		return
	b.create_tween().tween_property(b, "scale", Vector2.ONE * s, 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.content_margin_left = 28.0
	s.content_margin_right = 28.0
	s.content_margin_top = 12.0
	s.content_margin_bottom = 12.0
	return s
