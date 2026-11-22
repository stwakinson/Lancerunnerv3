class_name ArtoisFighterBrain
extends RefCounted
## A readable, finite combat loop. Decisions use delayed observations, not input state.
const Defence = preload("res://scripts/artois/artois_ship_defence.gd")
const TURN_RATE := deg_to_rad(70.0)
const REACTION := 0.35
var world: Node3D
var pilot: Node3D
var defence := Defence.new()
var personality := "freebooter"
var slot := 0
var target_key := ""
var state := "APPROACH"
var clock := 0.0
var timer := 0.0
var charge := 0.0
var velocity := Vector3.ZERO
var cruise := false
var shots_fired := 0
var dodges := 0
var _goal := Vector3.ZERO
var _scale := Vector3.ONE
var _sample_wait := 0.0
var _observed := Vector3.ZERO
var _observed_velocity := Vector3.ZERO
var _target_changed := true
var _shot_wait := 0.0
var _burst := 0
var _dodge_wait := 0.0
var _dodge_velocity := Vector3.ZERO
var _reaction := -1.0
var _threat_time := 0.0
var _hit_age := 10.0
var _retreat_wait := 0.0
var _tell: MeshInstance3D

func configure(space: Node3D, ship: Node3D, kind: String, ordinal: int) -> void:
	world = space
	pilot = ship
	personality = kind
	slot = ordinal
	_scale = pilot.scale
	defence.configure(pilot)
	defence.armour = 0 # Keep authored NPC hit points; power/guard use player rules.
	_tell = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.23
	mesh.height = 0.46
	_tell.mesh = mesh
	_tell.position = Vector3(0, 0.35, -3.4)
	_tell.material_override = world._material("ffab62", true)
	pilot.add_child(_tell)
	_tell.visible = false

func committed() -> bool:
	return state in ["WINDUP", "ATTACK RUN"]

func idle(delta: float) -> void:
	defence.advance(delta, false, false)
	defence.update_visual(0)
	_tell.visible = false
	charge = 0
	cruise = false
	state = "APPROACH"
	timer = 0
	_target_changed = true
	_threat_time = 0
	_reaction = -1
	_dodge_velocity = Vector3.ZERO
	_hit_age = 10
	pilot.set_meta("cruise", false)
	pilot.set_meta("cruise_charge", 0.0)

func hit() -> void:
	_hit_age = 0

func block_damage(amount: float, source: Vector3) -> float:
	hit()
	return defence.block(amount, source, pilot)

func advance(delta: float, target: Node3D, target_velocity: Vector3, may_attack: bool, hull_ratio: float, disruption: float) -> Dictionary:
	clock += delta
	timer += delta
	_hit_age += delta
	_retreat_wait = maxf(0, _retreat_wait - delta)
	_shot_wait = maxf(0, _shot_wait - delta)
	_dodge_wait = maxf(0, _dodge_wait - delta)
	_sample_wait -= delta
	if _target_changed or _sample_wait <= 0:
		_observed = target.global_position
		_observed_velocity = target_velocity
		_sample_wait = 0.25 if personality == "valois" else 0.4
		_target_changed = false
	var distance := pilot.global_position.distance_to(_observed)
	var direction := pilot.global_position.direction_to(_observed)
	var side := Vector3.RIGHT if slot % 2 == 0 else Vector3.LEFT
	var stage := _observed - direction * 160 + side * (70 + (slot % 3) * 40) + Vector3.UP * ((slot % 3 - 1) * 18)
	if hull_ratio < (0.18 if personality == "valois" else 0.25) and _retreat_wait == 0 and state != "RETREAT":
		_enter("RETREAT")
		_retreat_wait = 12
		_goal = pilot.global_position - direction * 350 + side * 100
	match state:
		"APPROACH", "FLANK":
			_goal = stage
			if distance < 270 and timer > 0.6 and may_attack:
				_enter("WINDUP")
			elif not may_attack: state = "FLANK"
		"WINDUP":
			_goal = pilot.global_position
			if timer >= (0.75 if personality == "valois" else 0.95):
				_enter("ATTACK RUN")
				_goal = _observed + direction * 140
				_burst = 2
		"ATTACK RUN":
			if timer > (2.0 if personality == "valois" else 1.8) or distance < 55:
				_enter("BREAK AWAY")
				_goal = pilot.global_position - pilot.global_basis.z.normalized() * 170 + side * 100
		"BREAK AWAY":
			if timer > 1.5: _enter("RECOVER")
		"RECOVER":
			_goal = stage
			if timer > 1.6: _enter("APPROACH")
		"RETREAT":
			if timer > 3.0: _enter("RECOVER")
	var incoming := _incoming()
	_threat_time = _threat_time + delta if incoming else 0.0
	if incoming and _reaction < 0 and _dodge_wait == 0: _reaction = REACTION + (slot % 4) * 0.04
	if _reaction >= 0:
		_reaction -= delta
		if _reaction <= 0:
			if incoming and state != "ATTACK RUN" and disruption <= 0 and _dodge_wait == 0:
				_dodge_velocity = pilot.global_basis.x.normalized() * (135.0 if slot % 2 == 0 else -135.0)
				_dodge_wait = 3.2
				dodges += 1
				charge = 0
				cruise = false
			_reaction = -1
	if disruption > 0:
		charge = 0
		cruise = false
		_dodge_velocity = Vector3.ZERO
	elif state in ["APPROACH", "FLANK", "RETREAT"] and distance > 330 and _dodge_wait < 2.8:
		charge += delta
		cruise = charge >= world.CRUISE_SPOOL_TIME
	elif distance < 230 or state not in ["APPROACH", "FLANK", "RETREAT"]:
		charge = 0
		cruise = false
	var look := _observed - pilot.global_position if state in ["WINDUP", "RECOVER", "FLANK"] else _goal - pilot.global_position
	if charge > 0: look = direction
	_turn(look, delta, cruise)
	defence.guard_direction = -pilot.global_basis.z.normalized()
	var threatened := _threat_time >= REACTION or (_hit_age >= REACTION and _hit_age < 2)
	defence.advance(delta, state in ["RECOVER", "FLANK"] and threatened and charge == 0 and not cruise, false)
	var boost_aligned := (-pilot.global_basis.z.normalized()).angle_to(pilot.global_position.direction_to(_goal)) < PI / 6
	var boosting := defence.afterburner(delta, boost_aligned and state in ["BREAK AWAY", "RETREAT"] and charge == 0 and disruption <= 0 and not defence.guard_active and defence.energy > 20)
	velocity = pilot.get_meta("velocity", Vector3.ZERO)
	var top := 175.0 if cruise else (105.0 if boosting else 35.0)
	var forward := -pilot.global_basis.z.normalized()
	var desired := forward * top
	if state == "WINDUP": desired = Vector3.ZERO
	elif state in ["RECOVER", "FLANK"] and charge == 0: desired = pilot.global_position.direction_to(_goal) * 25.0
	if disruption > 0: desired = desired.limit_length(12)
	velocity = velocity.move_toward(desired, delta * (110.0 if cruise else 85.0))
	if disruption > 0: velocity = velocity.limit_length(12)
	pilot.global_position += velocity * delta + _dodge_velocity * ((1 - exp(-6 * delta)) / 6.0)
	_dodge_velocity *= exp(-6 * delta)
	pilot.set_meta("velocity", velocity)
	pilot.set_meta("cruise", cruise)
	pilot.set_meta("cruise_charge", charge)
	pilot.set_meta("tactic", state)
	defence.update_visual(maxf(0, (world.CRUISE_SPOOL_TIME - charge) / world.CRUISE_SPOOL_TIME) if charge > 0 and not cruise else 0)
	_tell.visible = state == "WINDUP"
	_tell.scale = Vector3.ONE * (1 + 0.3 * sin(clock * 16))
	var aim := _observed + _observed_velocity * minf(distance / 125.0, 0.6) * 0.65
	var error := 1.3 if personality == "valois" else 3.0
	aim += Vector3(sin(clock * 2.1 + slot), cos(clock * 1.7 + slot), 0) * error
	var shot_direction := pilot.global_position.direction_to(aim)
	var fire := state == "ATTACK RUN" and _burst > 0 and _shot_wait == 0 and distance < 330 and charge == 0 and not cruise
	fire = fire and forward.angle_to(shot_direction) <= PI / 6 and _clear_line(aim)
	if fire and defence.spend(12):
		_burst -= 1
		_shot_wait = 0.48 if personality == "valois" else 0.65
		shots_fired += 1
	else: fire = false
	return {"fire": fire, "direction": shot_direction}

func _enter(next: String) -> void:
	state = next
	timer = 0

func _turn(direction: Vector3, delta: float, cruising: bool) -> void:
	if direction.length_squared() < 0.001: return
	var up := Vector3.RIGHT if absf(direction.normalized().y) > 0.98 else Vector3.UP
	var current := pilot.basis.orthonormalized().get_rotation_quaternion()
	var target := Basis.looking_at(direction, up).get_rotation_quaternion()
	var angle := current.angle_to(target)
	var fraction := minf(1, TURN_RATE * (0.18 if cruising else 1.0) * delta / maxf(angle, 0.00001))
	pilot.basis = Basis(current.slerp(target, fraction)).scaled(_scale)

func _incoming() -> bool:
	for shot in world.shots:
		if not is_instance_valid(shot): continue
		var offset: Vector3 = shot.global_position - pilot.global_position
		if offset.length() > 130 or offset.normalized().dot(-pilot.global_basis.z.normalized()) < -0.2: continue
		var relative: Vector3 = shot.get_meta("velocity") - velocity
		var speed := relative.length_squared()
		if speed < 0.01: continue
		var time := -offset.dot(relative) / speed
		if time > 0.1 and time < 1.1 and (offset + relative * time).length() < 7: return true
	return false

func _clear_line(aim: Vector3) -> bool:
	var planet: Vector3 = world.layout.world(world.layout.planet)
	var segment := aim - pilot.global_position
	var t := clampf((planet - pilot.global_position).dot(segment) / maxf(segment.length_squared(), 0.001), 0, 1)
	if (pilot.global_position + segment * t).distance_to(planet) < float(world.layout.planet.radius): return false
	# Hold fire if another local/fighter is directly between muzzle and aim.
	var allies: Array = world.combat.enemies.duplicate()
	if world.traffic != null:
		for actor in world.traffic.actors.values():
			if actor.alive and actor.hostile: allies.append(actor.node)
	for ally in allies:
		if ally == pilot or str(ally.get_meta("id", "")) == target_key: continue
		var along: float = clampf((ally.global_position - pilot.global_position).dot(segment) / maxf(segment.length_squared(), 0.001), 0, 1)
		if along > 0 and along < 0.95 and (pilot.global_position + segment * along).distance_to(ally.global_position) < 9: return false
	return true
