extends Node2D
## A small diegetic gazette board, aligned to the room's parallax layer.
const HIT_RECT := Rect2(-18, -23, 36, 46)
func _draw() -> void:
	draw_rect(HIT_RECT.grow(2), Color("302a24"))
	draw_rect(HIT_RECT, Color("745038"))
	for offset in [Vector2(-13, -18), Vector2(1, -12), Vector2(-11, 1)]:
		draw_rect(Rect2(offset, Vector2(12, 17)), Color("baac86"))
		for y in [4, 7, 10]: draw_line(offset + Vector2(2, y), offset + Vector2(10, y), Color("5c564a"), 1)
	draw_circle(Vector2(0, -30), 5, Color("122d38"))
	draw_circle(Vector2(0, -30), 4, Color("8ed4d7"), false, 1)
