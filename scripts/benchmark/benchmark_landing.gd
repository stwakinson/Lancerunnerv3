class_name BenchmarkLanding
extends Node2D

const Art = preload("res://scripts/benchmark/landing_art_layer.gd")
const Ambience = preload("res://scripts/benchmark/landing_ambience.gd")
const MAX_PAN := Vector2(48, 9)
const DEPTHS := [0.10, 0.23, 0.35, 0.65, 0.65, 1.05]

var layers: Array[Node2D] = []
var elapsed := 0.0
var weather_enabled := true
var parallax_enabled := true
var cinematic_motion := true
var camera_position := Vector2.ZERO
var manual_pan := 0.0
var _rain: BenchmarkLandingAmbience
var _lit_material: ShaderMaterial


func _ready() -> void:
	_add_art("DistantFortress", preload("res://assets/benchmark/landing/distant_fortress.png"), Rect2(-64, -36, 768, 432))
	_add_ambience("AirTraffic", Ambience.Pass.TRAFFIC)
	_add_ambience("ValleyMist", Ambience.Pass.MIST)
	var market := _add_art("MarketAndLandingPad", preload("res://assets/benchmark/landing/market_pad.png"), Rect2(-64, -92, 768, 432))
	market.extend_ground = true
	_lit_material = ShaderMaterial.new()
	_lit_material.shader = preload("res://shaders/benchmark/landing_lights.gdshader")
	market.material = _lit_material
	_add_ambience("StreetLife", Ambience.Pass.STREET)
	_add_art("ForegroundProps", preload("res://assets/benchmark/landing/foreground_props.png"), Rect2(-64, -70, 768, 432))
	_rain = Ambience.new()
	_rain.name = "NearWeather"
	_rain.kind = Ambience.Pass.RAIN
	add_child(_rain)


func _add_art(node_name: String, texture: Texture2D, frame: Rect2) -> BenchmarkLandingArtLayer:
	var layer := Art.new()
	layer.name = node_name
	layer.texture = texture
	layer.frame = frame
	add_child(layer)
	layers.append(layer)
	return layer


func _add_ambience(node_name: String, kind: BenchmarkLandingAmbience.Pass) -> void:
	var layer := Ambience.new()
	layer.name = node_name
	layer.kind = kind
	add_child(layer)
	layers.append(layer)


func advance(delta: float, pointer: Vector2, pan_input := 0.0) -> void:
	elapsed += delta
	manual_pan = clampf(manual_pan + pan_input * delta * 24, -24, 24)
	var drift := Vector2(sin(elapsed * 0.17) * 5, sin(elapsed * 0.13) * 1.2) if cinematic_motion else Vector2.ZERO
	var target := pointer.clamp(-Vector2.ONE, Vector2.ONE) * Vector2(18, 5) + Vector2(manual_pan, 0) + drift
	target = target.clamp(-MAX_PAN, MAX_PAN)
	if not parallax_enabled:
		camera_position = Vector2.ZERO
	else:
		camera_position = camera_position.lerp(target, 1.0 - exp(-delta * 4.5))
	for i in layers.size():
		# Pixel snapping preserves a stable output grid. Market and street actors
		# share a factor so feet remain attached to the pavement.
		layers[i].position = (-camera_position * DEPTHS[i]).round()
		if layers[i] is BenchmarkLandingAmbience:
			layers[i].advance(elapsed, weather_enabled)
	_lit_material.set_shader_parameter("clock", elapsed)
	_rain.advance(elapsed, weather_enabled)


func reset_camera() -> void:
	manual_pan = 0.0
	camera_position = Vector2.ZERO
	for layer in layers:
		layer.position = Vector2.ZERO
