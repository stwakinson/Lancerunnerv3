extends BenchmarkLanding
const Layer = preload("res://scripts/artois/artois_station_layer.gd")
const Markets = preload("res://scripts/artois/artois_markets.gd")
@export var station_id := "embry"
var profile := {}


func _ready() -> void:
	profile = Markets.new().profile(station_id)
	weather_enabled = true
	for i in 6:
		var layer := Layer.new()
		layer.name = ["WindowView", "HallStructure", "TrafficAndVapour", "MarketDeck", "Dockworkers", "Foreground"][i]
		layer.kind = i
		layer.profile = profile
		add_child(layer)
		layers.append(layer)


func advance(delta: float, pointer: Vector2, pan_input := 0.0, camera_frozen := false) -> void:
	elapsed += delta
	if not camera_frozen:
		manual_pan = clampf(manual_pan + pan_input * delta * 24, -24, 24)
		var drift := Vector2(sin(elapsed * 0.17) * 5, sin(elapsed * 0.13) * 1.2) if cinematic_motion else Vector2.ZERO
		var target := (pointer * Vector2(18, 5) + Vector2(manual_pan, 0) + drift).clamp(-MAX_PAN, MAX_PAN)
		camera_position = camera_position.lerp(target, 1.0 - exp(-delta * 4)) if parallax_enabled else Vector2.ZERO
	for i in layers.size():
		layers[i].position = (-camera_position * DEPTHS[i]).round()
		layers[i].clock = elapsed
		layers[i].mist_enabled = weather_enabled
		layers[i].queue_redraw()
