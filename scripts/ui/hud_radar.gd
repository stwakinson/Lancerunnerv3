class_name HudRadar
extends RefCounted

# Owns the sweep and contact history. Draws on the HUD's canvas during its
# _draw callback so radar layering stays the same as the other overlays.

const RADAR_GREEN := Color(0.3, 1.0, 0.45)
const ALLY_BLUE := Color(0.45, 0.72, 1.0)

var _sweep := 0.0
# Instance id -> [angle on the scope, seconds since the sweep last lit it].
var _pings := {}


func advance(delta: float, sweep_period: float) -> void:
	var previous := _sweep
	_sweep = fposmod(_sweep + TAU * delta / sweep_period, TAU)
	# Light up every blip the sweep line passed over since last frame.
	var swept := fposmod(_sweep - previous, TAU)
	for id in _pings:
		var ping: Array = _pings[id]
		ping[1] += delta
		if fposmod(ping[0] - previous, TAU) <= swept:
			ping[1] = 0.0


# Bottom-right: a green radar scope, turned with the view (ahead is up). A
# sweep line goes round trailing a fading glow; enemies within range light up
# as it passes over them, then fade until the next pass. Hunters show as
# bigger, brighter blips; a tick above or below a blip means it's higher or
# lower than you.
func draw_scope(canvas: Control, ship: PlayerShipController, cam: CameraFollow,
		radar_size: float, range_units: float, blip_fade: float, font: Font) -> void:
	var w := canvas.size.x
	var h := canvas.size.y
	var pad := h * 0.025
	var r := radar_size * h
	var c := Vector2(w - pad - r, h - pad - r)
	var me: Node3D = ship.pilot if ship.on_foot else ship

	# Scope: dark glass, rim, range rings and crosshair.
	canvas.draw_circle(c, r + 3.0, Color(0, 0, 0, 0.5))
	canvas.draw_circle(c, r, Color(0.02, 0.12, 0.05, 0.75))
	for ring in [0.33, 0.66]:
		canvas.draw_arc(c, r * ring, 0.0, TAU, 48, Color(RADAR_GREEN, 0.18), 1.0, true)
	canvas.draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(RADAR_GREEN, 0.15), 1.0)
	canvas.draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(RADAR_GREEN, 0.15), 1.0)

	# Sweep: a glowing wedge fading out behind the line.
	var steps := 24
	var trail := deg_to_rad(70.0)
	for i in steps:
		var a0 := _sweep - trail * float(i) / steps
		var a1 := _sweep - trail * float(i + 1) / steps
		var alpha := 0.28 * (1.0 - float(i) / steps)
		canvas.draw_colored_polygon(PackedVector2Array([c, c + _polar(a0, r), c + _polar(a1, r)]), Color(RADAR_GREEN, alpha))
	canvas.draw_line(c, c + _polar(_sweep, r), Color(RADAR_GREEN, 0.9), 2.0, true)

	# Blips, placed relative to where you're looking.
	var up := cam.up_direction
	var forward := -cam.global_basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	var right := forward.cross(up)
	var seen := {}
	for enemy in Enemy.active(canvas.get_tree()):
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
			canvas.draw_rect(Rect2(c + p - Vector2(q, q), Vector2(q, q) * 2.0), col)
		else:
			canvas.draw_circle(c + p, size + 2.0, Color(RADAR_GREEN, glow * 0.25))
			canvas.draw_circle(c + p, size, col)
		# Higher or lower than you by a fair margin: a small tick above or below.
		var height := rel.dot(up)
		if absf(height) > range_units * 0.08:
			var dir := -1.0 if height > 0.0 else 1.0
			canvas.draw_line(c + p + Vector2(0, dir * size), c + p + Vector2(0, dir * (size + 5.0)), col, 1.5)
	# Allies: blue blips, lit by the sweep like everything else.
	for ally in canvas.get_tree().get_nodes_in_group("allies"):
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
			canvas.draw_circle(c + p, size + 1.5, Color(ALLY_BLUE, glow * 0.25))
			canvas.draw_circle(c + p, size, Color(ALLY_BLUE, glow))
	for id in _pings.keys():
		if not seen.has(id):
			_pings.erase(id)

	# You, at the center, pointing ahead.
	var s := 5.0 * maxf(1.0, h / 720.0)
	canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.7, s * 0.7)]), Color(1, 1, 1, 0.9))

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
		canvas.draw_colored_polygon(PackedVector2Array([mc + Vector2(0, -d), mc + Vector2(d, 0), mc + Vector2(0, d), mc + Vector2(-d, 0)]), Color(1.0, 0.15, 0.1))
		canvas.draw_polyline(PackedVector2Array([mc + Vector2(0, -d - 2), mc + Vector2(d + 2, 0), mc + Vector2(0, d + 2), mc + Vector2(-d - 2, 0), mc + Vector2(0, -d - 2)]), Color(1, 1, 1, 0.9), 1.0)

	canvas.draw_arc(c, r, 0.0, TAU, 64, Color(RADAR_GREEN, 0.7), 2.0, true)
	var fs := roundi(h * 0.016)
	var rect := Rect2(c.x - r, c.y - r - fs * 1.6, r * 2.0, fs * 1.4)
	var y := rect.position.y + (rect.size.y - font.get_height(fs)) * 0.5 + font.get_ascent(fs)
	canvas.draw_string(font, Vector2(rect.position.x, y), "RADAR  %d" % roundi(range_units * 10.0),
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fs, Color(RADAR_GREEN, 0.8))


# Point on the scope at `angle` (clockwise from straight up) and distance `r`.
static func _polar(angle: float, r: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle)) * r
