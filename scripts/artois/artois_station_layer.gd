extends Node2D
## Native 640x360 placeholder plates; six independently moving parallax layers.
var kind := 0
var profile := {}
var clock := 0.0
var mist_enabled := true


func _draw() -> void:
	var faction: String = profile.get("faction", "Borderlanders")
	var theme: String = profile.get("theme", "exchange")
	var accent := Color("d8ad68")
	if faction == "Valois": accent = Color("779ed4")
	elif faction == "Britannian": accent = Color("c25d49")
	elif faction == "Freebooters": accent = Color("b37b67")
	elif faction == "Chapter of St Paul": accent = Color("b9a890")
	match kind:
		0:
			draw_rect(Rect2(-90, -50, 820, 460), Color("111c30"))
			for i in 95:
				var point := Vector2(fposmod(i * 79.3, 740) - 50, fposmod(i * 43.7, 270))
				draw_rect(Rect2(point, Vector2(1, 1)), Color(0.6, 0.7, 0.85, 0.55))
			draw_circle(Vector2(490, 130), 67, Color("49536f"))
			draw_circle(Vector2(479, 121), 60, Color("25334c"))
			if theme in ["mining", "salvage"]:
				for i in 11:
					var x := float(i * 71 - 40)
					var height := 90.0 + fposmod(i * 47.0, 150)
					draw_rect(Rect2(x, 230 - height, 25, height), Color("736c79"))
					draw_rect(Rect2(x + 18, 230 - height, 14, height), Color("b78b5d"))
		1:
			draw_rect(Rect2(-80, -40, 800, 69), Color("273444"))
			draw_rect(Rect2(-80, 190, 800, 80), Color("28333e"))
			for x in [-35, 110, 300, 555, 690]:
				draw_rect(Rect2(x, -30, 15, 230), Color("3e4c59"))
				draw_rect(Rect2(x + 4, -30, 3, 225), Color("687078"))
			for y in [30, 180]: draw_rect(Rect2(-70, y, 800, 8), Color("404c59"))
			for x in [124, 275]:
				draw_rect(Rect2(x, 35, 24, 95), accent.darkened(0.25))
				draw_rect(Rect2(x + 10, 43, 4, 68), Color("ddc89c"))
				draw_rect(Rect2(x + 3, 62, 18, 4), Color("ddc89c"))
			if theme == "chapel":
				for x in [335, 430, 525]:
					draw_arc(Vector2(x, 80), 35, PI, TAU, 20, Color("a29b88"), 8)
					draw_rect(Rect2(x - 39, 80, 8, 130), Color("a29b88"))
					draw_rect(Rect2(x + 31, 80, 8, 130), Color("a29b88"))
		2:
			var x := fposmod(clock * 10, 800) - 80
			draw_rect(Rect2(x, 143, 26, 4), Color("87b8c9"))
			draw_rect(Rect2(x + 21, 143, 6, 2), Color("e8bc7e"))
			if mist_enabled:
				for i in 8:
					var at := Vector2(300 + i * 42, 230 - fposmod(clock * 8 + i * 19, 80))
					draw_rect(Rect2(at, Vector2(20, 3)), Color(0.6, 0.7, 0.75, 0.08))
		3:
			draw_rect(Rect2(-80, 278, 800, 140), Color("35404a"))
			for y in range(284, 401, 18): draw_line(Vector2(-80, y), Vector2(720, y), Color("4a5159"), 1)
			for x in range(-60, 741, 32): draw_line(Vector2(x, 278), Vector2(x - 50, 400), Color("242d38"), 1)
			_counter(Rect2(20, 218, 105, 65), accent, false)
			_counter(Rect2(146, 225, 115, 58), accent, true)
			# A simple parked trader silhouette, leaving the two service counters clear.
			draw_rect(Rect2(382, 226, 171, 43), Color("b4b5b0"))
			draw_rect(Rect2(398, 215, 72, 16), accent)
			draw_rect(Rect2(476, 215, 37, 18), Color("738d9c"))
			draw_rect(Rect2(382, 244, 171, 6), accent)
			draw_rect(Rect2(399, 269, 9, 18), Color("202c36"))
			draw_rect(Rect2(524, 269, 9, 18), Color("202c36"))
			draw_rect(Rect2(548, 233, 8, 24), Color("80cfdf"))
			for i in 5:
				draw_rect(Rect2(292 + i * 9, 267, 6, 11), Color("9c8059"))
		4:
			for i in 5:
				var x := 52.0 + i * 60
				if i > 1: x += sin(clock * 0.2 + i) * 12
				_person(Vector2(x, 286 + (i % 2) * 4), accent)
		5:
			draw_rect(Rect2(-80, 335, 800, 70), Color("14212d"))
			draw_rect(Rect2(-70, 320, 160, 15), Color("24313c"))
			draw_rect(Rect2(570, 292, 140, 45), Color("253442"))
			draw_rect(Rect2(584, 296, 27, 28), accent.darkened(0.5))
			for x in [-30, 610]: draw_rect(Rect2(x, -50, 8, 410), Color("1c2a36"))


func _counter(area: Rect2, accent: Color, equipment: bool) -> void:
	draw_rect(area, Color("283644"))
	draw_rect(Rect2(area.position - Vector2(4, 15), Vector2(area.size.x + 8, 16)), accent.darkened(0.3))
	draw_rect(Rect2(area.position + Vector2(3, 7), area.size - Vector2(6, 12)), Color("182632"))
	draw_rect(Rect2(area.position + Vector2(0, 43), Vector2(area.size.x, 10)), Color("8f7655"))
	for i in 5:
		var at := area.position + Vector2(9 + i * 18, 28)
		draw_rect(Rect2(at, Vector2(13, 15 if equipment else 18)), Color("708d9d") if equipment else Color("b39062"))
		if equipment: draw_rect(Rect2(at + Vector2(3, -7), Vector2(4, 16)), Color("a3bdc8"))


func _person(at: Vector2, colour: Color) -> void:
	draw_rect(Rect2(at + Vector2(-2, -17), Vector2(5, 5)), Color("c7a489"))
	draw_rect(Rect2(at + Vector2(-3, -12), Vector2(7, 9)), colour.darkened(0.2))
	draw_rect(Rect2(at + Vector2(-3, -3), Vector2(2, 5)), Color("172633"))
	draw_rect(Rect2(at + Vector2(2, -3), Vector2(2, 5)), Color("172633"))
