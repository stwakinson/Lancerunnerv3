extends Node2D
## Self-contained room: no planet-scene or global-class-cache dependency.
const Art = preload("res://scripts/benchmark/landing_art_layer.gd")
var layers: Array[Node2D] = []
var elapsed := 0.0
var weather_enabled := true
var parallax_enabled := true
var cinematic_motion := true
var camera_position := Vector2.ZERO
var manual_pan := 0.0
## Independent exterior, empty architecture, staff, furniture, guests and near props.
const Patron = preload("res://scripts/artois/artois_tavern_patron.gd")
const ROOM = preload("res://assets/artois/tavern/room_shell.png")
const FRAME := Rect2(-32, -18, 704, 396)
const BAR_DEPTHS := [0.06, 0.38, 0.38, 0.38, 0.38, 1.05]
const COLUMNS := {"britannian": 0, "valois": 1, "borderlander": 2, "hanseatic": 3}
const SLOTS := [
	{"position": Vector2(30, 265), "row": 0, "size": Vector2(76, 86)},
	{"position": Vector2(202, 300), "row": 0, "size": Vector2(89, 104)},
	{"position": Vector2(393, 227), "row": 1, "size": Vector2(76, 94)},
	{"position": Vector2(602, 307), "row": 2, "size": Vector2(86, 102)}]
var contacts: Array = []
var guests: Array[Node2D] = []
var visit := 0
var signature := ""
var _random := RandomNumberGenerator.new()
var _lights: ShaderMaterial

func _ready() -> void:
	_random.randomize()
	_add_art("RainySpaceport", preload("res://assets/artois/tavern/exterior.png"), Rect2(26, -12, 392, 220))
	var room := _add_art("EmptyTavern", ROOM, FRAME)
	_lights = ShaderMaterial.new()
	_lights.shader = preload("res://shaders/artois/tavern_lights.gdshader")
	room.material = _lights
	for label in ["BarStaff", "CounterFront", "Patrons"]:
		var layer := Node2D.new()
		layer.name = label
		add_child(layer)
		layers.append(layer)
	# This exact aligned crop places staff behind the counter; it contains no people.
	var counter := AtlasTexture.new()
	counter.atlas = ROOM
	counter.region = Rect2(695, 450, 920, 170)
	var facade := Art.new()
	facade.texture = counter
	facade.frame = Rect2(FRAME.position + Vector2(695, 450) / Vector2(ROOM.get_size()) * FRAME.size, Vector2(920, 170) / Vector2(ROOM.get_size()) * FRAME.size)
	layers[3].add_child(facade)
	_add_art("NearTablesAndLeaves", preload("res://assets/artois/tavern/foreground.png"), FRAME)

func begin_visit(profiles: Array, pinned_id := "", seed_value := -1) -> void:
	if seed_value >= 0: _random.seed = seed_value
	visit += 1
	clear_people()
	var available: Array = profiles.duplicate(true)
	_shuffle(available)
	var count := _random.randi_range(2, mini(4, available.size())) if available.size() >= 2 else available.size()
	contacts = available.slice(0, count)
	if not pinned_id.is_empty() and not contacts.any(func(entry: Dictionary) -> bool: return entry.id == pinned_id):
		for entry in available:
			if entry.id == pinned_id:
				if contacts.is_empty(): contacts.append(entry)
				else: contacts[0] = entry
	var slots := [0, 1, 2, 3]
	_shuffle(slots)
	var entries := []
	for i in contacts.size():
		var entry: Dictionary = contacts[i]
		var actor := _guest(SLOTS[slots[i]], int(COLUMNS[entry.faction]), str(entry.name), str(entry.id))
		actor.profile = entry
		entries.append(str(entry.id) + "@" + str(slots[i]))
	# Optional passers-by occupy spare seats, independently of faction contracts.
	var extra := _random.randi_range(0, 4 - contacts.size())
	for i in extra:
		var name: String = ["A travelling shipwright", "A local pilot", "A wool factor", "A pilgrim"][ _random.randi_range(0, 3)]
		_guest(SLOTS[slots[contacts.size() + i]], _random.randi_range(0, 3), name, "")
	var staff := Patron.new()
	staff.row = 3
	staff.column = _random.randi_range(0, 3)
	staff.dimensions = Vector2(66, 82)
	staff.position = Vector2(465, 185)
	staff.guest_name = "The innkeeper"
	layers[2].add_child(staff)
	guests.append(staff)
	signature = ",".join(entries) + ":" + str(extra) + ":" + str(staff.column)

func _guest(slot: Dictionary, column: int, title: String, id: String) -> Node2D:
	var actor := Patron.new()
	actor.column = column
	actor.row = int(slot.row)
	actor.position = slot.position
	actor.dimensions = slot.size
	actor.contact_id = id
	actor.guest_name = title
	layers[4].add_child(actor)
	guests.append(actor)
	return actor

func _shuffle(values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := _random.randi_range(0, i)
		var value: Variant = values[i]
		values[i] = values[j]
		values[j] = value

func clear_people() -> void:
	for guest in guests:
		if is_instance_valid(guest): guest.free()
	guests.clear()
	contacts.clear()

func contact_rect(id: String) -> Rect2:
	for guest in guests:
		if guest.contact_id == id:
			return Rect2(guest.position + layers[4].position + guest.hit_rect.position, guest.hit_rect.size)
	return Rect2()

func advance(delta: float, pointer: Vector2, pan_input := 0.0, camera_frozen := false) -> void:
	elapsed += delta
	if not camera_frozen:
		manual_pan = clampf(manual_pan + pan_input * delta * 18, -18, 18)
		var drift := Vector2(sin(elapsed * 0.13) * 4, cos(elapsed * 0.11) * 1.2) if cinematic_motion else Vector2.ZERO
		var target := pointer.clamp(-Vector2.ONE, Vector2.ONE) * Vector2(16, 4) + Vector2(manual_pan, 0) + drift
		camera_position = camera_position.lerp(target, 1 - exp(-delta * 4.5)) if parallax_enabled else Vector2.ZERO
	for i in layers.size(): layers[i].position = (-camera_position * BAR_DEPTHS[i]).round()
	_lights.set_shader_parameter("clock", elapsed)
	_lights.set_shader_parameter("rain_enabled", weather_enabled)


func _add_art(label: String, texture: Texture2D, frame: Rect2) -> Node2D:
	var layer := Art.new()
	layer.name = label
	layer.texture = texture
	layer.frame = frame
	add_child(layer)
	layers.append(layer)
	return layer

func reset_camera() -> void:
	manual_pan = 0
	camera_position = Vector2.ZERO
	for layer in layers: layer.position = Vector2.ZERO

func is_room_ready() -> bool:
	return is_node_ready() and layers.size() == 6 and _lights != null
