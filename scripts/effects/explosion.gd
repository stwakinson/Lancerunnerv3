class_name Explosion
extends Node3D

# Self-contained burst of sparks plus a short light flash. Built entirely in
# code so no scene is needed; frees itself once the particles are gone.

const MAX_PARTICLE_LIFETIME := 0.9
const FLASH_DURATION := 0.25

var flash: OmniLight3D
var flash_intensity := 4.0
var age := 0.0


static func spawn(at: Vector3, color: Color, size: float = 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return

	var explosion := Explosion.new()
	explosion.name = "Explosion"
	explosion.position = at

	var ps := FxParticles.new()
	ps.rate = 0.0
	ps.burst = 60
	ps.max_particles = 128
	ps.lifetime = Vector2(0.35, MAX_PARTICLE_LIFETIME)
	ps.speed = Vector2(2.0 * size, 8.0 * size)
	ps.size = Vector2(0.15 * size, 0.55 * size)
	ps.start_color_a = Color.WHITE
	ps.start_color_b = color
	ps.shape = FxParticles.Shape.SPHERE
	ps.shape_radius = 0.2 * size
	ps.drag = 2.5
	ps.color_keys = [[0.0, Color.WHITE], [0.3, color], [1.0, color]]
	ps.alpha_keys = [[0.0, 1.0], [0.5, 0.8], [1.0, 0.0]]
	ps.size_end = 0.0
	explosion.add_child(ps)

	explosion.flash = OmniLight3D.new()
	explosion.flash.light_color = color
	explosion.flash.omni_range = 6.0 * size
	explosion.flash.light_energy = explosion.flash_intensity
	explosion.flash.shadow_enabled = false
	explosion.add_child(explosion.flash)

	tree.current_scene.add_child(explosion)


func _process(delta: float) -> void:
	age += delta
	if flash != null:
		flash.light_energy = flash_intensity * clampf(1.0 - age / FLASH_DURATION, 0.0, 1.0)
	if age > MAX_PARTICLE_LIFETIME + 0.1:
		queue_free()
