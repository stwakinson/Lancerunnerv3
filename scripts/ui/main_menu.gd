extends Node3D

# Home screen: the player's ship turns slowly over the planet with its engines
# idling, above a START MISSION button. That opens the mission picker: two
# boxes (Infinite and Classic), each with its name, a picture and an
# explanation. Picking one swings the ship's nose away from the camera, lights
# the engines and punches off into the distance while the screen fades into
# the game (which opens on the same view of the planet).

# The loading screen, which prepares and then opens the game.
const GAME_SCENE := "res://scenes/loading.tscn"

## Degrees per second the ship turns while idling.
@export var spin_speed := 18.0
## Where the middle of the ship sits on screen, as a fraction of screen height
## from the top (between the title and the START MISSION button).
@export var ship_screen_height := 0.42
## How far in front of the camera the ship sits (smaller = bigger on screen).
@export var ship_distance := 5.0

@onready var _camera: Camera3D = $Camera3D
@onready var _ship: Node3D = $ShipPivot
@onready var _ship_visual: Node3D = $ShipPivot/ShipVisual

const MODES := [
	{
		"mode": GameMode.Mode.INFINITE,
		"title": "INFINITE",
		"picture": "res://assets/ui/mode_infinite.png",
		"text": "Endless war. Destroyed enemies keep coming back, and the fighting "
			+ "gets tougher the longer you last. It goes on until you're shot down: "
			+ "how long can you survive, and how high can you score?",
	},
	{
		"mode": GameMode.Mode.CLASSIC,
		"title": "CLASSIC",
		"picture": "res://assets/ui/mode_classic.png",
		"text": "One fixed enemy force: 50 fighters and 50 robots, guarded by 30 missile "
			+ "turrets. Nothing respawns, on either side. Destroy every fighter and robot "
			+ "to win (turrets are optional); when only a few are left, they come for you.",
	},
]

var _ui: Control
var _start_button: Button
var _title: Control
var _hint: Control
var _picker: Control
var _ship_home := Vector3.ZERO
var _time := 0.0
var _launching := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ShipModel.attach(_ship_visual, ShipModel.PLAYER_THRUST_CORE, ShipModel.PLAYER_THRUST_TAIL)
	_place_ship()
	_ship_home = _ship.position
	_ship.rotation.y = deg_to_rad(145.0)  # three-quarter view, nose toward the camera
	_build_ui()


func _process(delta: float) -> void:
	if _launching:
		return
	_time += delta
	_ship.rotation.y = fposmod(_ship.rotation.y + deg_to_rad(spin_speed) * delta, TAU)
	_ship.position.y = _ship_home.y + sin(_time * 1.3) * 0.08
	_ship_visual.rotation.z = sin(_time * 0.9) * 0.06


func _unhandled_input(event: InputEvent) -> void:
	if _launching:
		return
	if event.is_action_pressed("ui_cancel") and _picker.visible:
		_show_picker(false)
	elif event.is_action_pressed("ui_accept") and not _picker.visible:
		_show_picker(true)


# START MISSION opens the mission picker (Back / Esc closes it again).
func _show_picker(on: bool) -> void:
	if _launching or SceneFader.busy:
		return
	_picker.visible = on
	_start_button.visible = not on
	_hint.visible = not on
	_title.visible = not on
	if on:
		(_picker.find_child("Play0", true, false) as Button).grab_focus()
	else:
		_start_button.grab_focus()


func _start_mission(mode: GameMode.Mode) -> void:
	if _launching or SceneFader.busy:
		return
	GameMode.current = mode
	_launching = true
	for b in _picker.find_children("*", "Button", true, false):
		(b as Button).disabled = true
	create_tween().tween_property(_ui, "modulate:a", 0.0, 0.3)

	# Swing the nose away from the camera (the nearest way round), level the
	# wings, then light the engines and accelerate off into the distance.
	var yaw := _ship.rotation.y
	var fly := create_tween()
	fly.tween_property(_ship, "rotation:y", roundf(yaw / TAU) * TAU, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	fly.parallel().tween_property(_ship_visual, "rotation:z", 0.0, 0.5)
	fly.tween_callback(_flare_engines)
	fly.tween_property(_ship, "position", _ship.position + Vector3(0.0, 1.5, -80.0), 1.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(0.8).timeout
	SceneFader.change_scene(GAME_SCENE, 0.7)


# Puts the middle of the hull (not just the pivot, which the model sits off of
# vertically) at ship_screen_height on screen. The camera keeps its height fixed
# at any window shape, so this holds when the window is resized.
func _place_ship() -> void:
	var bounds := AABB()
	var first := true
	for n in _ship_visual.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	var hull_offset := bounds.get_center().y - _ship.global_position.y if not first else 0.0

	var screen := get_viewport().get_visible_rect().size
	var target := _camera.project_position(Vector2(screen.x * 0.5, screen.y * ship_screen_height), ship_distance)
	_ship.global_position = target - Vector3(0.0, hull_offset, 0.0)


func _flare_engines() -> void:
	for n in _ship_visual.find_children("*", "FxParticles", true, false):
		var ps := n as FxParticles
		ps.rate *= 2.5
		ps.speed *= 2.5
		ps.size *= 1.4


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title := UiStyle.label("SHIP WARS", 72, true, 14)
	_ui.add_child(title)
	_place(title, 0.0, 1.0, 0.07, 0.07, 0.0, 0.0, 0.0, 110.0)
	_title = title

	_start_button = UiStyle.button("START MISSION", 26)
	_start_button.pressed.connect(_show_picker.bind(true))
	_ui.add_child(_start_button)
	_place(_start_button, 0.5, 0.5, 0.76, 0.76, -170.0, 170.0, -34.0, 34.0)

	var hint := UiStyle.label("Mouse to steer  ·  W/A/S/D to fly  ·  Shift boost  ·  Click to fire",
		16, false, 0, Color(1, 1, 1, 0.6))
	_ui.add_child(hint)
	_place(hint, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, -56.0, -26.0)
	_hint = hint

	var benchmark := UiStyle.button("ARTOIS  /  VISUAL BENCHMARK", 16)
	benchmark.pressed.connect(func() -> void:
		if not _launching and not SceneFader.busy:
			SceneFader.change_scene("res://scenes/benchmark/artois_visual.tscn"))
	_ui.add_child(benchmark)
	_place(benchmark, 0.5, 0.5, 0.87, 0.87, -210.0, 210.0, -22.0, 22.0)

	_build_picker()


# The mission picker: a dimmed backdrop, a heading, the two mode boxes side by
# side and a Back button.
func _build_picker() -> void:
	_picker = Control.new()
	_picker.visible = false
	_ui.add_child(_picker)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.05, 0.72)
	_picker.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Heading, boxes and Back stacked in one centred column, so nothing can
	# overlap whatever size the boxes end up.
	var center := CenterContainer.new()
	_picker.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)

	column.add_child(UiStyle.label("CHOOSE YOUR MISSION", 30, true, 6))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
	column.add_child(row)
	for i in MODES.size():
		row.add_child(_mode_box(MODES[i], i))

	var back := UiStyle.button("BACK", 18)
	back.pressed.connect(_show_picker.bind(false))
	back.custom_minimum_size = Vector2(180, 0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)


# One mode's box: MODE label and name, picture, explanation, play button.
func _mode_box(info: Dictionary, index: int) -> Control:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.07, 0.12, 0.92)
	style.border_color = Color(UiStyle.ACCENT, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(380, 0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)

	col.add_child(UiStyle.label("MODE", 13, true, 4, Color(UiStyle.ACCENT, 0.8)))
	col.add_child(UiStyle.label(info.title, 30, true, 5))

	var pic := TextureRect.new()
	pic.texture = load(info.picture) as Texture2D
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(348, 180)
	col.add_child(pic)

	# Same height in both boxes (room for five lines), so the boxes and their
	# play buttons line up.
	var text := UiStyle.label(info.text, 14, false, 0, Color(1, 1, 1, 0.8))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.custom_minimum_size = Vector2(348, 96)
	col.add_child(text)

	var play := UiStyle.button("PLAY " + info.title, 18)
	play.name = "Play%d" % index
	play.pressed.connect(_start_mission.bind(info.mode))
	col.add_child(play)
	return box


static func _place(c: Control, al: float, ar: float, at: float, ab: float,
		ol: float, orr: float, ot: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_right = ar
	c.anchor_top = at
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_right = orr
	c.offset_top = ot
	c.offset_bottom = ob
