extends Node2D
## A separate atlas actor. Nothing is painted into the empty room plate.
const ATLAS = preload("res://assets/artois/tavern/patrons.png")
var atlas_texture: Texture2D = ATLAS
var atlas_grid := Vector2i(4, 4)
var talk_id := ""
var profile := {}
var column := 0
var row := 0
var dimensions := Vector2(90, 98)
var contact_id := ""
var guest_name := ""
var _atlas: AtlasTexture
var hit_rect: Rect2

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_atlas = AtlasTexture.new()
	_atlas.atlas = atlas_texture
	var cell := Vector2(atlas_texture.get_size()) / Vector2(atlas_grid)
	_atlas.region = Rect2(Vector2(column, row) * cell, cell)
	# Include the gold contact marker as well as the visible figure.
	hit_rect = Rect2(Vector2(-dimensions.x * 0.42, -dimensions.y - 12), Vector2(dimensions.x * 0.84, dimensions.y + 10))
	queue_redraw()

func _draw() -> void:
	if _atlas == null: return
	if row != 3:
		draw_set_transform(Vector2(0, -1), 0, Vector2(1, 0.25))
		draw_circle(Vector2.ZERO, dimensions.x * 0.28, Color(0.02, 0.015, 0.01, 0.28))
		draw_set_transform(Vector2.ZERO)
	draw_texture_rect(_atlas, Rect2(Vector2(-dimensions.x * 0.5, -dimensions.y), dimensions), false)
	if not contact_id.is_empty():
		var at := Vector2(0, -dimensions.y - 6)
		draw_circle(at, 5, Color("33271a"))
		draw_circle(at, 4, Color("e8bc73"), false, 1)
		draw_line(at + Vector2(0, -2), at + Vector2(0, 1), Color("ffe2aa"), 1.5)
		draw_circle(at + Vector2(0, 2.5), 0.8, Color("ffe2aa"))

	elif not talk_id.is_empty():
		var at := Vector2(0, -dimensions.y - 6)
		draw_style_box(_speech_box(), Rect2(at - Vector2(6, 4), Vector2(12, 8)))
		draw_line(at + Vector2(-3, 4), at + Vector2(-4, 7), Color("8ed4d7"), 1)
		for x in [-3, 0, 3]: draw_circle(at + Vector2(x, 0), 0.8, Color("8ed4d7"))

func _speech_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("122d38")
	box.border_color = Color("8ed4d7")
	box.set_border_width_all(1)
	return box
