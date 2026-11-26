extends Control
signal closed
var world: Node3D
var mission: RefCounted
var rows := {}
var _ship: Label
var _close: Button
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.03, 0.05, 0.98)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label("PILOT / CHARACTER & FACTIONS", Vector2(78, 90), Vector2(900, 42), 28)
	_ship = _label("", Vector2(80, 145), Vector2(1110, 150), 16)
	_ship.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for column in [["FACTION", 80], ["SCORE", 350], ["REPUTATION", 430], ["STATUS", 720], ["CONTRACT ACCESS", 900]]:
		_label(column[0], Vector2(column[1], 315), Vector2(260, 20), 12)
	var index := 0
	for id in world.law.Factions.data.factions:
		var y := 350.0 + index * 37
		var title := _label(world.law.Factions.data.factions[id].name, Vector2(80, y), Vector2(265, 26), 16)
		var score := _label("", Vector2(350, y), Vector2(65, 26), 16)
		var bar := ProgressBar.new()
		bar.position = Vector2(430, y + 2)
		bar.size = Vector2(250, 18)
		bar.min_value = -100
		bar.max_value = 100
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		var status := _label("", Vector2(720, y), Vector2(175, 26), 14)
		var access := _label("", Vector2(900, y), Vector2(290, 26), 12)
		rows[id] = {"title": title, "score": score, "bar": bar, "status": status, "access": access}
		index += 1
	_label("CONTRACTS: Basic 0 / Veteran 10 / Elite 25     NAVAL SHIPS: 25 with their faction", Vector2(80, 590), Vector2(1120, 24), 14)
	_label("Docking needs normal standing (-19 or better). At -50, a faction is hostile and its armed ships attack on sight.", Vector2(80, 621), Vector2(1120, 24), 13)
	_close = Button.new()
	_close.name = "CharacterClose"
	_close.text = "CLOSE / I / F2 / ESC"
	_close.position = Vector2(920, 90)
	_close.size = Vector2(280, 42)
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(close_sheet)
	add_child(_close)
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
func open_sheet() -> void:
	var market: RefCounted = world.combat.ordnance.market
	var profile: Dictionary = market.Ships.profile(market.ship_class)
	var weapons := PackedStringArray()
	for id in market.weapons:
		weapons.append(str(market.ITEMS[id].name) if not str(id).is_empty() else "Empty mount")
	_ship.text = "%s / %s     Credits: %d     Cargo: %d / %d\nHull %d/%d     Armour %d/%d     Ward %d/%d     Energy %d/%d\nWeapons: %s\nUtility: %s\n%s" % [profile.name, profile.role, market.credits, market.cargo_used(), market.capacity(), roundi(world.combat.hull), roundi(world.combat.hull_max), roundi(world.combat.defence.armour), roundi(world.combat.defence.armour_max), roundi(world.combat.shield), roundi(world.combat.shield_max), roundi(world.combat.defence.energy), roundi(world.combat.defence.ENERGY_MAX), " / ".join(weapons), str(market.ITEMS[market.utility].name) if not market.utility.is_empty() else "None fitted", mission.summary()]
	for id in rows:
		var row: Dictionary = rows[id]
		var standing: int = world.law.score(id)
		var colour := Color("ee7967") if standing <= -50 else (Color("edc38d") if standing >= 25 else Color("8ed4d7"))
		row.score.text = str(standing)
		row.score.add_theme_color_override("font_color", colour)
		row.bar.value = standing
		var fill := StyleBoxFlat.new()
		fill.bg_color = colour
		row.bar.add_theme_stylebox_override("fill", fill)
		row.status.text = "HOSTILE" if standing <= -50 else ("WARY" if standing <= -20 else ("TRUSTED" if standing >= 25 else "NEUTRAL"))
		row.status.tooltip_text = world.law.description(id)
		var tiers := PackedStringArray()
		for template in mission.board.config.templates:
			if standing >= int(template.minimum_reputation): tiers.append(str(template.get("tier", "Contract")))
		row.access.text = " / ".join(tiers) if bool(world.law.Factions.data.factions[id].lawful) else "No local quest giver"
		if row.access.text.is_empty(): row.access.text = "Need 0 for basic jobs"
	show()
func close_sheet() -> void:
	hide()
	closed.emit()
