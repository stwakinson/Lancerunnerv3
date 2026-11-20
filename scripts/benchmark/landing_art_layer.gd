class_name BenchmarkLandingArtLayer
extends Node2D

# Source artwork stays intact. Framing and overscan are scene transforms, so
# replacement transparent plates do not need destructive image edits.

var texture: Texture2D
var frame := Rect2(-64, -36, 768, 432)
var extend_ground := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()


func _draw() -> void:
	if extend_ground:
		draw_rect(Rect2(-128, frame.end.y - 20, 896, 160), Color("12252b"))
	if texture != null:
		draw_texture_rect(texture, frame, false)
