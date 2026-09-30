extends CanvasLayer

# Autoloaded as SceneFader. Fades to black, swaps scenes, then fades back in,
# so moving between the menu and the game never cuts hard. Runs while the tree
# is paused (the pause menu calls it) and unpauses before the new scene starts.

@export var fade_in_time := 0.6

var busy := false

var _black: ColorRect


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The game opens from black too.
	_fade_in()


func change_scene(path: String, fade_out_time := 0.45) -> void:
	if busy:
		return
	busy = true
	_black.mouse_filter = Control.MOUSE_FILTER_STOP  # no clicks mid-transition
	var t := create_tween()
	t.tween_property(_black, "modulate:a", 1.0, fade_out_time)
	await t.finished
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await _fade_in()


# Same fade, but to a scene that's already built (the loading screen hands
# over the warmed-up game this way). `node` must be out of the tree.
func change_scene_to_node(node: Node, fade_out_time := 0.45) -> void:
	if busy:
		return
	busy = true
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(_black, "modulate:a", 1.0, fade_out_time)
	await t.finished
	get_tree().paused = false
	get_tree().change_scene_to_node(node)
	await _fade_in()


func _fade_in() -> void:
	busy = true
	_black.modulate.a = 1.0
	# Let the new scene load and draw a couple of frames under the black, so
	# any first-frame hitch stays hidden.
	await get_tree().process_frame
	await get_tree().process_frame
	var t := create_tween()
	t.tween_property(_black, "modulate:a", 0.0, fade_in_time).set_ease(Tween.EASE_OUT)
	await t.finished
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false
