class_name BenchmarkLandingAmbience
extends Node2D

# Animation passes have explicit depth and a shared clock. All effects are
# bounded draws; no accumulating rain, smoke or traffic nodes are spawned.

enum Pass { TRAFFIC, MIST, STREET, RAIN }
var kind := Pass.TRAFFIC
var elapsed := 0.0
var weather_enabled := true


func advance(time: float, weather: bool) -> void:
	elapsed = time
	weather_enabled = weather
	queue_redraw()


func _draw() -> void:
	match kind:
		Pass.TRAFFIC: _traffic()
		Pass.MIST: _mist()
		Pass.STREET: _street()
		Pass.RAIN: _rain()


func _pixel(at: Vector2, dimensions: Vector2, colour: Color) -> void:
	draw_rect(Rect2(at.round(), dimensions), colour)


func _glow(at: Vector2, radius: float, colour: Color, strength: float) -> void:
	for i in range(8, 0, -1):
		draw_circle(at, radius * i / 8.0, Color(colour, strength * (1.0 - i / 10.0)))


func _traffic() -> void:
	for i in 3:
		var x := fposmod(elapsed * (5.0 + i * 2.0) + i * 230.0, 850.0) - 100.0
		if i % 2:
			x = 640.0 - x
		var at := Vector2(roundf(x), 107 + i * 26 + sin(elapsed * 0.45 + i) * 3)
		# Small hull silhouettes are deliberately subordinate to the carrier.
		draw_colored_polygon(PackedVector2Array([at + Vector2(-7, 0), at + Vector2(4, -2), at + Vector2(9, 1), at + Vector2(-5, 3)]), Color("1b3640"))
		_pixel(at + Vector2(-7, 1), Vector2(2, 1), Color("7acddd"))
		_pixel(at + Vector2(4, 0), Vector2(2, 1), Color("cc9c6d"))
		if i == 1:
			draw_colored_polygon(PackedVector2Array([at + Vector2(1, 2), at + Vector2(-13, 36), at + Vector2(17, 36)]), Color(0.4, 0.73, 0.82, 0.045))


func _mist() -> void:
	if not weather_enabled:
		return
	for i in 18:
		var at := Vector2(fposmod(i * 73.0 + elapsed * 1.7, 860) - 110, 215 + sin(i * 2.0 + elapsed * 0.12) * 17)
		for ring in range(4, 0, -1):
			draw_set_transform(at, 0.0, Vector2(2.5, 0.45))
			draw_circle(Vector2.ZERO, ring * 12, Color(0.35, 0.58, 0.65, 0.011))
		draw_set_transform(Vector2.ZERO)


func _person(at: Vector2, scale_factor: float, phase: float, coat: Color) -> void:
	var stride := roundf(sin(phase) * 1.5)
	draw_set_transform(at.round(), 0.0, Vector2.ONE * scale_factor)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(0, -1), Vector2(7, 0), Vector2(1, 2)]), Color(0.01, 0.04, 0.06, 0.4))
	_pixel(Vector2(-2, -19), Vector2(4, 4), Color("ae9788"))
	_pixel(Vector2(-2, -20), Vector2(4, 2), Color("27333e"))
	_pixel(Vector2(-3, -15), Vector2(6, 9), coat)
	_pixel(Vector2(-4, -12), Vector2(2, 6), coat.darkened(0.25))
	_pixel(Vector2(3, -12), Vector2(2, 6), coat.lightened(0.06))
	_pixel(Vector2(-3, -6), Vector2(2, 6 + stride), Color("14252f"))
	_pixel(Vector2(1, -6), Vector2(2, 6 - stride), Color("182c34"))
	_pixel(Vector2(-2, -14), Vector2(1, 7), Color("b58e60"))
	draw_set_transform(Vector2.ZERO)


func _street() -> void:
	_person(Vector2(282 + sin(elapsed * 0.12) * 31, 279), 0.68, elapsed * 3.0, Color("5a6b68"))
	_person(Vector2(417 + sin(elapsed * 0.09 + 2) * 28, 280), 0.72, elapsed * 2.8, Color("66505a"))
	_person(Vector2(330, 294), 1.0, 0.0, Color("334d62"))
	# Cyan visor and a warm shoulder accent distinguish the pilot silhouette.
	_pixel(Vector2(329, 276), Vector2(3, 1), Color("8bc5d4"))
	_pixel(Vector2(327, 280), Vector2(2, 3), Color("a25b43"))
	# A small brazier provides animated local light and a street-scale anchor.
	var at := Vector2(224, 282)
	var flicker := 0.82 + sin(elapsed * 9) * 0.08 + sin(elapsed * 17) * 0.06
	_glow(at + Vector2(0, -5), 14, Color("e9a15e"), 0.012 * flicker)
	_pixel(at + Vector2(-4, -4), Vector2(8, 4), Color("3f3833"))
	_pixel(at + Vector2(-3, 0), Vector2(2, 5), Color("172a31"))
	_pixel(at + Vector2(2, 0), Vector2(2, 5), Color("172a31"))
	for i in 4:
		var height := 3 + int(fposmod(i * 3 + elapsed * 11, 4))
		_pixel(at + Vector2(-3 + i * 2, -4 - height), Vector2(2, height), Color("e68b48") if i % 2 else Color("f4c175"))
	for i in 7:
		var y := fposmod(elapsed * 9 + i * 5, 31)
		_pixel(at + Vector2(sin(i * 3 + elapsed) * 4, -8 - y), Vector2.ONE, Color(0.95, 0.56, 0.24, (1.0 - y / 31.0) * 0.55))
	# Restrained amber reflection glints, not geometric distortion of the art.
	for i in 6:
		var alpha := (0.5 + sin(elapsed * 1.7 + i) * 0.3) * 0.08
		draw_line(Vector2(70 - i * 2, 282 + i * 3), Vector2(82 + i * 3, 282 + i * 3), Color(0.95, 0.61, 0.29, alpha), 1)


func _rain() -> void:
	if not weather_enabled:
		return
	for i in 200:
		var near := i % 3 == 0
		var speed := 200.0 if near else 105.0
		var x := fposmod(i * 79.7 - elapsed * speed * 0.17, 680) - 20
		var y := fposmod(i * 43.3 + elapsed * speed, 400) - 20
		var streak := Vector2(-2, 7) if near else Vector2(-1, 3)
		draw_line(Vector2(x, y).round(), Vector2(x, y).round() + streak, Color(0.56, 0.75, 0.8, 0.22 if near else 0.10), 1)
	for i in 18:
		var phase := fposmod(elapsed * 1.4 + i * 0.17, 1.0)
		var at := Vector2(fposmod(i * 71.0, 640), 273 + i % 4 * 7)
		draw_arc(at, 0.5 + phase * 2.5, 0, PI, 6, Color(0.49, 0.7, 0.75, (1.0 - phase) * 0.14), 1)
