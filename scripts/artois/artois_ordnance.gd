class_name ArtoisOrdnance
extends RefCounted
## Cursor gimbals, seeker acquisition, ammunition and period-inspired supplies.
const ARC := PI / 6.0
const LOCK_TIME := 1.5
const LOCK_RANGE := 600.0
const MISSILES := {
	"pavise_missile": {"name": "PAVISE", "shield": 90.0, "hull": 6.0, "speed": 180.0, "colour": "83caff"},
	"bodkin_missile": {"name": "BODKIN", "shield": 8.0, "hull": 80.0, "speed": 160.0, "colour": "ffbc75"},
	"fetter_missile": {"name": "FETTER", "shield": 12.0, "hull": 5.0, "speed": 220.0, "colour": "b9a0ff"},
}
var combat: Node3D
var world: Node3D
var market: LandingMarketState
var selected_missile := "pavise_missile"
var lock_id := ""
var lock_progress := 0.0
var missile_cooldown := 0.0
var recovery_cooldown := 0.0
var cursor_enabled := false
var cursor := Vector2.ZERO
var pointer_direction := Vector3.FORWARD
var aim_direction := Vector3.FORWARD
var aim_depth := 350.0
var aim_clamped := false
var message := ""
var message_time := 0.0


func configure(owner_combat: Node3D, inventory: LandingMarketState) -> void:
	combat = owner_combat
	world = combat.world
	market = inventory
	reset_lock()


func set_cursor(pixel: Vector2) -> void:
	cursor = pixel
	cursor_enabled = true
	update_aim()


func update_aim() -> void:
	var forward: Vector3 = -world.ship.basis.z
	aim_direction = forward
	pointer_direction = forward
	aim_clamped = false
	var target: Node3D = combat.enemy(world.selected_id)
	aim_depth = clampf((target.position - world.ship.position).dot(forward), 20.0, 700.0) if target != null else 350.0
	if not cursor_enabled: return
	var origin: Vector3 = world.camera.project_ray_origin(cursor)
	var ray: Vector3 = world.camera.project_ray_normal(cursor)
	var denominator := ray.dot(forward)
	var desired := ray
	if denominator > 0.001:
		var distance: float = (world.ship.position + forward * aim_depth - origin).dot(forward) / denominator
		if distance > 0: desired = (origin + ray * distance - world.ship.position).normalized()
	pointer_direction = desired.normalized()
	aim_clamped = forward.angle_to(desired) > ARC
	aim_direction = clamp_direction(forward, desired, ARC, world.ship.basis.y)


static func clamp_direction(forward: Vector3, desired: Vector3, arc: float, fallback: Vector3) -> Vector3:
	var angle := forward.angle_to(desired)
	if angle <= arc: return desired.normalized()
	var axis := forward.cross(desired)
	if axis.length_squared() < 0.00001: axis = fallback
	return forward.rotated(axis.normalized(), arc).normalized()


func aim_point() -> Vector3:
	return world.ship.position + aim_direction * aim_depth


func reset_lock() -> void:
	lock_id = ""
	lock_progress = 0.0


func transit_locked() -> bool:
	return combat.dead or world.cruise or world.cruise_spool > 0 or world.highways.attached()


func lock_candidate() -> String:
	if transit_locked() or not combat.weapons.has("missile_rack"): return ""
	var target: Node3D = combat.enemy(world.selected_id)
	if target == null: return ""
	var delta: Vector3 = target.position - world.ship.position
	if delta.length() > LOCK_RANGE or delta.length() < 5.0: return ""
	if (-world.ship.basis.z).dot(delta.normalized()) < cos(deg_to_rad(20.0)): return ""
	var planet: Vector3 = world.layout.world(world.layout.planet)
	if combat._segment_hit(world.ship.position, target.position, planet, float(world.layout.planet.radius)) >= 0: return ""
	return world.selected_id


func advance(delta: float) -> void:
	update_aim()
	missile_cooldown = maxf(0.0, missile_cooldown - delta)
	recovery_cooldown = maxf(0.0, recovery_cooldown - delta)
	message_time = maxf(0.0, message_time - delta)
	var candidate := lock_candidate()
	if candidate.is_empty():
		reset_lock()
		return
	if lock_id != candidate:
		lock_id = candidate
		lock_progress = 0.0
	lock_progress = minf(LOCK_TIME, lock_progress + delta)


func notify(text: String) -> void:
	message = text
	message_time = 3.0


func cycle_missile() -> void:
	var ids := MISSILES.keys()
	selected_missile = ids[(ids.find(selected_missile) + 1) % ids.size()]
	reset_lock()
	notify("MISSILE SELECTED / " + str(MISSILES[selected_missile].name))


func launch() -> bool:
	if transit_locked():
		notify("MISSILES LOCKED DURING TRANSIT")
		return false
	if not combat.weapons.has("missile_rack"):
		notify("FIT A FALCON MISSILE RACK AT THE OUTFITTER")
		return false
	if lock_progress < LOCK_TIME or lock_id != lock_candidate() or lock_id.is_empty():
		notify("MISSILE REQUIRES A 1.5s LOCK / TARGET WITHIN 600 m AND 20 DEGREES")
		return false
	if missile_cooldown > 0: return false
	if combat.defence.energy < 12.0:
		notify("INSUFFICIENT ENERGY / MISSILE REQUIRES 12")
		return false
	var error := market.consume(selected_missile)
	if not error.is_empty():
		notify(error)
		return false
	combat.defence.spend(12.0)
	var slot: int = combat.weapons.find("missile_rack")
	var at: Vector3 = world.ship.global_transform * Vector3(-1.05 if slot == 0 else 1.05, 0.12, -3)
	var target: Node3D = combat.enemy(lock_id)
	var stats: Dictionary = MISSILES[selected_missile]
	var shot: MeshInstance3D = combat._projectile(at, at.direction_to(target.position) * float(stats.speed), 0.0, str(stats.colour), 5.0)
	var body := BoxMesh.new()
	body.size = Vector3(0.38, 0.38, 1.8)
	shot.mesh = body
	var exhaust := MeshInstance3D.new()
	var glow := SphereMesh.new()
	glow.radius = 0.22
	glow.height = 0.44
	exhaust.mesh = glow
	exhaust.position.z = 1.1
	exhaust.material_override = world._material("ffc27c", true)
	shot.add_child(exhaust)
	shot.set_meta("weapon", "missile_rack")
	shot.set_meta("missile", selected_missile)
	shot.set_meta("speed", stats.speed)
	shot.set_meta("target", lock_id)
	world.shots.append(shot)
	missile_cooldown = 1.2
	notify(str(stats.name) + " AWAY")
	return true


func use_recovery(id: String) -> bool:
	if combat.dead: return false
	if id not in ["armourer_mites", "ward_phial"]: return false
	if recovery_cooldown > 0:
		notify("RECOVERY SERVITORS RECHARGING")
		return false
	var full: bool = (combat.hull >= combat.HULL_MAX and combat.defence.armour >= combat.defence.ARMOUR_MAX) if id == "armourer_mites" else combat.shield >= combat.shield_max
	if full:
		notify("HULL ALREADY SOUND" if id == "armourer_mites" else "SHIELDS ALREADY FULL")
		return false
	var error := market.consume(id)
	if not error.is_empty():
		notify(error)
		return false
	if id == "armourer_mites":
		combat.hull = minf(combat.HULL_MAX, combat.hull + 60.0)
		combat.defence.armour = minf(combat.defence.ARMOUR_MAX, combat.defence.armour + 40.0)
	else:
		combat.shield = minf(combat.shield_max, combat.shield + 90.0)
		combat._shield_flash = 0.25
	recovery_cooldown = 3.0
	notify("ARMOURER'S MITES / HULL + ARMOUR REPAIRED" if id == "armourer_mites" else "WARD PHIAL / SHIELDS RESTORED")
	return true
