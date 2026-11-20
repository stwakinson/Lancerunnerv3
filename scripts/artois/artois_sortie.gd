class_name ArtoisSortie
extends RefCounted
## Deliberately repeatable, session-only test contract. Economy saves separately.
signal changed
const TARGET_ID := "test_patrol"
const REWARD := 1500
const SITE := {"id": TARGET_ID, "name": "Test Patrol / Mission Area", "kind": "mission", "map": [680, 495], "altitude": 80, "notes": "Destroy five waiting freebooters. They engage within 420 m. Return to the market contact for payment."}
var phase := "available"
var kills := 0
var world: ArtoisSpace
var _counted := {}


func configure(space: ArtoisSpace) -> void:
	world = space
	world.combat.enemy_destroyed.connect(_on_enemy_destroyed)


func accept() -> bool:
	if phase not in ["available", "failed", "paid"]: return false
	if world.layout.target(TARGET_ID).is_empty(): world.layout.locations.append(SITE.duplicate(true))
	kills = 0
	_counted.clear()
	phase = "active"
	world.combat.spawn_patrol(world.layout.world(SITE))
	world.select_target(TARGET_ID)
	changed.emit()
	return true


func _on_enemy_destroyed(id: String) -> void:
	if phase != "active" or not id.begins_with("patrol_") or _counted.has(id): return
	_counted[id] = true
	kills += 1
	if kills == 5:
		phase = "return"
		world.select_target(world.DOCK_ID)
	changed.emit()


func fail() -> void:
	if phase == "active": phase = "failed"
	world.combat.clear_encounter()
	changed.emit()


func claim(market: LandingMarketState) -> bool:
	if phase != "return" or market.credits > 1000000000 - REWARD: return false
	market.credits += REWARD
	# Claim only succeeds if the existing atomic economy save succeeds.
	if not market.save_state():
		market.credits -= REWARD
		return false
	phase = "paid"
	changed.emit()
	return true


func summary() -> String:
	match phase:
		"active": return "TEST SORTIE  /  DESTROY FREEBOOTERS  %d / 5  /  M: MISSION WAYPOINT" % kills
		"return": return "TEST SORTIE COMPLETE  /  RETURN TO PLANET CONTACT FOR 1,500 CREDITS"
		"failed": return "TEST SORTIE FAILED  /  ASK THE PLANET CONTACT TO RETRY"
		"paid": return "TEST SORTIE  /  PAYMENT RECEIVED"
	return "TEST SORTIE  /  TALK TO THE PLANET CONTACT TO ACCEPT"
