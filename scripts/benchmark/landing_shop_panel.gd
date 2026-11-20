class_name LandingShopPanel
extends Control

signal closed

const State = preload("res://scripts/benchmark/landing_market_state.gd")
const GOLD := Color("edc38d")
const PALE := Color("e0e8eb")
const MUTED := Color("94afbc")

var market: LandingMarketState
var shop_kind := "commodities"
var selected_id := "grain"
var _tree: Tree
var _title: Label
var _account: Label
var _item_name: Label
var _description: Label
var _totals: Label
var _message: Label
var _scope: Label
var _quantity: SpinBox
var _buy: Button
var _sell: Button
var _fit: Button
var _close: Button
var _slots: Array[Button] = []
var _refreshing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func configure(state: LandingMarketState) -> void:
	market = state


func open_shop(kind: String) -> void:
	shop_kind = kind
	selected_id = "grain" if kind == "commodities" else "pulse_laser"
	_quantity.value = 1
	_message.text = "Select an item to inspect prices and availability."
	visible = true
	_refresh()
	_close.grab_focus()


func close_shop() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused): focused.release_focus()
	visible = false
	closed.emit()


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	return style


func _label(text: String, at: Vector2, dimensions: Vector2, font_size: int, colour := PALE) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	add_child(label)
	return label


func _button(text: String, at: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.position = at
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", PALE)
	button.add_theme_stylebox_override("normal", _style(Color("173442"), Color("496371")))
	button.add_theme_stylebox_override("hover", _style(Color("294d5d"), GOLD))
	button.add_theme_stylebox_override("pressed", _style(Color("355867"), GOLD))
	button.add_theme_stylebox_override("disabled", _style(Color("12232d"), Color("293e49")))
	button.pressed.connect(action)
	add_child(button)
	return button


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.015, 0.025, 0.78)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := Panel.new()
	panel.position = Vector2(60, 78)
	panel.size = Vector2(1160, 552)
	panel.add_theme_stylebox_override("panel", _style(Color("0d202d"), Color("72828b")))
	add_child(panel)
	_label("AGINCOURT  /  LOWER MARKET", Vector2(88, 96), Vector2(600, 20), 12, GOLD)
	_title = _label("", Vector2(86, 119), Vector2(700, 43), 30)
	_account = _label("", Vector2(790, 103), Vector2(320, 60), 16, GOLD)
	_close = _button("×", Vector2(1158, 94), Vector2(40, 38), close_shop)
	_close.tooltip_text = "Return to the market (Esc)"
	_tree = Tree.new()
	_tree.position = Vector2(88, 185)
	_tree.size = Vector2(660, 320)
	_tree.columns = 5
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.set_column_expand(0, true)
	for i in range(1, 5):
		_tree.set_column_expand(i, false)
		_tree.set_column_custom_minimum_width(i, 76)
	_tree.add_theme_font_size_override("font_size", 15)
	_tree.add_theme_font_size_override("title_button_font_size", 12)
	_tree.add_theme_constant_override("v_separation", 16)
	_tree.add_theme_color_override("font_color", PALE)
	_tree.add_theme_stylebox_override("panel", _style(Color("0a1822"), Color("294451")))
	_tree.add_theme_stylebox_override("selected", _style(Color("294854"), Color("294854")))
	_tree.add_theme_stylebox_override("selected_focus", _style(Color("294854"), GOLD))
	_tree.add_theme_color_override("font_selected_color", GOLD)
	_tree.item_selected.connect(_selected)
	add_child(_tree)
	_item_name = _label("", Vector2(780, 186), Vector2(405, 35), 23, GOLD)
	_description = _label("", Vector2(782, 234), Vector2(400, 104), 15, MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label("QUANTITY", Vector2(782, 349), Vector2(130, 25), 12, MUTED)
	_quantity = SpinBox.new()
	_quantity.position = Vector2(920, 341)
	_quantity.size = Vector2(130, 38)
	_quantity.min_value = 1
	_quantity.max_value = 99
	_quantity.step = 1
	_quantity.value = 1
	_quantity.value_changed.connect(func(_value: float) -> void: _details())
	add_child(_quantity)
	_totals = _label("", Vector2(782, 389), Vector2(400, 25), 14, MUTED)
	_buy = _button("BUY", Vector2(782, 429), Vector2(190, 42), _trade.bind(true))
	_sell = _button("SELL", Vector2(986, 429), Vector2(190, 42), _trade.bind(false))
	_fit = _button("FIT TO SHIP", Vector2(782, 485), Vector2(394, 38), _fit_selected)
	_label("FITTED EQUIPMENT  /  CLICK A SLOT TO UNMOUNT", Vector2(90, 520), Vector2(660, 20), 11, MUTED)
	for i in 3:
		var slot := _button("", Vector2(88 + i * 224, 548), Vector2(212, 35), _unmount.bind(i))
		slot.add_theme_font_size_override("font_size", 12)
		_slots.append(slot)
	_message = _label("", Vector2(782, 537), Vector2(400, 51), 13, GOLD)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scope = _label("", Vector2(90, 601), Vector2(1100, 20), 11, MUTED)


func _refresh() -> void:
	_refreshing = true
	_title.text = "COMMODITIES EXCHANGE" if shop_kind == "commodities" else "SHIP WEAPONS & UTILITIES"
	_account.text = "%s cr\nCARGO  %d / %d" % [_money(market.credits), market.cargo_used(), market.capacity()]
	var titles := ["COMMODITY" if shop_kind == "commodities" else "EQUIPMENT", "BUY", "SELL", "CARGO" if shop_kind == "commodities" else "LOCKER", "STOCK"]
	for i in 5: _tree.set_column_title(i, titles[i])
	_tree.clear()
	var root := _tree.create_item()
	for id in State.ITEMS:
		var item: Dictionary = State.ITEMS[id]
		if (item.kind == "commodity") != (shop_kind == "commodities"): continue
		var row := _tree.create_item(root)
		row.set_metadata(0, id)
		row.set_text(0, item.name)
		row.set_text(1, _money(item.buy))
		row.set_text(2, _money(item.sell))
		row.set_text(3, str(market.owned(id)))
		row.set_text(4, str(market.stock[id]))
		for column in range(1, 5): row.set_text_alignment(column, HORIZONTAL_ALIGNMENT_RIGHT)
		if id == selected_id: row.select(0)
	for i in 3:
		var id: String = market.utility if i == 2 else market.weapons[i]
		_slots[i].text = ("UTILITY" if i == 2 else "W%d" % (i + 1)) + " · " + ("EMPTY" if id.is_empty() else str(State.ITEMS[id].name))
		_slots[i].disabled = id.is_empty()
		_slots[i].tooltip_text = "Unmount into your equipment locker"
	_scope.text = "Prices are per unit. Credits, cargo, dealer stock and loadout save locally."
	if shop_kind == "equipment": _scope.text = "PROTOTYPE LOADOUT · Fitting is saved; integration with flight weapons and shields is a later step."
	_refreshing = false
	_details()


func _selected() -> void:
	if _refreshing or _tree.get_selected() == null: return
	selected_id = str(_tree.get_selected().get_metadata(0))
	_details()


func _details() -> void:
	if market == null or not State.ITEMS.has(selected_id): return
	var item: Dictionary = State.ITEMS[selected_id]
	var quantity := int(_quantity.value)
	_item_name.text = item.name
	_description.text = str(item.kind).to_upper() + "\n" + str(item.description)
	_totals.text = "BUY  %s cr     /     SELL  %s cr" % [_money(int(item.buy) * quantity), _money(int(item.sell) * quantity)]
	_buy.tooltip_text = market.trade_error(selected_id, quantity, true)
	_sell.tooltip_text = market.trade_error(selected_id, quantity, false)
	_buy.disabled = not _buy.tooltip_text.is_empty()
	_sell.disabled = not _sell.tooltip_text.is_empty()
	_fit.visible = item.kind != "commodity"
	_fit.tooltip_text = market.fit_error(selected_id)
	_fit.disabled = not _fit.tooltip_text.is_empty()


func _finish(error: String, success: String) -> void:
	_message.text = error if not error.is_empty() else success
	if error.is_empty() and not market.save_state(): _message.text += " Changes are in memory; the local save failed."
	_refresh()


func _trade(buying: bool) -> void:
	var quantity := int(_quantity.value)
	_finish(market.trade(selected_id, quantity, buying), "%s %d × %s." % ["Bought" if buying else "Sold", quantity, State.ITEMS[selected_id].name])


func _fit_selected() -> void:
	_finish(market.fit(selected_id), "Fitted %s." % State.ITEMS[selected_id].name)


func _unmount(slot: int) -> void:
	_finish(market.unmount(slot), "Equipment returned to the locker.")


static func _money(amount: int) -> String:
	var text := str(amount)
	var result := ""
	while text.length() > 3:
		result = "," + text.right(3) + result
		text = text.left(text.length() - 3)
	return text + result
