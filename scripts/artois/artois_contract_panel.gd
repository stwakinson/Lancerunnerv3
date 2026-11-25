extends Control
## Faction contact conversations and stable per-contact contract offers.
signal closed
var mission: ArtoisSortie
var market: LandingMarketState
var port := "planet_dock"
var contact_id := ""
var offer_id := ""
var _contacts: OptionButton
var _offers: Tree
var _body: Label
var _action: Button
var _abandon: Button
var _message: Label
var _refreshing := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.035, 0.055, 0.97)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_label("FACTION CONTRACTS", Vector2(78, 96), Vector2(1100, 42), 28)
	_contacts = OptionButton.new()
	_contacts.position = Vector2(78, 150)
	_contacts.size = Vector2(1100, 40)
	_contacts.item_selected.connect(func(index: int) -> void:
		contact_id = str(_contacts.get_item_metadata(index))
		offer_id = ""
		_message.text = ""
		refresh())
	add_child(_contacts)
	_offers = Tree.new()
	_offers.position = Vector2(78, 215)
	_offers.size = Vector2(460, 280)
	_offers.hide_root = true
	_offers.add_theme_font_size_override("font_size", 17)
	_offers.add_theme_constant_override("v_separation", 14)
	_offers.item_selected.connect(func() -> void:
		if _refreshing or _offers.get_selected() == null: return
		offer_id = str(_offers.get_selected().get_metadata(0))
		_message.text = ""
		_details())
	add_child(_offers)
	_body = _label("", Vector2(584, 215), Vector2(595, 290), 16)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_action = _button("ACCEPT CONTRACT", Vector2(584, 520), Vector2(370, 45), _act)
	_action.name = "ContractAction"
	_abandon = _button("ABANDON CONTRACT", Vector2(78, 520), Vector2(350, 45), _cancel)
	var close := _button("CLOSE / ESC", Vector2(980, 520), Vector2(200, 45), close_panel)
	close.name = "ContractClose"
	_message = _label("", Vector2(78, 585), Vector2(1100, 45), 15)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label("One active contract. Return to its issuing contact to collect payment. Contracts last this session; rewards are saved.", Vector2(78, 648), Vector2(1120, 24), 12)
	visible = false

func _label(text: String, at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("efc99b"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _button(text: String, at: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	add_child(button)
	return button

func open_panel(at_port := "planet_dock", selected_contact := "") -> void:
	port = at_port
	_contacts.clear()
	var local_contacts: Array = mission.board.contacts(port)
	for contact in local_contacts:
		var faction_name: String = market.Factions.data.factions[contact.faction].name
		_contacts.add_item("%s / %s / Standing %d" % [contact.name, faction_name, int(market.reputation[contact.faction])])
		_contacts.set_item_metadata(_contacts.item_count - 1, contact.id)
	if selected_contact.is_empty() and not mission.active_offer.is_empty() and mission.return_port() == port:
		selected_contact = str(mission.active_offer.contact)
	contact_id = str(local_contacts[0].id) if not local_contacts.is_empty() else ""
	for i in _contacts.item_count:
		if str(_contacts.get_item_metadata(i)) == selected_contact:
			_contacts.select(i)
			contact_id = selected_contact
	offer_id = ""
	_message.text = ""
	visible = true
	refresh()

func close_panel() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused): focused.release_focus()
	visible = false
	closed.emit()

func refresh() -> void:
	_refreshing = true
	for i in _contacts.item_count:
		var contact: Dictionary = mission.board.contact(str(_contacts.get_item_metadata(i)))
		_contacts.set_item_text(i, "%s / %s / Standing %d" % [contact.name, market.Factions.data.factions[contact.faction].name, int(market.reputation[contact.faction])])
	_offers.clear()
	var root := _offers.create_item()
	var busy := mission.phase in ["active", "return"]
	_abandon.visible = busy
	if busy:
		var row := _offers.create_item(root)
		row.set_text(0, str(mission.active_offer.get("title", "Test sortie")))
		row.set_metadata(0, "")
		row.select(0)
	else:
		var offers: Array = mission.board.offers(contact_id, mission.world)
		if not offers.any(func(offer: Dictionary) -> bool: return offer.id == offer_id): offer_id = str(offers[0].id) if not offers.is_empty() else ""
		for offer in offers:
			var row := _offers.create_item(root)
			row.set_text(0, "%s\n%d cr / +%d standing" % [offer.title, int(offer.reward), int(offer.reputation)])
			row.set_metadata(0, offer.id)
			if offer.id == offer_id: row.select(0)
	_refreshing = false
	_details()

func _details() -> void:
	var busy := mission.phase in ["active", "return"]
	var offer: Dictionary = mission.active_offer if busy else {}
	if not busy:
		for entry in mission.board.offers(contact_id, mission.world):
			if entry.id == offer_id: offer = entry
	if busy and offer.is_empty():
		_body.text = "Test sortie / Destroy five freebooters.\nProgress %d / 5\n\nReturn to the planet contact for 1,500 credits." % mission.kills
		_action.text = "CLAIM TEST REWARD" if mission.phase == "return" else "IN PROGRESS"
		_action.disabled = mission.phase != "return"
		return
	if offer.is_empty():
		_body.text = "No contracts available at this location."
		_action.disabled = true
		return
	var faction_name: String = market.Factions.data.factions[offer.faction].name
	_body.text = "%s\n%s\n\n%s\n\n%d ships / %.1f km from issuer\nPayment %d cr / +%d %s standing\nRequired standing %d\nReturn to %s at %s." % [offer.title, faction_name, offer.brief, int(offer.count), float(offer.distance) / 1000.0, int(offer.reward), int(offer.reputation), faction_name, int(offer.minimum_reputation), offer.issuer, market.markets.profile(offer.port).name]
	if busy:
		_body.text += "\nProgress: %d / %d targets destroyed." % [mission.kills, mission.required_kills]
		var error: String = mission.claim_error(market, contact_id)
		_action.text = "CLAIM %d CREDITS" % int(offer.reward) if mission.phase == "return" else "IN PROGRESS / %d OF %d" % [mission.kills, mission.required_kills]
		_action.disabled = not error.is_empty()
		_action.tooltip_text = error
		if mission.phase == "return" and not error.is_empty(): _message.text = error
	else:
		_action.text = "ACCEPT CONTRACT"
		_action.tooltip_text = mission.accept_error(contact_id, offer_id, market)
		_action.disabled = not _action.tooltip_text.is_empty()
		if _action.disabled: _message.text = _action.tooltip_text

func _act() -> void:
	if mission.phase == "return":
		_message.text = "Payment and faction standing received." if mission.claim(market, contact_id) else "Payment unavailable. Return to the issuing contact, or check save storage and retry."
	elif mission.phase != "active":
		_message.text = "Contract accepted. Launch and follow the marked mission waypoint." if mission.accept_offer(contact_id, offer_id, market) else mission.accept_error(contact_id, offer_id, market)
	refresh()

func _cancel() -> void:
	if mission.abandon(): _message.text = "Contract abandoned. No payment or reputation awarded."
	refresh()
