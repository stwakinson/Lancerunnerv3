class_name ArtoisShipHolds
extends RefCounted
## Commodity units, not equipment locker slots. Shared by player saves and NPC hulls.
const CAPACITIES := {"longbow": 16, "epervier": 14, "interceptor": 8, "fighter": 20, "courier": 24, "salvager": 40, "light_freighter": 60, "hauler": 80, "pilgrim": 90, "cog": 120}

static func capacity(ship_class: String) -> int:
	return int(CAPACITIES.get(ship_class, CAPACITIES.fighter))

static func used(hold: Dictionary) -> int:
	var amount := 0
	for quantity in hold.values(): amount += int(quantity)
	return amount

static func summary(hold: Dictionary, items: Dictionary) -> String:
	var labels := PackedStringArray()
	for id in hold:
		if items.has(id) and int(hold[id]) > 0: labels.append("%s ×%d" % [items[id].name, int(hold[id])])
	return ", ".join(labels) if not labels.is_empty() else "Empty"
