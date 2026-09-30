extends Node
var t := 0.0
var step := 0
func _ready() -> void:
	if has_meta("child"): return
	var w := Node.new(); w.set_script(get_script()); w.set_meta("child", true)
	w.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(w)
	get_tree().change_scene_to_file.call_deferred("res://scenes/menu.tscn")
func rect(text: String) -> Rect2:
	for b in get_tree().root.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree(): return b.get_global_rect()
	return Rect2()
func _process(d: float) -> void:
	if not has_meta("child"): return
	t += d
	var scene := get_tree().current_scene
	if scene == null or scene.name != "Menu" or t < 1.0: return
	if step == 0:
		scene._show_picker(true); step = 1; set_meta("m", t)
	elif t > float(get_meta("m")) + 0.5:
		var panels := get_tree().root.find_children("*", "PanelContainer", true, false)
		var box_bottom := 0.0
		for p in panels: print(p.get_global_rect()); box_bottom = maxf(box_bottom, (p as Control).get_global_rect().end.y)
		var back := rect("BACK")
		print("window %s | boxes end at y=%.0f, BACK starts at y=%.0f (gap %.0f) | play buttons at y=%.0f and %.0f" % [get_viewport().get_visible_rect().size, box_bottom, back.position.y, back.position.y - box_bottom, rect("PLAY INFINITE").position.y, rect("PLAY CLASSIC").position.y])
		get_viewport().get_texture().get_image().save_png("/private/tmp/claude-501/-Users-aryav-Godot-projects-ship-wars/cf407410-adbb-457a-a572-83683308fee1/scratchpad/picker_%s.png" % OS.get_environment("RES"))
		get_tree().quit()
