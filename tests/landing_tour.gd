extends SceneTree

# Deterministic rendered tour. Optional Godot Movie Maker recording:
# godot --path . --fixed-fps 30 --write-movie /path/tour.avi --script res://tests/landing_tour.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Control = load("res://scenes/benchmark/artois_visual.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	# Drive the same landing API as live input, with a repeatable camera path.
	scene.set_process(false)
	while root.get_node("SceneFader").busy:
		await process_frame
	await scene.toggle_docking()
	var rate := 30.0
	for i in 180:
		var time := i / rate
		var pointer := Vector2(sin(time * TAU / 6.0), sin(time * TAU / 6.0) * 0.3)
		scene.landing_world.advance(1.0 / rate, pointer)
		await process_frame
	print("PASS: landing tour rendered")
	quit()
