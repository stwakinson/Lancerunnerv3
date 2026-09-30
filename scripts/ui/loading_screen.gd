extends Node3D

# Loading screen between the menu and the game. The bar tracks real work:
#   1. Loads the game scene (planet textures, sky, shaders) on background threads.
#   2. Loads everything the game only pulls in later: fighters, walking robots,
#      bullets and their models.
#   3. Builds the world, frozen, behind this screen.
#   4. Warms up: shows one of every enemy, effect and the on-foot gun to the
#      game camera (hidden under this screen) until the renderer stops
#      compiling new pipelines, so none of that happens mid-fight.
# Then it swaps straight to the already-built game.

const GAME_SCENE := "res://scenes/main.tscn"
# Loaded by the game only once play starts; loading them here keeps them in
# memory so the first enemy or shot doesn't hitch.
const EXTRA_RESOURCES := {
	"res://scenes/enemy.tscn": "Loading enemy fighters",
	"res://scenes/ground_robot.tscn": "Loading T-800 robots",
	"res://assets/models/ground_robot.glb": "Loading robot models",
	"res://scenes/bullet.tscn": "Loading weapons",
	"res://scenes/enemy_bullet.tscn": "Loading enemy weapons",
	"res://scenes/missile_turret.tscn": "Loading missile turrets",
	"res://scenes/ally_fighter.tscn": "Loading allied fighters",
	"res://scenes/ally_trooper.tscn": "Loading allied troopers",
}
const TIPS := [
	"Hold still low over the planet and gravity pulls you down. Keep your speed up to stay flying.",
	"Land, then press E to climb out and fight on foot. Press E by the ship to get back in.",
	"Press Z to zoom in and aim. On foot it aims down the gun's sights.",
	"On foot, Shift sprints on the boost meter and Space jumps.",
	"Walking robots only come for you near the ground. They take two shots to drop.",
	"Fly level near the ground and you'll follow the planet all the way around.",
	"Diving straight into the ground at full speed destroys your ship. Come in gently to land.",
	"Press [ and ] to change mouse sensitivity.",
]

## Warm-up ends once no new pipelines have compiled for this many frames...
@export var settle_frames := 20
## ...but always shows the warm-up set for at least this many frames...
@export var min_warmup_frames := 30
## ...and gives up waiting after this many.
@export var max_warmup_frames := 600
## The bar never finishes faster than this, so it can be read.
@export var min_display_time := 2.0
## A background load that makes no progress for this long is finished directly.
@export var stall_timeout := 5.0

# Share of the bar each stage fills.
const W_GAME := 0.55
const W_EXTRAS := 0.15
const W_BUILD := 0.05
const W_WARMUP := 0.25

var _progress := 0.0      # real progress, 0..1
var _shown := 0.0         # what the bar shows, eased toward _progress
var _stage := "Starting up"
var _elapsed := 0.0
var _tip_index := 0
var _tip_timer := 0.0
var _held := []           # keeps the extra resources loaded

var _bar_fill: ColorRect
var _bar_back: ColorRect
var _percent: Label
var _stage_label: Label
var _tip_label: Label
var _spinner: Label


func _ready() -> void:
	# Keep loading even if the window loses focus (which pauses the game).
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_tip_index = randi() % TIPS.size()
	_build_ui()
	_run()


func _process(delta: float) -> void:
	_elapsed += delta
	# Never runs ahead of the real work; eases up to it smoothly.
	_shown = move_toward(_shown, _progress, delta * maxf(0.4, (_progress - _shown) * 4.0))
	_bar_fill.size.x = _bar_back.size.x * _shown
	_percent.text = "%d%%" % roundi(_shown * 100.0)
	_stage_label.text = _stage
	_spinner.text = ["◐", "◓", "◑", "◒"][int(_elapsed * 6.0) % 4]
	_tip_timer += delta
	if _tip_timer > 5.0:
		_tip_timer = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_tip_label.text = "TIP  ·  " + TIPS[_tip_index]


func _run() -> void:
	# Let the screen fade in before the heavy lifting starts.
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. The game scene and everything it references, in the background.
	_stage = "Loading planet and sky"
	var game_scene := await _load(GAME_SCENE, 0.0, W_GAME) as PackedScene
	if game_scene == null:
		_stage = "Couldn't load the game"
		return

	# 2. Resources the game loads later on.
	var i := 0
	for path in EXTRA_RESOURCES:
		_stage = EXTRA_RESOURCES[path]
		var from := W_GAME + W_EXTRAS * i / EXTRA_RESOURCES.size()
		var to := W_GAME + W_EXTRAS * (i + 1) / EXTRA_RESOURCES.size()
		_held.append(await _load(path, from, to))
		i += 1
		_progress = to

	# 3. Build the world, frozen until the swap.
	_stage = "Building the world"
	await get_tree().process_frame
	var game := game_scene.instantiate()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(game)
	_progress = W_GAME + W_EXTRAS + W_BUILD

	# 4. Warm-up.
	_stage = "Compiling shaders"
	var cam := game.get_node("MainCamera") as CameraFollow
	cam.snap_to_target()
	var warm := _spawn_warmup_set(game, cam)
	var frames := 0
	var quiet := 0
	var last := _pipeline_compilations()
	var base := W_GAME + W_EXTRAS + W_BUILD
	while frames < max_warmup_frames:
		await get_tree().process_frame
		frames += 1
		if frames % 10 == 0:
			_warmup_effects(cam)
		var now := _pipeline_compilations()
		quiet = quiet + 1 if now == last else 0
		last = now
		if frames >= min_warmup_frames and quiet >= settle_frames:
			break
		# Frames still compiling count as progress too, just slower.
		_progress = base + W_WARMUP * minf(0.95, float(frames) / (min_warmup_frames + settle_frames * 2))
	for n in warm:
		if is_instance_valid(n):
			n.queue_free()
	var pilot := game.get_node("Pilot") as PlayerOnFoot
	pilot.hide_gun()
	(game.get_node("Player") as PlayerShipController).gear.snap(false)

	_stage = "Ready"
	_progress = 1.0
	while _shown < 1.0 or _elapsed < min_display_time:
		await get_tree().process_frame

	# Swap to the game that's already built and warmed up.
	remove_child(game)
	game.process_mode = Node.PROCESS_MODE_INHERIT
	SceneFader.change_scene_to_node(game, 0.3)


# Loads `path` on a background thread, moving the bar from `from` to `to` as
# it goes. One thread only: splitting a load over sub-threads can deadlock
# (seen here as the bar freezing part way). If it ever stops making progress
# for stall_timeout seconds, finish it on this thread instead so the screen
# can never hang.
func _load(path: String, from: float, to: float) -> Resource:
	if ResourceLoader.load_threaded_request(path, "", false) != OK:
		return ResourceLoader.load(path)
	var progress := []
	var last := -1.0
	var still := 0.0
	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return ResourceLoader.load(path)
		var p: float = progress[0] if not progress.is_empty() else 0.0
		_progress = lerpf(from, to, p)
		if p > last:
			last = p
			still = 0.0
		else:
			still += get_process_delta_time()
			if still > stall_timeout:
				push_warning("Loading %s stalled at %d%%; finishing it directly." % [path, roundi(p * 100.0)])
				break
		await get_tree().process_frame
	# Returns at once if it's loaded; otherwise waits here for it to finish.
	return ResourceLoader.load_threaded_get(path)


func _pipeline_compilations() -> int:
	var total := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += RenderingServer.get_rendering_info(info)
	return total


# One of everything the game draws later, in front of the (hidden) game
# camera: a fighter with its thrusters, a robot, both bullets and the gun.
func _spawn_warmup_set(game: Node, cam: Camera3D) -> Array:
	var out := []
	var view := cam.global_transform
	var items := [
		[_held[0], Vector3(-3.0, -0.5, -14.0)],   # enemy fighter
		[_held[1], Vector3(3.0, -2.0, -12.0)],    # ground robot
		[_held[3], Vector3(-1.0, 0.5, -8.0)],     # player bullet
		[_held[4], Vector3(1.0, 0.5, -8.0)],      # enemy bullet
		[_held[6], Vector3(5.0, 1.0, -16.0)],     # allied fighter
		[_held[7], Vector3(-2.0, -2.0, -6.0)],    # allied trooper
	]
	for item in items:
		var node := (item[0] as PackedScene).instantiate() as Node3D
		add_child(node)
		node.global_transform = Transform3D(view.basis, view * item[1])
		# Just be seen: no moving, shooting, expiring or touching anything.
		node.set_process(false)
		var area := node as Area3D
		if area != null:
			area.collision_layer = 0
			area.collision_mask = 0
		node.remove_from_group("enemies")
		node.remove_from_group("bullets")
		node.remove_from_group("allies")
		node.remove_from_group("allies_air")
		node.remove_from_group("allies_ground")
		out.append(node)
	# A missile turret, firing one (unguided) missile so its flame and smoke are ready.
	var turret := (_held[5] as PackedScene).instantiate() as MissileTurret
	add_child(turret)
	turret.global_transform = Transform3D(view.basis, view * Vector3(4.0, -6.0, -24.0))
	turret.set_process(false)
	turret.remove_from_group("enemies")
	turret.collision_layer = 0
	turret.test_fire()
	out.append(turret)
	(game.get_node("Pilot") as PlayerOnFoot).prepare_gun(cam as CameraFollow)
	# Both parachutes (same materials, different colors).
	for chute in [[Color(1.0, 0.45, 0.1), Vector3(-4.0, -1.0, -12.0)], [Color(0.2, 0.55, 1.0), Vector3(4.0, -1.0, -12.0)]]:
		var p := Parachute.make(1.2, 1.5, chute[0], 0.02)
		add_child(p)
		p.global_transform = Transform3D(view.basis, view * chute[1])
		p.set_process(false)
		out.append(p)
	# Show the landing gear too, so its materials are ready for the first landing.
	(game.get_node("Player") as PlayerShipController).gear.snap(true)
	return out


func _warmup_effects(cam: Camera3D) -> void:
	var view := cam.global_transform
	Explosion.spawn(view * Vector3(0.0, 0.0, -10.0), Color(1.0, 0.45, 0.15), 1.2)
	Explosion.spawn(view * Vector3(2.0, 1.0, -12.0), Color(0.6, 0.8, 1.0), 0.6)
	Blast.spawn(view * Vector3(-2.0, 0.0, -14.0), 1.0)
	var planet := Planet.instance
	if planet != null:
		var p := view * Vector3(0.0, -1.0, -9.0)
		DustPuff.spawn(p, planet.up_at(p))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Opaque, so the warm-up behind it never shows.
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06)
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title := UiStyle.label("SHIP WARS", 64, true, 14)
	root.add_child(title)
	_place(title, 0.0, 1.0, 0.24, 0.24, 0.0, 0.0, 0.0, 90.0)

	var sub := UiStyle.label("PREPARING MISSION", 18, true, 8, Color(UiStyle.ACCENT, 0.85))
	root.add_child(sub)
	_place(sub, 0.0, 1.0, 0.24, 0.24, 0.0, 0.0, 92.0, 122.0)

	# Bar: thin track with the fill growing left to right.
	_bar_back = ColorRect.new()
	_bar_back.color = Color(1, 1, 1, 0.1)
	root.add_child(_bar_back)
	_place(_bar_back, 0.5, 0.5, 0.58, 0.58, -300.0, 300.0, -4.0, 4.0)
	_bar_fill = ColorRect.new()
	_bar_fill.color = UiStyle.ACCENT
	_bar_back.add_child(_bar_fill)
	_bar_fill.position = Vector2.ZERO
	_bar_fill.size = Vector2(0.0, 8.0)

	_stage_label = UiStyle.label("", 18, false, 1, Color(1, 1, 1, 0.85))
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_stage_label)
	_place(_stage_label, 0.5, 0.5, 0.58, 0.58, -300.0, 200.0, -40.0, -12.0)

	_spinner = UiStyle.label("", 18, false, 0, UiStyle.ACCENT)
	_spinner.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_spinner)
	_place(_spinner, 0.5, 0.5, 0.58, 0.58, -328.0, -302.0, -40.0, -12.0)

	_percent = UiStyle.label("0%", 18, true, 2, Color.WHITE)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_percent)
	_place(_percent, 0.5, 0.5, 0.58, 0.58, 200.0, 300.0, -40.0, -12.0)

	_tip_label = UiStyle.label("TIP  ·  " + TIPS[_tip_index], 16, false, 0, Color(1, 1, 1, 0.6))
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_tip_label)
	_place(_tip_label, 0.5, 0.5, 0.82, 0.82, -360.0, 360.0, -30.0, 30.0)


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
