class_name BenchmarkLanding
extends Node2D

const Layer = preload("res://scripts/benchmark/landing_layer.gd")
var layers: Array[Node2D] = []
var elapsed := 0.0
var weather_enabled := true
var _rain: Node2D


func _ready() -> void:
	for depth in 4:
		var layer := Layer.new()
		layer.depth = depth
		layer.name = ["StormSky", "Fortress", "TownAndLandingPad", "MarketForeground"][depth]
		add_child(layer)
		layers.append(layer)
	_rain = Node2D.new()
	_rain.name = "Weather"
	_rain.draw.connect(_draw_rain)
	add_child(_rain)


func advance(delta: float, pointer: Vector2) -> void:
	elapsed += delta
	for i in layers.size():
		# Limited camera travel prevents gaps between layered illustrations.
		layers[i].position = Vector2(roundf(pointer.x * i * -2.5), roundf(pointer.y * i * -1.1))
	_rain.queue_redraw()


func _draw_rain() -> void:
	if not weather_enabled:
		return
	for i in 170:
		var x := fposmod(i * 79.7 - elapsed * 42, 660) - 10
		var y := fposmod(i * 43.3 + elapsed * 170, 380) - 10
		_rain.draw_line(Vector2(floorf(x), floorf(y)), Vector2(floorf(x - 2), floorf(y + 6)), Color(0.57, 0.76, 0.8, 0.18), 1)
	for i in 12:
		var x := fposmod(i * 67.7 + elapsed * 2, 640)
		_rain.draw_circle(Vector2(x, 247 + sin(i * 2.0 + elapsed) * 6), 25, Color(0.58, 0.74, 0.73, 0.018))
