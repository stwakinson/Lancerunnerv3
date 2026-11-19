class_name BenchmarkLandingLayer
extends Node2D

# Deliberately simple, original pixel blockout. Layered art can replace these
# nodes without changing docking, parallax or the high-resolution interface.

var depth := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	queue_redraw()


func _rect(x: float, y: float, w: float, h: float, hex: String) -> void:
	draw_rect(Rect2(floorf(x), floorf(y), w, h), Color.html(hex))


func _draw() -> void:
	_rng.seed = 1415 + depth
	match depth:
		0: _sky()
		1: _castle()
		2: _town()
		3: _foreground()


func _sky() -> void:
	for y in range(-30, 390, 3):
		var colour := Color("101e32").lerp(Color("467075"), clampf(float(y) / 340, 0, 1))
		draw_rect(Rect2(-40, y, 720, 3), colour)
	for i in 35:
		var x := _rng.randf_range(-50, 700)
		var y := _rng.randf_range(5, 160)
		draw_circle(Vector2(x, y), _rng.randf_range(20, 75), Color(0.1, 0.2, 0.25, 0.16))
	# A warm break under the storm cloud.
	for i in 18:
		draw_rect(Rect2(400 - i * 8, 180 + i * 2, 270 + i * 14, 3), Color(0.75, 0.49, 0.32, 0.1))


func _castle() -> void:
	# A fortress built on a cliff: clear silhouette before surface detail.
	draw_colored_polygon(PackedVector2Array([Vector2(260, 180), Vector2(290, 130), Vector2(560, 100), Vector2(650, 165), Vector2(640, 265), Vector2(260, 240)]), Color("25363c"))
	for i in 85:
		var x := _rng.randi_range(290, 650)
		var y := _rng.randi_range(150, 240)
		_rect(x, y, _rng.randi_range(3, 12), _rng.randi_range(10, 55), ["293b41", "33494b", "3b4f4d"][i % 3])
	_rect(320, 83, 250, 80, "283e49")
	_rect(338, 57, 65, 80, "304955")
	_rect(421, 48, 53, 90, "324853")
	_rect(484, 69, 66, 90, "2c424d")
	for x in [309, 356, 410, 466, 554]:
		_rect(x, 55 if x % 2 == 0 else 75, 19, 110, "39515c")
		var top := 55 if x % 2 == 0 else 75
		draw_colored_polygon(PackedVector2Array([Vector2(x - 4, top), Vector2(x + 9, top - 18), Vector2(x + 23, top)]), Color("192c3a"))
		_rect(x + 9, top - 28, 1, 10, "5f7d82")
		_rect(x + 9, top - 29, 2, 2, "ec9161")
	for x in range(327, 563, 9):
		for y in range(90, 151, 12):
			if _rng.randf() > 0.35:
				_rect(x - 1, y - 1, 4, 6, "6c6553")
				_rect(x, y, 2, 4, "e3a963")
	for x in range(320, 577, 8):
		_rect(x, 155, 5, 5, "53635e")
	# A spacecraft beacon and atmospheric light beam.
	draw_colored_polygon(PackedVector2Array([Vector2(550, 86), Vector2(583, 230), Vector2(624, 230)]), Color(0.37, 0.7, 0.76, 0.07))
	_rect(542, 80, 17, 3, "73909a")
	_rect(554, 80, 2, 2, "b6ece6")


func _house(x: float, y: float, w: float, h: float, roof: String) -> void:
	_rect(x, y, w, h, "7b7460")
	_rect(x + w * 0.65, y, w * 0.35, h, "555a51")
	draw_colored_polygon(PackedVector2Array([Vector2(x - 5, y + 1), Vector2(x + w * 0.45, y - h * 0.55), Vector2(x + w + 5, y + 1)]), Color.html(roof))
	_rect(x, y + 1, w, 3, "283435")
	for offset in [0.0, 0.45, 0.95]:
		_rect(x + w * offset, y, 3, h, "373b35")
	_rect(x, y + h * 0.45, w, 3, "3d3f36")
	draw_line(Vector2(x + 3, y + 3), Vector2(x + w * 0.45, y + h * 0.45), Color("393d36"), 2)
	for wx in [x + w * 0.15, x + w * 0.65]:
		_rect(wx - 1, y + 8, 9, 13, "504c3b")
		_rect(wx, y + 9, 6, 10, "e8ad61")
		_rect(wx + 3, y + 9, 1, 10, "79603f")
	_rect(x + w * 0.43, y + h * 0.65, 10, h * 0.35, "252f2e")
	_rect(x + w * 0.43 + 2, y + h * 0.65 + 2, 6, h * 0.35 - 2, "a37147")


func _town() -> void:
	_rect(-40, 260, 720, 140, "263b40")
	# Perspective paving and irregular wet stone highlights.
	for y in range(258, 385, 7):
		var spacing := 10 + (y - 258) / 6
		for x in range(-30, 700, int(spacing)):
			var offset := 5 if y % 2 else 0
			_rect(x + offset, y, spacing - 2, 3, ["34484a", "3d5353", "2e4448", "52615b"][_rng.randi_range(0, 3)])
	_house(10, 193, 70, 77, "293f43")
	_house(75, 173, 61, 96, "364347")
	_house(142, 204, 50, 68, "2e4142")
	_house(199, 204, 46, 62, "38484a")
	_house(248, 216, 38, 48, "283e43")
	_rect(91, 140, 7, 24, "5d6762")
	for i in 6:
		draw_circle(Vector2(94 + i * 2, 132 - i * 7), 6 + i * 2, Color(0.32, 0.42, 0.43, 0.12))
	# Lamps and wet reflections.
	for x in [70, 190, 330, 565]:
		_rect(x, 216, 2, 65, "152c35")
		_rect(x - 3, 215, 8, 2, "64736c")
		draw_circle(Vector2(x + 1, 222), 16, Color(0.97, 0.62, 0.27, 0.055))
		_rect(x - 1, 218, 5, 7, "f4c47c")
		for i in 7:
			_rect(x - i * 1.5, 281 + i * 4, 3 + i * 3, 1, "8b7656" if i % 2 else "645f4e")
	# Bunting adds scale and ties the medieval street together.
	draw_line(Vector2(8, 184), Vector2(316, 228), Color("61706a"), 1)
	for i in 12:
		var x := 20 + i * 24
		var y := 185 + i * 3.4
		draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 11, y + 2), Vector2(x + 6, y + 14)]), Color.html("a25d45" if i % 2 else "55777a"))
	# Landed ship: a deliberately graphic proxy for a future authored sprite.
	draw_colored_polygon(PackedVector2Array([Vector2(415, 262), Vector2(458, 241), Vector2(558, 244), Vector2(592, 270), Vector2(449, 282)]), Color("9baab0"))
	draw_colored_polygon(PackedVector2Array([Vector2(415, 262), Vector2(449, 282), Vector2(592, 270), Vector2(581, 284), Vector2(449, 293), Vector2(411, 274)]), Color("3a4e5b"))
	draw_colored_polygon(PackedVector2Array([Vector2(441, 250), Vector2(458, 241), Vector2(558, 244), Vector2(573, 255)]), Color("bb4a35"))
	_rect(465, 237, 44, 10, "1f4053")
	_rect(471, 237, 29, 2, "75abb5")
	_rect(444, 279, 8, 5, "8be1e8")
	_rect(559, 274, 14, 4, "86d5db")
	_rect(463, 290, 4, 8, "172e36")
	_rect(556, 282, 4, 13, "172e36")
	for x in [453, 564]:
		for i in 5:
			_rect(x - 4 + i, 300 + i * 4, 12 - i, 1, "436e78")


func _foreground() -> void:
	# Market stalls, flower boxes and small figures form the near layer.
	for x in [10, 118, 265]:
		_rect(x, 285, 61, 19, "614d3c")
		_rect(x + 3, 270, 2, 34, "665843")
		_rect(x + 56, 270, 2, 34, "665843")
		for i in 6:
			_rect(x + i * 10, 269, 10, 8, "a96444" if i % 2 else "c9b58c")
		for i in 20:
			_rect(x + _rng.randf_range(3, 56), _rng.randf_range(281, 290), 3, 3, ["75936a", "b6b56d", "a16352"][i % 3])
	for at in [Vector2(225, 291), Vector2(354, 281), Vector2(385, 312), Vector2(298, 278)]:
		_rect(at.x, at.y - 11, 4, 4, "b9a084")
		_rect(at.x - 1, at.y - 7, 6, 9, "71858a")
		_rect(at.x, at.y + 2, 2, 5, "182e36")
		_rect(at.x + 3, at.y + 2, 2, 5, "182e36")
	for side in [0, 1]:
		for i in 110:
			var x := _rng.randf_range(-25, 175) if side == 0 else _rng.randf_range(515, 680)
			var y := _rng.randf_range(330, 385)
			_rect(x, y, _rng.randi_range(2, 5), _rng.randi_range(2, 5), ["1c3b3e", "36564b", "67845f", "9b8c64", "a47773"][i % 5])
