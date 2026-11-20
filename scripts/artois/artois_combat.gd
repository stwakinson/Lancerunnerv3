class_name ArtoisCombat
extends Node3D
## Artois-only equipment, projectile sweeps and encounter combat.
signal enemy_destroyed(id: String)
signal player_destroyed

const Fighter = preload("res://scripts/benchmark/voxel_ship.gd")
const WEAPONS := {
	"pulse_laser": {"damage": 24.0, "interval": 0.24, "speed": 360.0, "colour": "8ae5ed", "life": 2.2},
	"autocannon": {"damage": 10.0, "interval": 0.085, "speed": 460.0, "colour": "ffce7c", "life": 1.5},
	"missile_rack": {"damage": 65.0, "interval": 1.2, "speed": 140.0, "colour": "ff926c", "life": 5.0},
}
const HULL_MAX := 120.0
const AGGRO_RANGE := 420.0
var world: Node3D
var weapons: Array = ["pulse_laser", ""]
var hull := HULL_MAX
var shield := 60.0
var shield_max := 60.0
var shield_regen := 8.0
var dead := false
var enemies: Array[Node3D] = []
var hostile_shots: Array[MeshInstance3D] = []
var _cooldowns := [0.0, 0.0]
var _since_hit := 10.0
var _shield_flash := 0.0
var _bubble: MeshInstance3D
var _mounts: Node3D
var _bursts: Array[MeshInstance3D] = []


func configure(space: Node3D, market: LandingMarketState) -> void:
	world = space
	weapons = market.weapons.duplicate()
	shield_max = 180.0 if market.utility == "shield" else 60.0
	shield_regen = 22.0 if market.utility == "shield" else 8.0
	if _mounts != null: _mounts.free()
	_mounts = Node3D.new()
	_mounts.name = "FittedHardpoints"
	world.ship.add_child(_mounts)
	for i in 2:
		if not WEAPONS.has(weapons[i]): continue
		var gun := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.28, 0.32, 1.8 if weapons[i] != "missile_rack" else 1.0)
		gun.mesh = mesh
		gun.position = Vector3(-1.05 if i == 0 else 1.05, 0.12, -2.1)
		gun.material_override = world._material(WEAPONS[weapons[i]].colour, false)
		_mounts.add_child(gun)
	if _bubble == null:
		_bubble = MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 3.4
		mesh.height = 6.8
		_bubble.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 0.75, 1, 0.18)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bubble.material_override = mat
		world.ship.add_child(_bubble)
	repair()


func repair() -> void:
	hull = HULL_MAX
	shield = shield_max
	dead = false
	_since_hit = 10.0
	_cooldowns = [0.0, 0.0]
	_shield_flash = 0.0
	if _bubble != null: _bubble.visible = false


func fire() -> void:
	if dead or world.cruise or (world.highways != null and world.highways.attached()): return
	for slot in 2:
		var id: String = weapons[slot]
		if not WEAPONS.has(id) or _cooldowns[slot] > 0: continue
		var stats: Dictionary = WEAPONS[id]
		_cooldowns[slot] = stats.interval
		var at: Vector3 = world.ship.global_transform * Vector3(-1.05 if slot == 0 else 1.05, 0.12, -3.0)
		var direction: Vector3 = -world.ship.basis.z
		var target := enemy(world.selected_id)
		# Small cone assist only for a selected hostile in front of the ship.
		if target != null:
			var lead: Vector3 = target.global_position + (target.get_meta("velocity") as Vector3) * at.distance_to(target.global_position) / float(stats.speed)
			var aim := at.direction_to(lead)
			if direction.dot(aim) > cos(deg_to_rad(7.0)): direction = aim
		var shot := _projectile(at, direction * float(stats.speed) + world.velocity, float(stats.damage), str(stats.colour), float(stats.life))
		shot.set_meta("weapon", id)
		shot.set_meta("target", world.selected_id if target != null else "")
		world.shots.append(shot)


func _projectile(at: Vector3, velocity: Vector3, damage: float, colour: String, life: float) -> MeshInstance3D:
	var shot := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.16, 2.0)
	shot.mesh = box
	shot.material_override = world._material(colour, true)
	add_child(shot)
	shot.global_position = at
	if velocity.length_squared() > 0: shot.look_at(at + velocity.normalized(), Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
	shot.set_meta("velocity", velocity)
	shot.set_meta("damage", damage)
	shot.set_meta("remaining", life)
	return shot


func spawn_patrol(centre: Vector3) -> void:
	clear_encounter()
	for i in 5:
		var fighter := Fighter.new()
		fighter.name = "PatrolEnemy%d" % (i + 1)
		add_child(fighter)
		fighter.global_position = centre + Vector3((i - 2) * 38.0, (i % 2) * 22.0, -65.0 - absf(i - 2) * 15.0)
		fighter.scale = Vector3.ONE * 1.6
		# Visible red identification fins distinguish this hostile patrol.
		fighter._box(Vector3(0, 0.8, 0.4), Vector3(1.8, 0.35, 1.5), "f65c45", true)
		fighter.set_meta("id", "patrol_%d" % (i + 1))
		fighter.set_meta("hull", 65.0)
		fighter.set_meta("shield", 20.0)
		fighter.set_meta("active", false)
		fighter.set_meta("cooldown", 0.8 + i * 0.35)
		fighter.set_meta("velocity", Vector3.ZERO)
		enemies.append(fighter)


func enemy(id: String) -> Node3D:
	for fighter in enemies:
		if fighter.get_meta("id") == id: return fighter
	return null


func clear_encounter() -> void:
	for fighter in enemies: fighter.queue_free()
	enemies.clear()
	clear_projectiles()


func clear_projectiles() -> void:
	for shot in world.shots: shot.queue_free()
	world.shots.clear()
	for shot in hostile_shots: shot.queue_free()
	hostile_shots.clear()


func advance(delta: float) -> void:
	for i in 2: _cooldowns[i] = maxf(0.0, float(_cooldowns[i]) - delta)
	_since_hit += delta
	if not dead and _since_hit > 4.0: shield = minf(shield_max, shield + shield_regen * delta)
	_shield_flash = maxf(0.0, _shield_flash - delta)
	if _bubble != null: _bubble.visible = _shield_flash > 0
	for fighter in enemies:
		var to_player: Vector3 = world.ship.position - fighter.position
		var distance := to_player.length()
		if distance < AGGRO_RANGE: fighter.set_meta("active", true)
		if dead or not fighter.get_meta("active"): continue
		# Stop pursuit if the player pulls far ahead of this fighter.
		if distance > 850:
			fighter.set_meta("active", false)
			fighter.set_meta("velocity", Vector3.ZERO)
			continue
		if distance > 0.1:
			var direction := to_player / distance
			var desired := direction * (26.0 if distance > 130 else (-18.0 if distance < 75 else 0.0))
			var previous: Vector3 = fighter.get_meta("velocity")
			var velocity := previous.move_toward(desired, delta * 32.0)
			fighter.position += velocity * delta
			fighter.set_meta("velocity", velocity)
			var up := Vector3.RIGHT if absf(direction.y) > 0.98 else Vector3.UP
			fighter.basis = Basis(fighter.basis.orthonormalized().get_rotation_quaternion().slerp(Basis.looking_at(direction, up).get_rotation_quaternion(), 1.0 - exp(-delta * 2.5))).scaled(Vector3.ONE * 1.6)
		var wait := float(fighter.get_meta("cooldown")) - delta
		if wait <= 0 and distance < 350:
			var aim: Vector3 = world.ship.position + world.velocity * minf(distance / 150.0, 0.6)
			var shot := _projectile(fighter.position - fighter.basis.z * 5, fighter.position.direction_to(aim) * 150.0, 5.0, "ff7059", 3.0)
			hostile_shots.append(shot)
			wait = 2.4
		fighter.set_meta("cooldown", wait)
	_advance_shots(world.shots, delta, true)
	_advance_shots(hostile_shots, delta, false)
	for i in range(_bursts.size() - 1, -1, -1):
		var burst := _bursts[i]
		var remaining := float(burst.get_meta("remaining")) - delta
		burst.set_meta("remaining", remaining)
		burst.scale += Vector3.ONE * delta * 12
		if remaining <= 0:
			burst.queue_free()
			_bursts.remove_at(i)


func _advance_shots(list: Array, delta: float, friendly: bool) -> void:
	for i in range(list.size() - 1, -1, -1):
		var shot: MeshInstance3D = list[i]
		var velocity: Vector3 = shot.get_meta("velocity")
		if friendly and shot.get_meta("weapon", "") == "missile_rack":
			var target := enemy(str(shot.get_meta("target", "")))
			if target != null:
				velocity = velocity.move_toward(shot.position.direction_to(target.position) * 140.0, delta * 180.0)
				shot.set_meta("velocity", velocity)
		var next := shot.position + velocity * delta
		var hit := false
		# Sweep the segment, so fast rounds cannot tunnel through small ships.
		if friendly:
			var victim: Node3D
			var nearest := INF
			for fighter in enemies:
				var distance := _segment_hit(shot.position, next, fighter.position, 5.5)
				if distance >= 0 and distance < nearest:
					nearest = distance
					victim = fighter
			if victim != null:
				damage_enemy(str(victim.get_meta("id")), float(shot.get_meta("damage")))
				hit = true
		elif not dead and _segment_hit(shot.position, next, world.ship.position, 3.2) >= 0:
			damage_player(float(shot.get_meta("damage")))
			hit = true
		shot.position = next
		var remaining := float(shot.get_meta("remaining")) - delta
		shot.set_meta("remaining", remaining)
		if hit or remaining <= 0:
			shot.queue_free()
			list.remove_at(i)


static func _segment_hit(from: Vector3, to: Vector3, centre: Vector3, radius: float) -> float:
	var delta := to - from
	var length := delta.length()
	if length < 0.00001: return 0.0 if from.distance_to(centre) <= radius else -1.0
	var direction := delta / length
	var offset := from - centre
	if offset.length_squared() <= radius * radius: return 0.0
	var b := offset.dot(direction)
	var disc := b * b - offset.length_squared() + radius * radius
	if disc < 0: return -1.0
	var distance := -b - sqrt(disc)
	return distance if distance >= 0 and distance <= length else -1.0


func damage_player(amount: float) -> void:
	if dead or amount <= 0: return
	_since_hit = 0
	var absorbed := minf(shield, amount)
	shield -= absorbed
	hull = maxf(0.0, hull - (amount - absorbed))
	if absorbed > 0: _shield_flash = 0.25
	if hull <= 0:
		dead = true
		player_destroyed.emit()


func damage_enemy(id: String, amount: float) -> void:
	var fighter := enemy(id)
	if fighter == null or amount <= 0: return
	var absorbed := minf(float(fighter.get_meta("shield")), amount)
	fighter.set_meta("shield", float(fighter.get_meta("shield")) - absorbed)
	var health := maxf(0.0, float(fighter.get_meta("hull")) - (amount - absorbed))
	fighter.set_meta("hull", health)
	if health > 0: return
	var burst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	burst.mesh = mesh
	burst.material_override = world._material("ffc07c", true)
	add_child(burst)
	burst.position = fighter.position
	burst.set_meta("remaining", 0.3)
	_bursts.append(burst)
	enemies.erase(fighter)
	fighter.queue_free()
	if world.selected_id == id: world.select_target("test_patrol")
	enemy_destroyed.emit(id)
