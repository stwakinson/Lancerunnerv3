extends Control
signal closed
var entries: Array = []
var _heading: Label
var _list: ItemList
var _title: Label
var _kind: Label
var _body: RichTextLabel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.03, 0.05, 0.98)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_heading = _label("", Vector2(78, 92), Vector2(1110, 45), 27)
	_list = ItemList.new()
	_list.position = Vector2(78, 170)
	_list.size = Vector2(370, 385)
	_list.add_theme_font_size_override("font_size", 16)
	_list.add_theme_constant_override("v_separation", 18)
	_list.auto_height = false
	_list.item_selected.connect(_select)
	add_child(_list)
	_kind = _label("", Vector2(490, 170), Vector2(690, 28), 14)
	_title = _label("", Vector2(490, 208), Vector2(690, 75), 24)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body = RichTextLabel.new()
	_body.position = Vector2(490, 300)
	_body.size = Vector2(690, 270)
	_body.add_theme_font_size_override("normal_font_size", 18)
	_body.add_theme_color_override("default_color", Color("d5e0e2"))
	add_child(_body)
	var close := Button.new()
	close.name = "StoriesClose"
	close.text = "CLOSE / ESC"
	close.position = Vector2(980, 590)
	close.size = Vector2(200, 45)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_panel)
	add_child(close)
	_label("Gold ! = contracts    Blue speech = local talk    Board / innkeeper = news", Vector2(78, 652), Vector2(1110, 25), 14)
	hide()

func _label(text: String, at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("edc38d"))
	add_child(label)
	return label

func open_panel(title: String, articles: Array) -> void:
	entries = articles.duplicate(true)
	_heading.text = title
	_list.clear()
	for entry in entries:
		_list.add_item(str(entry.title))
		_list.set_item_tooltip(_list.item_count - 1, str(entry.title))
	if not entries.is_empty():
		_list.select(0)
		_select(0)
	show()

func _select(index: int) -> void:
	if index < 0 or index >= entries.size(): return
	var entry: Dictionary = entries[index]
	_title.text = str(entry.title)
	_kind.text = str(entry.kind)
	_kind.add_theme_color_override("font_color", Color("8ed4d7") if entry.kind == "VERIFIED TRADE TIP" else Color("edc38d"))
	_body.text = str(entry.text)
	_body.scroll_to_line(0)

func close_panel() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused): focused.release_focus()
	hide()
	closed.emit()
