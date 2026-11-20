extends Node2D
## Small original pixel placeholder, attached to the market's street-life layer.
func _draw() -> void:
	draw_ellipse_shadow()
	draw_rect(Rect2(-4, -25, 8, 7), Color("d9b18a"))
	draw_rect(Rect2(-5, -27, 10, 4), Color("465c72"))
	draw_rect(Rect2(-6, -18, 12, 13), Color("39596a"))
	draw_rect(Rect2(-2, -18, 4, 12), Color("d8ac68"))
	draw_rect(Rect2(-9, -17, 3, 12), Color("243643"))
	draw_rect(Rect2(6, -17, 3, 12), Color("243643"))
	draw_rect(Rect2(-5, -5, 4, 7), Color("1c2a36"))
	draw_rect(Rect2(1, -5, 4, 7), Color("1c2a36"))
	draw_rect(Rect2(-2, -41, 4, 9), Color("ffc976"))
	draw_rect(Rect2(-2, -30, 4, 3), Color("ffc976"))


func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0, 2), 0, Vector2(1, 0.25))
	draw_circle(Vector2.ZERO, 12, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO)
