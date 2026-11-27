class_name ArtoisTraffic
extends Node3D
## A bounded, session-stable local population. No distance LOD or respawn director.
const Holds = preload("res://scripts/artois/artois_ship_holds.gd")
const FighterBrain = preload("res://scripts/artois/artois_fighter_brain.gd")
const Models = preload("res://scripts/artois/artois_local_models.gd")
const Routes = preload("res://scripts/artois/artois_traffic_routes.gd")
var world: Node3D
var actors := {}
var profiles := {}
var routes := Routes.new()
var models := Models.new()
var shots: Array[MeshInstance3D] = []
var radio_history: Array[Dictionary] = []
var radio_line := ""
var elapsed := 0.0
var _radio_until := 0.0
var _radio_ready := 0.0
var _cargo_random := RandomNumberGenerator.new()
var _random := RandomNumberGenerator.new()
var population_limit := 30
var player_present := true


func configure(space: Node3D) -> void:
	world = space
	routes.configure(world)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/artois_population.json"))
	_random.seed = int(data.seed)
	_cargo_random.seed = int(data.seed) + 72
	population_limit = int(data.limit)
	var port_counts := {}
	for profile in data.factions:
		profiles[profile.id] = profile
		for i in int(profile.count):
			if actors.size() >= population_limit: break
			_spawn(profile, i, port_counts)


func _spawn(profile: Dictionary, index: int, port_counts: Dictionary) -> void:
	var id := "local_%s_%02d" % [profile.id, index + 1]
	var home: String = profile.ports[index % profile.ports.size()]
	var armed_role: bool = profile.role in ["pirate", "raider", "guard"]
	var role: String = "salvager" if profile.id == "borderlander" and index >= 5 else profile.role
	var pilot: String = str(profile.first[index % profile.first.size()]) + " " + str(profile.last[(index * 3 + 1) % profile.last.size()])
	var spawn_position := routes.harbour(home)
	var count := int(port_counts.get(home, 0))
	port_counts[home] = count + 1
	spawn_position += Vector3([0.0, -70.0, 70.0][count % 3], (count % 2) * 12, -40.0 - floorf(count / 3.0) * 55.0)
	var node := models.make(profile.model)
	node.name = id
	add_child(node)
	node.position = spawn_position
	node.set_meta("id", id)
	node.set_meta("local", true)
	var actor := {"id": id, "pilot": pilot.strip_edges(), "name": profile.ships[index], "faction": profile.id,
		"allegiance": str(profile.get("allegiance", profile.id)),
		"hold": {}, "ship_class": "salvager" if role == "salvager" else profile.ship_class, "cargo_capacity": Holds.capacity("salvager" if role == "salvager" else str(profile.ship_class)),
		"role": role, "hostile": armed_role, "node": node, "home": home, "origin": home, "destination": home,
		"cargo": "Empty recovery hold" if role == "salvager" else profile.cargo[index % profile.cargo.size()], "hull": float(profile.hull), "shield": float(profile.shield),
		"radius": float(profile.radius), "alive": true, "velocity": Vector3.ZERO, "state": "DEPARTING", "path": [],
		"join_leg": -1, "cruise_charge": 0.0, "cruise": false, "energy": 100.0, "leg": 0, "timer": 0.0, "decision": float(index) * 0.17, "target": "", "provoked": false,
		"threat": "", "disruption": 0.0, "fire_wait": 0.8 + index * 0.25, "trips": 0, "distance": 0.0,
		"salvage_next": role == "salvager", "patrol_step": index}
	actors[id] = actor
	if armed_role:
		_load_manifest(actor)
		actor.brain = FighterBrain.new()
		actor.brain.configure(world, node, "valois" if role in ["raider", "guard"] else "freebooter", index)
		actor.state = "PROWLING"
		actor.path = [{"position": _patrol_point(actor), "mode": "flight"}]
	else: _next_trip(actor)
	_sync(actor)


func get_actor(id: String) -> Dictionary:
	var actor: Dictionary = actors.get(id, {})
	return actor if not actor.is_empty() and actor.alive else {}


func hostile(id: String) -> Node3D:
	var actor := get_actor(id)
	return actor.node if not actor.is_empty() and actor.hostile else null


func target_entry(id: String) -> Dictionary:
	var actor := get_actor(id)
	if actor.is_empty(): return {}
	var profile: Dictionary = profiles[actor.faction]
	var destination: Dictionary = world.layout.target(actor.destination)
	var destination_name: String = str(destination.get("name", "Local patrol"))
	return {"id": id, "name": actor.name, "kind": "hostile" if world.law.enemy(actor) else "local",
		"faction": profile.name, "pilot": actor.pilot, "role": actor.role, "state": actor.state,
		"notes": "%s / %s / %s → %s / Cargo: %s / Hull %d / Shield %d" % [profile.name + " / " + world.law.description(actor.allegiance), actor.pilot, actor.state, destination_name, Holds.summary(actor.hold, LandingMarketState.ITEMS) + " / HOLD %d/%d" % [Holds.used(actor.hold), actor.cargo_capacity], roundi(actor.hull), roundi(actor.shield)]}


func nearby_ids(radius := 1800.0) -> Array:
	var result := []
	for id in actors:
		var actor: Dictionary = actors[id]
		if actor.alive and actor.node.visible and actor.node.position.distance_to(world.ship.position) <= radius: result.append(id)
	result.sort_custom(func(a: String, b: String) -> bool: return actors[a].node.position.distance_squared_to(world.ship.position) < actors[b].node.position.distance_squared_to(world.ship.position))
	return result


func _next_trip(actor: Dictionary) -> void:
	var profile: Dictionary = profiles[actor.faction]
	var choices: Array = profile.salvage if actor.role == "salvager" and actor.salvage_next else profile.ports
	var destination: String = choices[_random.randi_range(0, choices.size() - 1)]
	for attempt in choices.size():
		if destination != actor.destination: break
		destination = choices[(choices.find(destination) + 1) % choices.size()]
	if actor.role != "salvager": _load_manifest(actor)
	actor.origin = actor.destination
	actor.destination = destination
	if actor.role == "salvager": actor.salvage_next = not actor.salvage_next
	actor.path = routes.plan(actor.node.position, routes.harbour(destination))
	actor.leg = 0
	actor.state = "DEPARTING"
	actor.node.visible = true
	actor.timer = 0
	_radio(actor, "Clearing harbour. Bound for %s." % world.layout.target(destination).name)


func _patrol_point(actor: Dictionary) -> Vector3:
	var angle := float(actor.patrol_step) * 2.1
	return routes.harbour(actor.home) + Vector3(cos(angle) * 125, sin(angle * 0.7) * 35, sin(angle) * 125)


func advance(delta: float) -> void:
	var steps := maxi(1, ceili(delta / 0.1))
	for i in steps: _step(delta / steps)
	if elapsed > _radio_until: radio_line = ""


func _step(delta: float) -> void:
	elapsed += delta
	for actor in actors.values():
		if not actor.alive: continue
		if not actor.hostile: actor.energy = minf(100, actor.energy + 18.0 * delta)
		actor.disruption = maxf(0.0, actor.disruption - delta)
		actor.fire_wait = maxf(0.0, actor.fire_wait - delta)
		actor.decision -= delta
		if actor.decision <= 0:
			actor.decision = 0.7 + _random.randf() * 0.4
			if actor.hostile: _choose_prey(actor)
			else: _sense_threat(actor)
		if actor.hostile: _hostile_step(actor, delta)
		else: _civilian_step(actor, delta)
		_sync(actor)
	_advance_shots(delta)


func _choose_prey(actor: Dictionary) -> void:
	if actor.role == "guard":
		_choose_guard_target(actor)
		return
	if actor.provoked and player_present and not world.combat.dead and actor.node.position.distance_to(world.ship.position) < 850:
		actor.target = "player"
		return
	var current: Variant = _target_position(actor.target)
	if not actor.target.is_empty() and current != null and actor.node.position.distance_to(current) < 700: return
	actor.target = ""
	var engaged := 0
	for other in actors.values():
		if other.alive and other.hostile and not other.target.is_empty(): engaged += 1
	if engaged >= 2: return
	var nearest := 430.0
	for prey in actors.values():
		if not prey.alive or prey.hostile or not prey.node.visible: continue
		if actor.role == "raider" and prey.faction not in ["britannian", "hanseatic"]: continue
		var distance: float = actor.node.position.distance_to(prey.node.position)
		if distance < nearest:
			nearest = distance
			actor.target = prey.id
	if actor.target.is_empty() and world.law.enemy(actor) and player_present and not world.combat.dead and actor.node.position.distance_to(world.ship.position) < 300:
		actor.target = "player"
	if not actor.target.is_empty():
		_radio(actor, "Stand to. Surrender your cargo." if actor.role == "pirate" else "Contact identified. Maintain formation.", true)


func _choose_guard_target(actor: Dictionary) -> void:
	actor.target = ""
	var home: Vector3 = routes.harbour(actor.home)
	if actor.node.position.distance_to(home) > 1800: return
	if player_present and not world.combat.dead and world.law.enemy(actor) and world.ship.position.distance_to(home) < 1400 and actor.node.position.distance_to(world.ship.position) < 900:
		actor.target = "player"
		return
	var nearest := 650.0
	for other in actors.values():
		if not other.alive or not other.node.visible or other.role not in ["pirate", "raider"]: continue
		if other.node.position.distance_to(home) > 1400: continue
		var distance: float = actor.node.position.distance_to(other.node.position)
		if distance < nearest:
			nearest = distance
			actor.target = other.id


func _sense_threat(actor: Dictionary) -> void:
	if actor.state in ["DOCKED", "SALVAGING"]: return
	var nearest := 450.0
	var threat := "player" if world.law.enemy(actor) and player_present and actor.node.position.distance_to(world.ship.position) < 700 else ""
	for other in actors.values():
		if not other.alive or not other.hostile or other.target != actor.id: continue
		var distance: float = actor.node.position.distance_to(other.node.position)
		if distance < nearest:
			nearest = distance
			threat = other.id
	if not threat.is_empty():
		if actor.state != "FLEEING": _radio(actor, "Mayday! We are a civilian vessel. Breaking for harbour!", true)
		actor.threat = threat
		if actor.state != "FLEEING":
			actor.cruise_charge = 0.0
			actor.cruise = false
		actor.state = "FLEEING"
		actor.timer = 7.0


func _civilian_step(actor: Dictionary, delta: float) -> void:
	if actor.state in ["DOCKED", "SALVAGING"]:
		actor.timer -= delta
		if actor.timer <= 0: _next_trip(actor)
		return
	if actor.state == "FLEEING":
		actor.timer -= delta
		var threat: Variant = _target_position(actor.threat)
		if threat != null and actor.timer > 0:
			var away: Vector3 = (actor.node.position - threat).normalized()
			actor.cruise_charge = actor.cruise_charge + delta if actor.disruption <= 0 else 0.0
			actor.cruise = actor.cruise_charge >= world.CRUISE_SPOOL_TIME
			_move(actor, actor.node.position + away * 300 + Vector3.UP * 30, world.CRUISE_SPEED if actor.cruise else world.NORMAL_SPEED, delta)
			return
		actor.cruise = false
		actor.cruise_charge = 0.0
		actor.provoked = false
		actor.threat = ""
		actor.path = routes.plan(actor.node.position, routes.harbour(actor.destination))
		actor.leg = 0
	if int(actor.leg) >= actor.path.size():
		actor.velocity = Vector3.ZERO
		actor.trips += 1
		var salvage: bool = actor.role == "salvager" and actor.destination in profiles[actor.faction].salvage
		actor.state = "SALVAGING" if salvage else "DOCKED"
		if salvage:
			actor.hold = {"alloy": _cargo_random.randi_range(8, 20), "argent_ore": _cargo_random.randi_range(2, 7)}
			actor.cargo = "Recovered scrap"
		else:
			actor.hold.clear()
			actor.cargo = "Empty recovery hold" if actor.role == "salvager" else "Delivered"
		actor.node.visible = salvage
		actor.timer = 10.0 + _random.randf() * 10.0
		_radio(actor, "Holding for salvage recovery." if salvage else "Cargo delivered. Requesting a berth.")
		return
	var leg: Dictionary = actor.path[actor.leg]
	actor.state = "FILAMENT TRANSIT" if leg.mode == "filament" else ("SALVAGE RUN" if actor.role == "salvager" else "LOCAL DELIVERY")
	if leg.mode == "filament" and actor.join_leg != actor.leg:
		actor.join_leg = actor.leg
		world.highways.joining.emit_join(actor.node, int(leg.route), float(leg.sign))
	elif leg.mode != "filament": actor.join_leg = -1
	var speed := 350.0 if leg.mode == "filament" else float(profiles[actor.faction].speed)
	if _move(actor, leg.position, speed, delta):
		actor.leg += 1


func _hostile_step(actor: Dictionary, delta: float) -> void:
	var target: Variant = _target_position(actor.target)
	if target != null and not actor.target.is_empty():
		var target_node: Node3D = world.ship if actor.target == "player" else actors[actor.target].node
		var target_velocity: Vector3 = world.velocity if actor.target == "player" else actors[actor.target].velocity
		actor.node.set_meta("velocity", actor.velocity)
		actor.brain.target_key = actor.target
		var action: Dictionary = actor.brain.advance(delta, target_node, target_velocity, world.combat.committed_attackers(actor.target) < 2, actor.hull / float(profiles[actor.faction].hull), actor.disruption)
		actor.velocity = actor.brain.velocity
		actor.energy = actor.brain.defence.energy
		actor.cruise = actor.brain.cruise
		actor.cruise_charge = actor.brain.charge
		actor.state = actor.brain.state
		if action.fire:
			var shot: MeshInstance3D = world.combat._projectile(actor.node.position - actor.node.basis.z.normalized() * 8, action.direction * 110 + actor.velocity, 22.0, "f7a36c" if actor.role == "pirate" else "c5b0ef", 3.5)
			shot.set_meta("source", actor.id)
			shots.append(shot)
		return
	actor.brain.target_key = ""
	actor.brain.idle(delta)
	actor.energy = actor.brain.defence.energy
	actor.cruise = false
	actor.cruise_charge = 0.0
	actor.state = "PROWLING"
	var point := _patrol_point(actor)
	if _move(actor, point, 25.0, delta): actor.patrol_step += 1


func _move(actor: Dictionary, target: Vector3, speed: float, delta: float) -> bool:
	var from: Vector3 = actor.node.position
	var offset := target - from
	if offset.length() < 12:
		actor.node.position = target
		return true
	var filament := speed > 200
	if filament: speed = minf(speed, sqrt(world.highways.EXIT_SPEED * world.highways.EXIT_SPEED + 2.0 * world.highways.ACCELERATION * offset.length()))
	if not filament and speed < 200 and not actor.cruise: speed = minf(speed, world.NORMAL_SPEED)
	if actor.disruption > 0: speed = minf(speed, 12.0)
	var desired := offset.normalized() * speed
	# A small local separation force avoids identical centreline formations.
	if speed < 200:
		for other in actors.values():
			if other.id == actor.id or not other.alive or not other.node.visible: continue
			var away: Vector3 = from - other.node.position
			var clearance: float = actor.radius + other.radius + 12
			if away.length_squared() > 0.1 and away.length() < clearance:
				desired += away.normalized() * 25.0 * (1.0 - away.length() / clearance)
	desired = desired.limit_length(speed)
	var velocity: Vector3 = actor.velocity
	velocity = velocity.move_toward(desired, delta * (110.0 if filament or actor.cruise else 70.0))
	if actor.disruption > 0: velocity = velocity.limit_length(12)
	var next := from + velocity * delta
	if (target - from).dot(target - next) <= 0:
		next = target
	actor.node.position = next
	actor.distance += from.distance_to(next)
	actor.velocity = velocity
	if velocity.length_squared() > 0.1:
		var direction := velocity.normalized()
		var up := Vector3.RIGHT if absf(direction.y) > 0.98 else Vector3.UP
		actor.node.basis = Basis(actor.node.basis.get_rotation_quaternion().slerp(Basis.looking_at(direction, up).get_rotation_quaternion(), 1.0 - exp(-delta * (0.54 if actor.cruise else 3.0))))
	return next.is_equal_approx(target)


func _target_position(id: String) -> Variant:
	if id == "player": return null if world.combat.dead or not player_present else world.ship.position
	var actor := get_actor(id)
	return actor.node.position if not actor.is_empty() and actor.node.visible else null


func _sync(actor: Dictionary) -> void:
	for key in ["hull", "shield", "velocity", "disruption", "cargo_capacity", "ship_class"]: actor.node.set_meta(key, actor[key])
	actor.node.set_meta("cargo_hold", actor.hold)
	actor.node.set_meta("cruise", (actor.cruise or actor.state == "FILAMENT TRANSIT") and actor.disruption <= 0)


func damage(id: String, shield_damage: float, hull_damage: float, source := "player", disruption := 0.0, source_position: Vector3 = Vector3.INF) -> void:
	var actor := get_actor(id)
	if actor.is_empty() or not actor.node.visible or shield_damage <= 0: return
	if source == "player": world.law.record(actor.node, actor.allegiance, not actor.hostile)
	if actor.hostile:
		var attacker_position: Vector3 = source_position
		if not attacker_position.is_finite():
			var known: Variant = _target_position(source)
			if known != null: attacker_position = known
		var original := shield_damage
		shield_damage = actor.brain.block_damage(shield_damage, attacker_position)
		hull_damage *= shield_damage / original
	var absorbed := minf(actor.shield, shield_damage)
	world.combat.impact(actor.node.position, source_position, float(actor.radius), absorbed > 0)
	actor.shield -= absorbed
	actor.hull = maxf(0.0, actor.hull - hull_damage * (1.0 - absorbed / shield_damage))
	actor.disruption = maxf(actor.disruption, disruption)
	if disruption > 0:
		actor.cruise = false
		actor.cruise_charge = 0.0
		actor.velocity = (actor.velocity as Vector3).limit_length(12)
		actor.node.set_meta("cruise", false)
	if source == "player":
		actor.provoked = true
		if actor.role == "guard": alert_patrol(actor)
		if actor.hostile: actor.target = "player"
		else:
			actor.threat = "player"
			if actor.state != "FLEEING":
				actor.cruise_charge = 0.0
				actor.cruise = false
			actor.state = "FLEEING"
			actor.timer = 7.0
			_radio(actor, "Hold your fire! We are civilians!", true)
	elif actor.hostile:
		var attacker := get_actor(source)
		if not attacker.is_empty(): actor.target = source
	elif not actor.hostile:
		actor.threat = source
		if actor.state != "FLEEING":
			actor.cruise_charge = 0.0
			actor.cruise = false
		actor.state = "FLEEING"
		actor.timer = 7.0
		_radio(actor, "Taking fire! Breaking for harbour!", true)
	if actor.hull <= 0:
		if source == "player": world.law.record(actor.node, actor.allegiance, not actor.hostile, true)
		world.loot.drop_ship(actor.node, actor.hold, actor.velocity)
		world.combat._explosion(actor.node.position, clampf(float(actor.radius), 5.5, 14.0), actor.velocity)
		actor.alive = false
		actor.state = "DESTROYED"
		actor.node.visible = false
		actor.velocity = Vector3.ZERO
		_radio(actor, "Mayday—", true)
		if world.selected_id == id: world.select_target(world.DOCK_ID)
	_sync(actor)


func _advance_shots(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var shot := shots[i]
		var from := shot.position
		var next := from + (shot.get_meta("velocity") as Vector3) * delta
		var source: String = shot.get_meta("source")
		var hit := ""
		var nearest := INF
		for actor in actors.values():
			if actor.id == source or not actor.alive or not actor.node.visible: continue
			var distance: float = world.combat._segment_hit(from, next, actor.node.position, actor.radius)
			if distance >= 0 and distance < nearest:
				nearest = distance
				hit = actor.id
		if player_present and not world.combat.dead:
			var distance: float = world.combat._segment_hit(from, next, world.ship.position, 3.2)
			if distance >= 0 and distance < nearest: hit = "player"
		if hit == "player": world.combat.damage_player(float(shot.get_meta("damage")), -1.0, from)
		elif not hit.is_empty(): damage(hit, float(shot.get_meta("damage")), float(shot.get_meta("damage")), source, 0.0, from)
		shot.position = next
		var remaining := float(shot.get_meta("remaining")) - delta
		shot.set_meta("remaining", remaining)
		if not hit.is_empty() or remaining <= 0:
			shot.queue_free()
			shots.remove_at(i)


func _radio(actor: Dictionary, text: String, urgent := false) -> void:
	if elapsed < _radio_ready: return
	if actor.node.position.distance_to(world.ship.position) > 1500 and world.selected_id != actor.id: return
	radio_line = "%s: %s" % [actor.name, text]
	_radio_until = elapsed + 8.0
	_radio_ready = elapsed + (3.0 if urgent else 10.0)
	radio_history.append({"pilot": actor.pilot, "ship": actor.name, "text": text, "time": elapsed})
	if radio_history.size() > 8: radio_history.pop_front()


func _load_manifest(actor: Dictionary) -> void:
	var profile: Dictionary = profiles[actor.faction]
	var port: Dictionary = world.port_catalog.profile(actor.destination)
	var goods: Array = profile.cargo_goods.duplicate()
	if not actor.hostile:
		if port.theme == "planet": goods = ["grain", "oxygen", "lamp_oil"]
		elif port.theme in ["mining", "salvage"]: goods = ["argent_ore", "alloy"]
		var available := []
		for id in goods:
			if port.quotes.has(id): available.append(id)
		if available.is_empty(): available = port.quotes.keys()
		goods = available
	actor.hold = {}
	if goods.is_empty(): return
	var remaining := _cargo_random.randi_range(maxi(2, int(actor.cargo_capacity * (0.2 if actor.hostile else 0.5))), maxi(2, int(actor.cargo_capacity * (0.6 if actor.hostile else 0.85))))
	for i in mini(2, goods.size()):
		var id: String = goods[(int(_cargo_random.randi()) + i) % goods.size()]
		var amount := remaining if i == mini(2, goods.size()) - 1 else maxi(1, floori(remaining / 2.0))
		actor.hold[id] = int(actor.hold.get(id, 0)) + amount
		remaining -= amount
	actor.cargo = Holds.summary(actor.hold, LandingMarketState.ITEMS)


func alert_patrol(victim: Dictionary) -> void:
	for ally in actors.values():
		if not ally.alive or ally.role != "guard" or ally.allegiance != victim.allegiance: continue
		if ally.node.position.distance_to(victim.node.position) > 1500: continue
		ally.provoked = true
		ally.target = "player"
		ally.decision = 0.0
