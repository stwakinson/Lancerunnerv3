class_name Hud
extends Control

# Everything drawn over the game, matching the Unity IMGUI HUD: hit flash,
# score + combo (top-left), health bar + kills (top-right), banners, the
# controls hint, game over screen, enemy markers, the crosshair and the
# mouse-sensitivity message. All sizes are fractions of screen height.


@export_group("Crosshair")
@export var crosshair_color := Color(1.0, 1.0, 1.0, 0.9)
@export var arm_length := 0.016
@export var gap := 0.007
@export var thickness := 0.0022

@export_group("Enemy Indicators")
@export var indicator_color := Color(1.0, 0.3, 0.25, 0.9)
## Size of the brackets around on-screen enemies, as a fraction of screen height.
@export var marker_size := 0.03

const MENU_SCENE := "res://scenes/menu.tscn"

var _font: SystemFont
# Game over buttons (real Controls, shown only on the game over screen).
var _game_over_buttons: HBoxContainer
var _was_game_over := false

@export_group("Radar")
## Radius of the scope, as a fraction of screen height.
@export var radar_size := 0.12
## How far the radar sees in the ship, and on foot (robots are small and close).
@export var radar_range_ship := 400.0
@export var radar_range_on_foot := 30.0
## Seconds per turn of the sweep line.
@export var sweep_period := 2.5
## How long a blip glows after the sweep passes over it.
@export var blip_fade := 2.2
const RADAR_GREEN := Color(0.3, 1.0, 0.45)
const ALLY_BLUE := Color(0.45, 0.72, 1.0)

var _sweep := 0.0            # sweep angle, radians clockwise from straight ahead

# Missile camera: a picture-in-picture view from a camera mounted on the side
# of the nearest missile chasing you, looking ahead at your ship.
var _missile_cam_box: SubViewportContainer
var _missile_cam_view: SubViewport
var _missile_cam: Camera3D
var _cam_missile: Missile
# Instance id -> [angle on the scope, seconds since the sweep last lit it].
var _pings := {}
var _bold: SystemFont


func _ready() -> void:
	process_priority = 200  # after the camera has moved
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial", "Helvetica", "Liberation Sans", "sans-serif"])
	_bold = _font.duplicate()
	_bold.font_weight = 700
	_build_game_over_buttons()
	_build_missile_cam()


func _process(delta: float) -> void:
	queue_redraw()
	_update_missile_cam()
	var previous := _sweep
	_sweep = fposmod(_sweep + TAU * delta / sweep_period, TAU)
	# Light up every blip the sweep line passed over since last frame.
	var swept := fposmod(_sweep - previous, TAU)
	for id in _pings:
		var ping: Array = _pings[id]
		ping[1] += delta
		if fposmod(ping[0] - previous, TAU) <= swept:
			ping[1] = 0.0
	var gm := GameManager.instance
	var over := gm != null and gm.game_over_screen
	if over != _was_game_over:
		_was_game_over = over
		_game_over_buttons.visible = over
		var cam := get_viewport().get_camera_3d() as CameraFollow
		if over:
			# Free the cursor so the buttons can be clicked.
			if cam != null:
				cam.release_mouse()
			for b in _game_over_buttons.get_children():
				(b as Button).disabled = false
			(_game_over_buttons.get_child(0) as Button).grab_focus()
		elif cam != null:
			cam.capture_mouse()


func _build_game_over_buttons() -> void:
	_game_over_buttons = HBoxContainer.new()
	_game_over_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_game_over_buttons.add_theme_constant_override("separation", 24)
	add_child(_game_over_buttons)
	_game_over_buttons.anchor_left = 0.0
	_game_over_buttons.anchor_right = 1.0
	_game_over_buttons.anchor_top = 0.56
	_game_over_buttons.anchor_bottom = 0.56
	_game_over_buttons.offset_bottom = 60.0
	_game_over_buttons.visible = false

	var again := UiStyle.button("PLAY AGAIN  (R)", 22)
	again.custom_minimum_size = Vector2(230, 0)
	again.pressed.connect(func() -> void:
		if GameManager.instance != null:
			GameManager.instance.restart_game())
	_game_over_buttons.add_child(again)

	var menu := UiStyle.button("MAIN MENU", 22)
	menu.custom_minimum_size = Vector2(230, 0)
	menu.pressed.connect(func() -> void:
		if SceneFader.busy:
			return
		for b in _game_over_buttons.get_children():
			(b as Button).disabled = true
		SceneFader.change_scene(MENU_SCENE))
	_game_over_buttons.add_child(menu)


func _draw() -> void:
	var gm := GameManager.instance
	var cam := get_viewport().get_camera_3d() as CameraFollow
	var w := size.x
	var h := size.y
	var pad := h * 0.025

	if gm != null:
		# Red flash when a life is lost.
		if gm.hit_flash > 0.0:
			draw_rect(Rect2(0, 0, w, h), Color(1, 0, 0, 0.35 * gm.hit_flash))
		_draw_score(gm, pad, h)
		_draw_health_and_kills(gm, pad, w, h)

		if gm.game_over_screen:
			_draw_game_over(gm, w, h)
		elif gm.is_game_over:
			pass  # the player's explosion plays out first
		else:
			if gm.banner_timer > 0.0 and not gm.banner_text.is_empty():
				# Fade in quickly, hold, fade out over the last half second.
				var alpha := clampf((gm.banner_duration - gm.banner_timer) * 4.0, 0, 1) * clampf(gm.banner_timer * 2.0, 0, 1)
				var bs := roundi(h * 0.08)
				_label(Rect2(0, h * 0.28, w, bs * 1.5), gm.banner_text, bs, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
			if gm.play_time < 8.0:
				var hs := roundi(h * 0.02)
				_label(Rect2(0, h - pad - hs * 2.0, w, hs * 2.0),
					"Mouse to steer  ·  W/S forward/back  ·  A/D strafe  ·  Shift boost  ·  Click / Space to fire  ·  Z zoom  ·  Esc menu",
					hs, Color(1, 1, 1, 0.8 * clampf(8.0 - gm.play_time, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, 1, false)

	if gm != null and not gm.is_game_over and gm.player != null:
		var ls := roundi(h * 0.025)
		var prompt_rect := Rect2(0, h * 0.8, w, ls * 2.0)
		if gm.player.on_foot:
			_draw_foot_panel(gm.player, pad, h)
			if gm.player.wrecked:
				_label(prompt_rect, _new_ship_text(gm.player), ls, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
			if gm.player.pilot.near_ship:
				_label(prompt_rect, "Press E to get in the ship", ls, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
		else:
			_draw_flight_panel(gm.player, pad, h)
			match gm.player.state:
				PlayerShipController.State.LANDED:
					var msg := "LANDED  ·  Press W to take off  ·  Press E to get out" if gm.player.can_exit else "TOUCHDOWN"
					_label(prompt_rect, msg, ls, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
				PlayerShipController.State.TAKING_OFF:
					_label(prompt_rect, "TAKING OFF", ls, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 1, true)

	if cam != null and gm != null and not gm.is_game_over and gm.player != null:
		_draw_radar(gm.player, cam, w, h, pad)
		_draw_missile_warning(gm.player, w, h)
		_draw_missile_cam_frame(gm.player, h)
	if cam != null and (gm == null or not gm.is_game_over):
		_draw_enemy_indicators(cam, w, h)
	# No crosshair on the game over screen; aiming down the sights on foot: just a small dot.
	if gm != null and gm.is_game_over:
		pass
	elif cam != null and cam.first_person and cam.zoom_blend > 0.6:
		var r := maxf(1.5, h * 0.0022)
		draw_circle(Vector2(w, h) * 0.5, r + 1.0, Color(0, 0, 0, 0.5))
		draw_circle(Vector2(w, h) * 0.5, r, crosshair_color)
	else:
		_draw_crosshair(w, h)

	if cam != null and cam.sensitivity_message_timer > 0.0:
		var ss := roundi(h * 0.025)
		_label(Rect2(0, h * 0.6, w, ss * 2.0), "Mouse sensitivity  %.2f   ( [  /  ] )" % cam.mouse_sensitivity,
			ss, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 1, false)


func _draw_score(gm: GameManager, pad: float, h: float) -> void:
	var base := roundi(h * 0.035)
	var punched := roundi(base * (1.0 + 0.25 * gm.score_punch))
	_label(Rect2(pad, pad, size.x, base * 2.0), "SCORE  " + _thousands(gm.score), punched, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	# Which mission this is.
	var ms := roundi(h * 0.018)
	_label(Rect2(pad, pad + base * 1.25, size.x, ms * 1.4), "MISSION: " + GameMode.title, ms, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, 0, true)
	if gm.combo > 1:
		_label(Rect2(pad, pad + base * 2.1, size.x, base * 2.0), "COMBO x%d" % gm.combo,
			roundi(h * 0.025), Color(1.0, 0.75, 0.2), HORIZONTAL_ALIGNMENT_LEFT, 0, true)


# Top-right: a health bar that shades green -> orange -> red as health drops
# (the chunk just lost drains away white; it throbs when low), then kills.
func _draw_health_and_kills(gm: GameManager, pad: float, w: float, h: float) -> void:
	var s := h * 0.045
	var right_size := roundi(h * 0.03)

	if not gm.is_game_over:
		var bar_w := h * 0.32
		var bar_h := s * 0.6
		var x := w - pad - bar_w
		var y := pad + (s - bar_h) * 0.5
		var frac := float(gm.health) / float(gm.max_health)
		var trail := gm.health_trail / float(gm.max_health)
		# Blend around the color wheel so in-between shades stay vivid: red -> orange at half -> green.
		var hue := lerpf(0.0, 0.08, frac * 2.0) if frac < 0.5 else lerpf(0.08, 0.36, (frac - 0.5) * 2.0)
		var fill := Color.from_hsv(hue, 0.8, 0.95)
		if frac <= 0.3:
			# Low health: the bar throbs a little brighter.
			fill = fill.lerp(Color(1.0, 0.55, 0.5), 0.25 + 0.25 * sin(Time.get_ticks_msec() * 0.012))
		draw_rect(Rect2(x - 2, y - 2, bar_w + 4, bar_h + 4), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(x, y, bar_w, bar_h), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(x, y, bar_w * trail, bar_h), Color(1, 1, 1, 0.8))
		draw_rect(Rect2(x, y, bar_w * frac, bar_h), fill)
		_label(Rect2(0, pad, x - s * 0.3, s), "HEALTH", right_size, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 1, true)

	var y := pad + s * 1.2
	_label(Rect2(0, y, w - pad, right_size * 1.4), "KILLS  %d" % gm.kills, right_size, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 0, true)
	# Allies still alive (they're gone for good when destroyed).
	var allies := get_tree().get_first_node_in_group("ally_spawner") as AllySpawner
	if allies != null and not gm.is_game_over:
		var fs := roundi(h * 0.02)
		_label(Rect2(0, y + right_size * 1.5, w - pad, fs * 1.4), "ALLIES   AIR %d   GROUND %d" % [allies.air_alive, allies.ground_alive],
			fs, ALLY_BLUE, HORIZONTAL_ALIGNMENT_RIGHT, 0, true)
	# Enemies still alive (in Classic mode, all of them must go to win).
	if gm.spawner != null and not gm.is_game_over:
		var es := roundi(h * 0.024)
		_label(Rect2(0, y + right_size * 1.5 + h * 0.03, w - pad, es * 1.4), "ENEMIES LEFT  %d" % gm.spawner.enemies_left,
			es, Color(1.0, 0.45, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 0, true)


# Bottom-left: boost meter, speed, and height above the planet when it's close.
func _draw_flight_panel(ship: PlayerShipController, pad: float, h: float) -> void:
	var fs := roundi(h * 0.022)
	var bar_w := h * 0.22
	var bar_h := maxf(3.0, h * 0.008)
	var x := pad
	var y := h - pad - bar_h

	var fill := Color(0.45, 0.8, 1.0, 0.9)
	if ship.boosting:
		fill = Color(0.7, 0.95, 1.0, 1.0)
	elif ship.boost_locked:
		fill = Color(1.0, 0.45, 0.35, 0.8)
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(1, 1, 1, 0.15))
	draw_rect(Rect2(x, y, bar_w * ship.boost_energy, bar_h), fill)
	_label(Rect2(x, y - fs * 1.5, bar_w, fs * 1.4), "BOOST", fs, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, 1, true)

	var line := "SPEED  %d" % roundi(ship.velocity.length() * 10.0)
	var planet := Planet.instance
	if planet != null:
		var alt := planet.altitude(ship.global_position)
		if alt < 200.0:
			line += "     ALT  %d" % roundi(maxf(alt - ship.landing_clearance, 0.0) * 10.0)
		if ship.gravity_weight(ship.global_position) > 0.0:
			line += "     GRAVITY"
	_label(Rect2(x, y - fs * 3.1, h, fs * 1.4), line, fs, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, 1, false)

	# What the keys do right now.
	var keys: Array[String] = []
	if ship.state == PlayerShipController.State.FLYING:
		keys.append("[W/A/S/D]  fly    [Shift]  boost    [Click]  fire    [Z]  zoom")
		keys.append("[E]  bail out of the ship")
		if ship.gravity_weight(ship.global_position) > 0.0:
			keys.append(_chute_key(ship.chute != null, ship.chute_cooldown, "the ship's"))
		else:
			keys.append("No parachute in space (no gravity)")
	_draw_keys(keys, x, y - fs * 3.1, fs)


# After losing the ship: when R will bring a new one.
static func _new_ship_text(ship: PlayerShipController) -> String:
	if ship.replacement_wait > 0.0:
		return "New ship ready in %ds" % ceili(ship.replacement_wait)
	return "Press R to get a new ship"


# The parachute line for the key list: open, cut, or how long until ready.
static func _chute_key(open: bool, cooldown: float, whose: String) -> String:
	if open:
		return "[C]  cut %s parachute" % whose
	if cooldown > 0.0:
		return "Parachute ready in %ds" % ceili(cooldown)
	return "[Q]  open %s parachute (slows your fall)" % whose


# A column of key hints stacked upward from `bottom`, one per line.
func _draw_keys(keys: Array[String], x: float, bottom: float, fs: int) -> void:
	var ks := roundi(fs * 0.9)
	for i in keys.size():
		var y := bottom - ks * 1.5 * (keys.size() - i)
		_label(Rect2(x, y, size.y, ks * 1.4), keys[i], ks, Color(0.75, 0.9, 1.0, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 1, false)


# Bottom-left on foot: the boost meter doubles as sprint stamina and the
# suit boosters' fuel.
func _draw_foot_panel(ship: PlayerShipController, pad: float, h: float) -> void:
	var fs := roundi(h * 0.022)
	var bar_w := h * 0.22
	var bar_h := maxf(3.0, h * 0.008)
	var x := pad
	var y := h - pad - bar_h
	var fill := Color(0.55, 1.0, 0.6, 0.9)
	if ship.pilot.sprinting:
		fill = Color(0.8, 1.0, 0.8, 1.0)
	elif ship.boost_locked:
		fill = Color(1.0, 0.45, 0.35, 0.8)
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(1, 1, 1, 0.15))
	draw_rect(Rect2(x, y, bar_w * ship.boost_energy, bar_h), fill)
	var pilot := ship.pilot
	var title := "SPRINT"
	var mode := "ON FOOT"
	var keys: Array[String] = []
	if pilot.zero_g:
		title = "SUIT BOOST"
		mode = "ZERO-G  ·  no gravity"
		keys.append("[W/A/S/D]  fly where you look    [Shift]  boost")
		keys.append("[Space]  go up    [Ctrl]  go down")
	elif not pilot.on_ground:
		title = "JETPACK"
		mode = "FALLING  ·  land faster than %d and you die" % roundi(pilot.safe_landing_speed * 10.0)
		keys.append("[Space] (hold)  jetpack up    [W/A/S/D]  steer    [Shift]  boost")
		keys.append(_chute_key(pilot.chute != null, pilot.chute_cooldown, "your"))
	else:
		keys.append("[W/A/S/D]  walk    [Shift]  sprint    [Click]  shoot    [Right-click]  aim")
		keys.append("[Space]  jump (hold to use the jetpack)")
		if pilot.chute_cooldown > 0.0:
			keys.append(_chute_key(false, pilot.chute_cooldown, "your"))
	keys.append("[R]  bring a ship to you" if ship.replacement_wait <= 0.0 else _new_ship_text(ship))
	_label(Rect2(x, y - fs * 1.5, bar_w, fs * 1.4), title, fs, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, 1, true)
	var fall := ""
	if not pilot.on_ground and not pilot.zero_g:
		fall = "     FALL  %d" % roundi(maxf(-pilot.velocity.dot(Planet.instance.up_at(pilot.global_position)), 0.0) * 10.0)
	_label(Rect2(x, y - fs * 3.1, h, fs * 1.4), mode + fall, fs, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, 1, false)
	_draw_keys(keys, x, y - fs * 3.1, fs)


# Bottom-right: a green radar scope, turned with the view (ahead is up). A
# sweep line goes round trailing a fading glow; enemies within range light up
# as it passes over them, then fade until the next pass. Hunters show as
# bigger, brighter blips; a tick above or below a blip means it's higher or
# lower than you.
func _draw_radar(ship: PlayerShipController, cam: CameraFollow, w: float, h: float, pad: float) -> void:
	var r := radar_size * h
	var c := Vector2(w - pad - r, h - pad - r)
	var me: Node3D = ship.pilot if ship.on_foot else ship
	var range_units := radar_range_on_foot if ship.on_foot else radar_range_ship

	# Scope: dark glass, rim, range rings and crosshair.
	draw_circle(c, r + 3.0, Color(0, 0, 0, 0.5))
	draw_circle(c, r, Color(0.02, 0.12, 0.05, 0.75))
	for ring in [0.33, 0.66]:
		draw_arc(c, r * ring, 0.0, TAU, 48, Color(RADAR_GREEN, 0.18), 1.0, true)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(RADAR_GREEN, 0.15), 1.0)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(RADAR_GREEN, 0.15), 1.0)

	# Sweep: a glowing wedge fading out behind the line.
	var steps := 24
	var trail := deg_to_rad(70.0)
	for i in steps:
		var a0 := _sweep - trail * float(i) / steps
		var a1 := _sweep - trail * float(i + 1) / steps
		var alpha := 0.28 * (1.0 - float(i) / steps)
		draw_colored_polygon(PackedVector2Array([c, c + _polar(a0, r), c + _polar(a1, r)]), Color(RADAR_GREEN, alpha))
	draw_line(c, c + _polar(_sweep, r), Color(RADAR_GREEN, 0.9), 2.0, true)

	# Blips, placed relative to where you're looking.
	var up := cam.up_direction
	var forward := -cam.global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	var right := forward.cross(up)
	var seen := {}
	for enemy in Enemy.active(get_tree()):
		var rel := enemy.global_position - me.global_position
		var flat := Vector2(rel.dot(right), -rel.dot(forward))
		if flat.length() > range_units:
			continue
		var id := enemy.get_instance_id()
		seen[id] = true
		var p := flat / range_units * r
		var angle := atan2(p.x, -p.y)
		if not _pings.has(id):
			_pings[id] = [angle, blip_fade]
		var ping: Array = _pings[id]
		ping[0] = angle
		var glow := clampf(1.0 - (ping[1] as float) / blip_fade, 0.0, 1.0)
		if glow <= 0.0:
			continue
		var size := (3.2 if enemy.attacking else 2.0) * maxf(1.0, h / 720.0)
		var col := Color(RADAR_GREEN.lightened(0.4) if enemy.attacking else RADAR_GREEN, glow)
		if enemy is MissileTurret:
			# Missile turrets: squares.
			var q := size * 1.1
			draw_rect(Rect2(c + p - Vector2(q, q), Vector2(q, q) * 2.0), col)
		else:
			draw_circle(c + p, size + 2.0, Color(RADAR_GREEN, glow * 0.25))
			draw_circle(c + p, size, col)
		# Higher or lower than you by a fair margin: a small tick above or below.
		var height := rel.dot(up)
		if absf(height) > range_units * 0.08:
			var dir := -1.0 if height > 0.0 else 1.0
			draw_line(c + p + Vector2(0, dir * size), c + p + Vector2(0, dir * (size + 5.0)), col, 1.5)
	# Allies: blue blips, lit by the sweep like everything else.
	for ally in get_tree().get_nodes_in_group("allies"):
		var a := ally as Node3D
		var rel := a.global_position - me.global_position
		var flat := Vector2(rel.dot(right), -rel.dot(forward))
		if flat.length() > range_units:
			continue
		var id := a.get_instance_id()
		seen[id] = true
		var p := flat / range_units * r
		var angle := atan2(p.x, -p.y)
		if not _pings.has(id):
			_pings[id] = [angle, blip_fade]
		var ping: Array = _pings[id]
		ping[0] = angle
		var glow := clampf(1.0 - (ping[1] as float) / blip_fade, 0.0, 1.0)
		if glow > 0.0:
			var size := 2.4 * maxf(1.0, h / 720.0)
			draw_circle(c + p, size + 1.5, Color(ALLY_BLUE, glow * 0.25))
			draw_circle(c + p, size, Color(ALLY_BLUE, glow))
	for id in _pings.keys():
		if not seen.has(id):
			_pings.erase(id)

	# You, at the center, pointing ahead.
	var s := 5.0 * maxf(1.0, h / 720.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.7, s * 0.7)]), Color(1, 1, 1, 0.9))

	# Missiles chasing you: blinking red diamonds, always shown (pinned to the
	# rim if they're still out of range).
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.4) < 0.25
	for m in Missile.active:
		if not m.homing or not blink or m.target != ship:
			continue
		var rel := m.global_position - me.global_position
		var p := Vector2(rel.dot(right), -rel.dot(forward)) / range_units * r
		if p.length() > r - 4.0:
			p = p.normalized() * (r - 4.0)
		var d := 5.0 * maxf(1.0, h / 720.0)
		var mc := c + p
		draw_colored_polygon(PackedVector2Array([mc + Vector2(0, -d), mc + Vector2(d, 0), mc + Vector2(0, d), mc + Vector2(-d, 0)]), Color(1.0, 0.15, 0.1))
		draw_polyline(PackedVector2Array([mc + Vector2(0, -d - 2), mc + Vector2(d + 2, 0), mc + Vector2(0, d + 2), mc + Vector2(-d - 2, 0), mc + Vector2(0, -d - 2)]), Color(1, 1, 1, 0.9), 1.0)

	draw_arc(c, r, 0.0, TAU, 64, Color(RADAR_GREEN, 0.7), 2.0, true)
	var fs := roundi(h * 0.016)
	_label(Rect2(c.x - r, c.y - r - fs * 1.6, r * 2.0, fs * 1.4), "RADAR  %d" % roundi(range_units * 10.0), fs, Color(RADAR_GREEN, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 1, true)


# Top center: WARNING · MISSILE LOCK (flashing red) while a missile is chasing
# the ship; MISSILE LOCKING (amber, with how close the lock is) while a turret
# is locking on.
func _draw_missile_warning(ship: PlayerShipController, w: float, h: float) -> void:
	var chased := false
	for m in Missile.active:
		if m.homing and m.target == ship:
			chased = true
	var lock := 0.0
	for t in MissileTurret.all:
		if not t.dead and t.locking:
			lock = maxf(lock, t.lock_progress)
	var fs := roundi(h * 0.034)
	var rect := Rect2(0, h * 0.11, w, fs * 1.6)
	if chased:
		if fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.32:
			draw_rect(Rect2(w * 0.5 - h * 0.3, rect.position.y - 4, h * 0.6, rect.size.y + 8), Color(0.5, 0.0, 0.0, 0.45))
			_label(rect, "WARNING  ·  MISSILE LOCK", fs, Color(1.0, 0.2, 0.15), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
		var advice := "It's after your empty ship: stay clear of the blast" if ship.on_foot \
			else "One hit and you're dead: boost away (straight up works), out-turn it, or press E to bail out"
		_label(Rect2(0, rect.end.y + 2, w, fs), advice, roundi(fs * 0.5), Color(1, 0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 1, false)
	elif lock > 0.0:
		var amber := Color(1.0, 0.7, 0.15)
		_label(rect, "MISSILE LOCKING", roundi(fs * 0.8), amber, HORIZONTAL_ALIGNMENT_CENTER, 1, true)
		var bw := h * 0.25
		var by := rect.end.y + 2
		draw_rect(Rect2(w * 0.5 - bw * 0.5, by, bw, 4), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(w * 0.5 - bw * 0.5, by, bw * lock, 4), amber)


func _build_missile_cam() -> void:
	_missile_cam_box = SubViewportContainer.new()
	_missile_cam_box.stretch = true
	_missile_cam_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_missile_cam_box.visible = false
	add_child(_missile_cam_box)
	_missile_cam_view = SubViewport.new()
	_missile_cam_view.size = Vector2i(320, 180)
	# Same anti-aliasing as the main view, so it draws with the same (already
	# compiled) shaders.
	_missile_cam_view.msaa_3d = get_viewport().msaa_3d
	_missile_cam_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_missile_cam_box.add_child(_missile_cam_view)
	_missile_cam = Camera3D.new()
	_missile_cam.fov = 35.0
	_missile_cam.near = 0.2
	_missile_cam.far = 4000.0
	_missile_cam_view.add_child(_missile_cam)


# Pick the nearest missile chasing the ship and ride along on its side.
func _update_missile_cam() -> void:
	var gm := GameManager.instance
	var ship := gm.player if gm != null else null
	_cam_missile = null
	if ship != null and not gm.is_game_over:
		var best := INF
		for m in Missile.active:
			if m.homing and m.target == ship:
				var d := m.global_position.distance_to(ship.global_position)
				if d < best:
					best = d
					_cam_missile = m
	_missile_cam_box.visible = _cam_missile != null
	if _cam_missile == null:
		return
	var h := size.y
	var box := Vector2(h * 0.4, h * 0.225)
	_missile_cam_box.size = box
	# Below the top-right stack (health, kills, allies, enemies left, which ends
	# near h * 0.19), leaving room for the MISSILE CAM label above the box.
	_missile_cam_box.position = Vector2(size.x - h * 0.025 - box.x, h * 0.25)
	var m := _cam_missile
	var up := Planet.instance.up_at(m.global_position) if Planet.instance != null else Vector3.UP
	# Mounted on the missile's flank, back toward the tail, looking at the ship
	# (the missile's body runs along the edge of the shot).
	var eye := m.global_position + m.global_basis.x * 0.7 + up * 0.25 + m.global_basis.z * 2.0
	_missile_cam.global_position = eye
	var look := ship.global_position
	if eye.distance_squared_to(look) > 0.01:
		_missile_cam.look_at(look, up)
	_missile_cam.current = true


func _draw_missile_cam_frame(ship: PlayerShipController, h: float) -> void:
	if _cam_missile == null or not _missile_cam_box.visible:
		return
	var rect := Rect2(_missile_cam_box.position, _missile_cam_box.size)
	draw_rect(rect.grow(2.0), Color(1.0, 0.2, 0.15, 0.9), false, 2.0)
	var fs := roundi(h * 0.018)
	var dist := _cam_missile.global_position.distance_to(ship.global_position)
	var fuel := maxf(0.0, _cam_missile.fuel_time - _cam_missile.age)
	_label(Rect2(rect.position.x, rect.position.y - fs * 1.6, rect.size.x, fs * 1.4),
		"MISSILE CAM   %d m   ·   fuel %.0fs" % [roundi(dist * 10.0), fuel], fs, Color(1.0, 0.4, 0.3), HORIZONTAL_ALIGNMENT_LEFT, 1, true)


# Point on the scope at `angle` (clockwise from straight up) and distance `r`.
static func _polar(angle: float, r: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle)) * r


func _draw_game_over(gm: GameManager, w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.55))
	var bs := roundi(h * 0.08)
	if gm.mission_complete:
		_label(Rect2(0, h * 0.25, w, roundi(h * 0.026) * 2.0), "ALL ENEMIES DESTROYED", roundi(h * 0.026), Color(0.6, 1.0, 0.7, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
		_label(Rect2(0, h * 0.32, w, bs * 1.5), "MISSION COMPLETE", bs, Color(0.4, 1.0, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
	else:
		_label(Rect2(0, h * 0.32, w, bs * 1.5), "GAME OVER", bs, Color(1.0, 0.3, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
	var cs := roundi(h * 0.035)
	var sub := Color(1, 1, 1, 0.75)
	if not gm.death_reason.is_empty():
		var rs := roundi(h * 0.026)
		_label(Rect2(0, h * 0.25, w, rs * 2.0), gm.death_reason, rs, Color(1.0, 0.7, 0.6, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 1, true)
	_label(Rect2(0, h * 0.44, w, cs * 2.0), "Kills %d   ·   Score %s" % [gm.kills, _thousands(gm.score)], cs, sub, HORIZONTAL_ALIGNMENT_CENTER, 1, false)


# Screen-center crosshair: four arms around a gap plus a center dot, with a
# dark outline so it reads against both stars and hull.
func _draw_crosshair(w: float, h: float) -> void:
	var arm := arm_length * h
	var g := gap * h
	var t := maxf(1.0, thickness * h)
	var c := Vector2(w * 0.5, h * 0.5)
	_crosshair_shape(c, arm, g, t, t * 0.5, Color(0, 0, 0, crosshair_color.a * 0.6))
	_crosshair_shape(c, arm, g, t, 0.0, crosshair_color)


func _crosshair_shape(c: Vector2, arm: float, g: float, t: float, o: float, col: Color) -> void:
	var half := t * 0.5
	draw_rect(Rect2(c.x - g - arm - o, c.y - half - o, arm + 2 * o, t + 2 * o), col)  # left
	draw_rect(Rect2(c.x + g - o, c.y - half - o, arm + 2 * o, t + 2 * o), col)        # right
	draw_rect(Rect2(c.x - half - o, c.y - g - arm - o, t + 2 * o, arm + 2 * o), col)  # top
	draw_rect(Rect2(c.x - half - o, c.y + g - o, t + 2 * o, arm + 2 * o), col)        # bottom
	draw_rect(Rect2(c.x - half - o, c.y - half - o, t + 2 * o, t + 2 * o), col)       # dot


# Red brackets around enemies that are on screen. Off-screen enemies get no
# marker: you have to find them yourself.
func _draw_enemy_indicators(cam: Camera3D, w: float, h: float) -> void:
	var s := marker_size * h
	var center := Vector2(w * 0.5, h * 0.5)
	var focal := (h * 0.5) / tan(deg_to_rad(cam.fov) * 0.5)
	var to_view := cam.global_transform.affine_inverse()

	# Classic mode, last few left: arrows at the screen edge point to each one.
	var gm0 := GameManager.instance
	if GameMode.is_classic and gm0 != null and gm0.spawner != null and gm0.spawner.enemies_left <= 5:
		for enemy in Enemy.active(get_tree()):
			if enemy is MissileTurret:
				continue   # turrets don't count toward winning
			var lv := to_view * enemy.global_position
			var lp := center + Vector2(lv.x, -lv.y) * (focal / maxf(absf(-lv.z), 0.0001))
			var on := -lv.z > 0.0 and lp.x >= 0 and lp.x <= w and lp.y >= 0 and lp.y <= h
			if on:
				_draw_bracket(lp, s)
			else:
				_draw_last_enemy_arrow(center, lp if -lv.z > 0.0 else center + (center - lp), s, w, h)
		return
	# Only enemy fighters hunting you, and only once they're within radar range,
	# are marked; patrolling or far-off ones you have to spot yourself. Ground
	# robots and missile turrets are never marked (they show on the radar).
	var gm := GameManager.instance
	var me: Node3D = null
	var range_units := radar_range_ship
	if gm != null and gm.player != null:
		me = gm.player.pilot if gm.player.on_foot else gm.player
		range_units = radar_range_on_foot if gm.player.on_foot else radar_range_ship
	for enemy in Enemy.active(get_tree()):
		if not enemy.attacking or enemy is GroundRobot or enemy is MissileTurret:
			continue
		if me != null and enemy.global_position.distance_to(me.global_position) > range_units:
			continue
		var local := to_view * enemy.global_position
		var depth := -local.z
		var behind := depth < 0.0
		var k := focal / maxf(absf(depth), 0.0001)
		var p := center + Vector2(local.x * k, -local.y * k)

		if not behind and p.x >= 0 and p.x <= w and p.y >= 0 and p.y <= h:
			_draw_bracket(p, s)


# A red triangle at the screen edge pointing toward an off-screen enemy.
func _draw_last_enemy_arrow(center: Vector2, p: Vector2, s: float, w: float, h: float) -> void:
	var d := p - center
	if d.length_squared() < 1.0:
		d = Vector2.DOWN
	var margin := h * 0.06
	var kx := (w * 0.5 - margin) / absf(d.x) if absf(d.x) > 0.001 else INF
	var ky := (h * 0.5 - margin) / absf(d.y) if absf(d.y) > 0.001 else INF
	var pos := center + d * minf(kx, ky)
	var dir := d.normalized()
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([pos + dir * s * 0.6, pos - dir * s * 0.4 + side * s * 0.4, pos - dir * s * 0.4 - side * s * 0.4]), indicator_color)


func _draw_bracket(p: Vector2, s: float) -> void:
	var half := s * 0.5
	var length := s * 0.3
	var t := maxf(1.0, s * 0.07)
	# Four corners of a square around the enemy.
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var cx: float = p.x + sx * half
			var cy: float = p.y + sy * half
			draw_rect(Rect2(cx if sx < 0 else cx - length, cy - t * 0.5, length, t), indicator_color)
			draw_rect(Rect2(cx - t * 0.5, cy if sy < 0 else cy - length, t, length), indicator_color)


# Like a Unity GUI.Label: text in a rect, aligned horizontally, and vertically
# at the top (valign 0) or middle (valign 1).
func _label(rect: Rect2, text: String, font_size: int, color: Color, halign: HorizontalAlignment, valign: int, bold: bool) -> void:
	var font: Font = _bold if bold else _font
	var ascent := font.get_ascent(font_size)
	var line_h := font.get_height(font_size)
	var y := rect.position.y + ascent if valign == 0 else rect.position.y + (rect.size.y - line_h) * 0.5 + ascent
	draw_string(font, Vector2(rect.position.x, y), text, halign, rect.size.x, font_size, color)


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
