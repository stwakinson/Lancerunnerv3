class_name DustPuff
extends Node3D

# A soft ring of dust kicked up when the ship touches down or lifts off.

const LIFETIME := 1.8


static func spawn(at: Vector3, up: Vector3) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return

	var puff := DustPuff.new()
	puff.name = "DustPuff"
	puff.transform = Transform3D(Basis(Rotations.look_rotation(up, Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP)), at)

	var ps := FxParticles.new()
	ps.burst = 40
	ps.max_particles = 40
	ps.lifetime = Vector2(0.8, LIFETIME)
	ps.speed = Vector2(1.5, 4.0)
	ps.size = Vector2(0.6, 1.6)
	ps.additive = false
	ps.start_color_a = Color(0.62, 0.56, 0.48)
	ps.start_color_b = Color(0.45, 0.4, 0.34)
	# A flat, wide cone pointing up: dust spreads out along the ground.
	ps.shape = FxParticles.Shape.CONE
	ps.cone_angle = 80.0
	ps.shape_radius = 1.0
	ps.drag = 1.8
	ps.color_keys = [[0.0, Color.WHITE], [1.0, Color.WHITE]]
	ps.alpha_keys = [[0.0, 0.0], [0.15, 0.5], [1.0, 0.0]]
	ps.size_end = 1.8
	puff.add_child(ps)
	tree.current_scene.add_child(puff)


var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME + 0.1:
		queue_free()
