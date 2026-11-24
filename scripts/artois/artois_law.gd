extends Node
## Persistent faction standings; attacks are charged per incident, never per bullet.
const Factions = preload("res://scripts/artois/artois_factions.gd")
const HOSTILE := -50
const ATTACK := -8
const DESTRUCTION := -30
var world: Node3D
var ledger_visible := false
var last_notice := ""
var _dirty: RefCounted
var _retry := 0.0

func market() -> RefCounted:
	return world.combat.ordnance.market

func score(faction: String) -> int:
	return int(market().reputation.get(faction, 0))

func hostile(faction: String) -> bool:
	return score(faction) <= HOSTILE

func relation(faction: String) -> String:
	return "HOSTILE / SHOOT ON SIGHT" if hostile(faction) else ("WARY" if score(faction) <= -20 else "NEUTRAL")

func enemy(actor: Dictionary) -> bool:
	return bool(actor.provoked) or hostile(str(actor.allegiance))

func record(victim: Node3D, faction: String, civilian: bool, destroyed := false) -> void:
	if not Factions.data.factions.has(faction): return
	if destroyed:
		if victim.get_meta("law_destroyed", false): return
		victim.set_meta("law_destroyed", true)
	else:
		var now: float = world.traffic.elapsed
		if now < float(victim.get_meta("law_next_attack", -1.0)): return
		victim.set_meta("law_next_attack", now + 30.0)
	var penalty := DESTRUCTION if destroyed else ATTACK
	_change(faction, penalty)
	if civilian and bool(Factions.data.factions[faction].lawful):
		for protector in ["britannian", "valois"]:
			if protector != faction: _change(protector, -12 if destroyed else -3)
	last_notice = "%s: %s (%d) / %s" % [Factions.data.factions[faction].name, "VESSEL DESTROYED" if destroyed else "ASSAULT REPORTED", penalty, relation(faction)]
	world.combat.ordnance.notify(last_notice)
	_dirty = market()
	_flush()

func _change(faction: String, amount: int) -> void:
	market().reputation[faction] = clampi(score(faction) + amount, -100, 100)

func _flush() -> void:
	if _dirty == null: return
	if _dirty != market():
		_dirty = null
		return
	if _dirty.save_state(): _dirty = null
	else: push_warning("Reputation save failed; standings retained in memory and will retry.")
	_retry = 5.0

func _process(delta: float) -> void:
	if _dirty == null: return
	_retry -= delta
	if _retry <= 0: _flush()

func territory_owner(id: String) -> String:
	return str(Factions.data.owners.get(id, ""))

func description(faction: String) -> String:
	return "%s: %d / %s" % [Factions.data.factions[faction].name, score(faction), relation(faction)]
