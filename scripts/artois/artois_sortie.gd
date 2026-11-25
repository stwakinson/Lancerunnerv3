class_name ArtoisSortie
extends RefCounted
## One session contract at a time; credits and faction rewards save atomically.
signal changed
const TARGET_ID := "test_patrol"
const REWARD := 1500
const SITE := {"id": TARGET_ID, "name": "Test Patrol / Mission Area", "kind": "mission", "map": [680, 495], "altitude": 80, "notes": "Destroy five waiting freebooters. They engage within 420 m. Return to the market contact for payment."}
const Board = preload("res://scripts/artois/artois_contract_board.gd")
var board := Board.new()
var active_offer := {}
var required_kills := 5
var _objectives := {}
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
	active_offer = {}
	required_kills = 5
	_objectives.clear()
	kills = 0
	_counted.clear()
	phase = "active"
	world.combat.spawn_patrol(world.layout.world(SITE))
	world.select_target(TARGET_ID)
	changed.emit()
	return true


func _on_enemy_destroyed(id: String) -> void:
	if phase != "active" or _counted.has(id): return
	if not active_offer.is_empty():
		if not _objectives.has(id): return
	elif not id.begins_with("patrol_"): return
	_counted[id] = true
	kills += 1
	if kills == required_kills:
		phase = "return"
		world.select_target(return_port())
	changed.emit()


func fail() -> void:
	if phase in ["active", "return"]:
		phase = "failed"
		_resolve_offer()
	world.combat.clear_encounter()
	changed.emit()


func return_port() -> String:
	return str(active_offer.get("port", world.DOCK_ID))

func accept_error(contact_id: String, offer_id: String, market: LandingMarketState) -> String:
	if phase in ["active", "return"]: return "Finish or abandon your current contract first."
	var issuer: Dictionary = board.contact(contact_id)
	if issuer.is_empty() or market.market_id != issuer.port or not world.docked or world.active_port != issuer.port: return "Visit the issuing contact to accept."
	for offer in board.offers(contact_id, world):
		if offer.id != offer_id: continue
		var access := market.Factions.access_error(market.reputation, issuer.port)
		if not access.is_empty(): return access
		if int(market.reputation[issuer.faction]) < int(offer.minimum_reputation):
			return "%s standing %d required." % [market.Factions.data.factions[issuer.faction].name, int(offer.minimum_reputation)]
		return ""
	return "This offer is no longer available."

func accept_offer(contact_id: String, offer_id: String, market: LandingMarketState) -> bool:
	if not accept_error(contact_id, offer_id, market).is_empty(): return false
	for offer in board.offers(contact_id, world):
		if offer.id == offer_id: active_offer = offer.duplicate(true)
	if active_offer.is_empty(): return false
	_remove_marker()
	var map: Vector2 = active_offer.site
	var marker := {"id": TARGET_ID, "name": active_offer.title + " / Contract Area", "kind": "mission", "map": [map.x, map.y], "altitude": active_offer.altitude, "notes": active_offer.brief}
	world.layout.locations.append(marker)
	kills = 0
	required_kills = int(active_offer.objective)
	_counted.clear()
	_objectives.clear()
	phase = "active"
	world.combat.spawn_patrol(world.layout.world(marker), {"count": active_offer.count, "prefix": active_offer.id + "_", "faction": active_offer.enemy_faction, "hull_scale": active_offer.hull_scale, "captain": active_offer.captain if active_offer.template == "bounty" else ""})
	for i in world.combat.enemies.size():
		if active_offer.template != "bounty" or i == 0: _objectives[str(world.combat.enemies[i].get_meta("id"))] = true
	world.select_target(TARGET_ID)
	changed.emit()
	return true

func abandon() -> bool:
	if phase not in ["active", "return"]: return false
	phase = "abandoned"
	world.combat.clear_encounter()
	_resolve_offer()
	changed.emit()
	return true

func claim_error(market: LandingMarketState, contact_id := "") -> String:
	if phase != "return": return "Complete the objective before claiming payment."
	if active_offer.is_empty(): return ""
	if market.market_id != return_port() or contact_id != active_offer.contact or not world.docked or world.active_port != return_port():
		return "Return to %s at %s." % [active_offer.issuer, market.markets.profile(return_port()).name]
	return market.Factions.access_error(market.reputation, return_port())

func claim(market: LandingMarketState, contact_id := "") -> bool:
	if not claim_error(market, contact_id).is_empty(): return false
	var reward := int(active_offer.get("reward", REWARD))
	if market.credits > 1000000000 - reward: return false
	var previous_reputation: Dictionary = market.reputation.duplicate()
	if active_offer.is_empty():
		for faction in ["britannian", "valois"]: market.reputation[faction] = mini(100, int(market.reputation[faction]) + 10)
	else:
		var faction: String = active_offer.faction
		market.reputation[faction] = mini(100, int(market.reputation[faction]) + int(active_offer.reputation))
	market.credits += reward
	if not market.save_state():
		market.reputation = previous_reputation
		market.credits -= reward
		return false
	phase = "paid"
	world.combat.clear_encounter()
	_resolve_offer()
	changed.emit()
	return true

func _remove_marker() -> void:
	for i in range(world.layout.locations.size() - 1, -1, -1):
		if world.layout.locations[i].id == TARGET_ID: world.layout.locations.remove_at(i)

func _resolve_offer() -> void:
	if not active_offer.is_empty(): board.invalidate(active_offer.contact)
	world.select_target(return_port())
	_remove_marker()

func summary() -> String:
	var title: String = str(active_offer.get("title", "Test sortie"))
	match phase:
		"active": return "CONTRACT / %s / %d OF %d / M: WAYPOINT" % [title, kills, required_kills]
		"return": return "CONTRACT COMPLETE / RETURN TO " + str(world.port_catalog.profile(return_port()).name).to_upper()
		"failed": return "CONTRACT FAILED / VISIT A FACTION CONTACT FOR NEW WORK"
		"abandoned": return "CONTRACT ABANDONED / VISIT A FACTION CONTACT FOR NEW WORK"
		"paid": return "CONTRACT / PAYMENT AND REPUTATION RECEIVED"
	return "CONTRACTS / VISIT PLANET OR CARRIER FACTION CONTACTS"
