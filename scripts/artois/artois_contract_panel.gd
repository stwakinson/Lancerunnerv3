extends Control
## A separate planet conversation modal, using the existing logical UI canvas.
signal closed
var mission: ArtoisSortie
var market: LandingMarketState
var _body: Label
var _action: Button
var _message: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.035, 0.055, 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_label("PLANET CONTACT  /  CAPTAIN FLUELLEN", Vector2(210, 160), 25)
	_body = _label("", Vector2(210, 220), 19)
	_body.size = Vector2(850, 220)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message = _label("", Vector2(210, 460), 15)
	_action = _button("ACCEPT TEST SORTIE", Vector2(210, 510), _act)
	_action.name = "ContractAction"
	var close := _button("CLOSE  /  ESC", Vector2(690, 510), close_panel)
	close.name = "ContractClose"
	visible = false


func _label(text: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("efc99b"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _button(text: String, at: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = Vector2(370, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	add_child(button)
	return button


func open_panel() -> void:
	_message.text = ""
	visible = true
	refresh()


func close_panel() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	_body.text = "A freebooter patrol is waiting off the southern wreck field. Fly to the marked test area and destroy all five ships. They will attack when you approach within 420 m.\n\nPayment: 1,500 credits and +10 Britannian / Valois reputation on your return. Docking repairs your hull and shields. Left mouse fires; double-tap a movement key to dodge."
	_action.disabled = mission.phase == "active"
	match mission.phase:
		"active": _action.text = "IN PROGRESS  /  %d OF 5 DESTROYED" % mission.kills
		"return": _action.text = "CLAIM 1,500 CREDITS"
		"failed": _action.text = "RETRY TEST SORTIE"
		"paid": _action.text = "REPEAT TEST SORTIE"
		_: _action.text = "ACCEPT TEST SORTIE"
	if mission.phase == "return": _body.text = "Five freebooters destroyed. The route is clear. Good work, pilot.\n\nCollect your 1,500 credits below. You may repeat the test contract afterwards."


func _act() -> void:
	if mission.phase == "return":
		_message.text = "Payment received: 1,500 credits." if mission.claim(market) else "Payment could not be saved. Check credits/save storage and try again."
	else:
		if mission.accept(): _message.text = "Contract accepted. Launch, then press G to navigate to the marked patrol."
	refresh()
