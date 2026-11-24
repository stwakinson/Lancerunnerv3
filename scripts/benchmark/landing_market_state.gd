class_name LandingMarketState
extends RefCounted

# Shared landing economy. Artois reads this loadout on launch; the original
# combat mission remains separate. Prices are fixed; quantities and stock persist.

const ShipHolds = preload("res://scripts/artois/artois_ship_holds.gd")
const Markets = preload("res://scripts/artois/artois_markets.gd")
const Factions = preload("res://scripts/artois/artois_factions.gd")
const VERSION := 1
var reputation := Factions.defaults()
const BASE_CAPACITY := 20
const ITEMS := {
	"grain": {"name": "Wheat & Grain", "kind": "commodity", "buy": 40, "sell": 32, "stock": 90, "description": "Planet-grown wheat and staple grain. Orbital settlements pay a small premium. One hold space."},
	"alloy": {"name": "Refined alloy", "kind": "commodity", "buy": 120, "sell": 96, "stock": 45, "description": "Structural metal for shipyards, hull repairs and fortress maintenance. One cargo space per unit."},
	"medicine": {"name": "Apothecary Chests", "kind": "commodity", "buy": 210, "sell": 168, "stock": 30, "description": "Field medicines and salves. Chapter apothecaries supply garrisons and civilian infirmaries. One hold space."},
	"textiles": {"name": "Fine Broadcloth", "kind": "commodity", "buy": 160, "sell": 128, "stock": 35, "description": "Valois cloth prized by merchants and officers alike. One cargo space per unit."},
	"fuel": {"name": "Reactor cells", "kind": "commodity", "buy": 95, "sell": 76, "stock": 60, "description": "Sealed industrial power cells, traded as cargo. One cargo space per unit."},
	"oxygen": {"name": "Bottled Air", "kind": "commodity", "buy": 20, "sell": 18, "stock": 120, "description": "Purified oxygen and breathing air from the planet's airworks. Essential cargo for sealed settlements; one hold space."},
	"wool": {"name": "Wool Bales", "kind": "commodity", "buy": 62, "sell": 57, "stock": 45, "description": "Fleece for cloth workshops and shipboard insulation. Northern factors sell cheaply; southern weavers pay more."},
	"argent_ore": {"name": "Argent Ore", "kind": "commodity", "buy": 182, "sell": 174, "stock": 12, "description": "Silver-bearing rare-metal concentrate for contacts, instruments and plate. Mining and salvage ports export it."},
	"ale": {"name": "Ale Casks", "kind": "commodity", "buy": 32, "sell": 28, "stock": 50, "description": "A familiar comfort for dockworkers and garrisons. Counting houses and chapter brewers supply the trade."},
	"lamp_oil": {"name": "Tallow & Lamp Oil", "kind": "commodity", "buy": 48, "sell": 44, "stock": 60, "description": "Rendering-house oils for lamps, seals and machinery. Cheap planetside; stations pay a little more."},
	"pulse_laser": {"name": "Lance pulse laser", "kind": "weapon", "buy": 1400, "sell": 1050, "stock": 6, "description": "Class I energy weapon. Artois: 48 damage, 125 m/s, 12 energy per shot. Fits either weapon hardpoint in the prototype loadout."},
	"autocannon": {"name": "Longbow autocannon", "kind": "weapon", "buy": 2100, "sell": 1575, "stock": 4, "description": "Class I ballistic weapon. Artois: 24 damage, 165 m/s, 6 energy per shot. Fits either prototype weapon hardpoint."},
	"missile_rack": {"name": "Falcon missile rack", "kind": "weapon", "buy": 2600, "sell": 1950, "stock": 3, "description": "Launches Pavise, Bodkin or Fetter rounds. Z selects ammo; F fires after a 1.5-second lock. Uses 12 energy per launch. Ammunition sold separately."},
	"shield": {"name": "Aegis shield generator", "kind": "utility", "buy": 1800, "sell": 1350, "stock": 4, "description": "Raises Artois shields from 60 to 180 and regeneration from 8 to 22 per second after four seconds without damage. Fits the utility mount."},
	"cargo_expander": {"name": "Cargo expansion module", "kind": "utility", "buy": 900, "sell": 675, "stock": 5, "description": "Adds 10 cargo spaces while fitted. Empty the extra cargo space before removing this module."},
	"pavise_missile": {"name": "Pavise missile", "kind": "consumable", "buy": 120, "sell": 90, "stock": 40, "description": "Anti-shield round: 90 shield / 6 hull damage. Requires a Falcon rack and lock. Z selects; F launches."},
	"bodkin_missile": {"name": "Bodkin missile", "kind": "consumable", "buy": 180, "sell": 135, "stock": 30, "description": "Anti-hull round: 8 shield / 80 hull damage. Shields must be stripped first. Z selects; F launches from a Falcon rack."},
	"fetter_missile": {"name": "Fetter missile", "kind": "consumable", "buy": 90, "sell": 65, "stock": 40, "description": "Disruptor: 12 shield / 5 hull damage. Cancels cruise and caps speed at 12 m/s for six seconds. Requires a Falcon rack."},
	"armourer_mites": {"name": "Armourer's Mites", "kind": "consumable", "buy": 180, "sell": 135, "stock": 25, "description": "Tiny repair servitors, an armourer's retinue for your hull. B restores 60 hull and 40 armour. Shared three-second recovery cooldown."},
	"ward_phial": {"name": "Ward Phial", "kind": "consumable", "buy": 140, "sell": 105, "stock": 30, "description": "A sealed reserve of warding energy. N restores 90 shield. Shared three-second recovery cooldown."},
}
const LEGACY_IDS := ["grain", "alloy", "medicine", "textiles", "fuel", "pulse_laser", "autocannon", "missile_rack", "shield", "cargo_expander"]

var ship_class := "fighter"
var credits := 7500
var cargo := {"grain": 3, "alloy": 1}
var locker := {}
var weapons: Array = ["pulse_laser", ""]
var utility := ""
var markets := Markets.new()
var market_id := "planet_dock"
var market_stocks := {}
var stock := {}
var save_path := "user://lancerunner_market_preview_v1.json"


func _init() -> void:
	for id in ITEMS:
		stock[id] = int(ITEMS[id].stock)
	market_stocks[market_id] = stock


func cargo_used() -> int:
	var used := 0
	for amount in cargo.values():
		used += amount
	return used


func capacity() -> int:
	return ShipHolds.capacity(ship_class) + (10 if utility == "cargo_expander" else 0)


func owned(id: String) -> int:
	return int((cargo if ITEMS[id].kind == "commodity" else locker).get(id, 0))


func trade_error(id: String, quantity: int, buying: bool) -> String:
	if not ITEMS.has(id) or quantity < 1 or quantity > 99:
		return "Choose a valid item and a quantity from 1 to 99."
	var item := quote(id)
	if item.kind == "commodity" and not trades_good(id): return "This market does not trade that good."
	if buying:
		if quantity > int(stock[id]): return "The dealer does not have that many in stock."
		if credits < int(item.buy) * quantity: return "Insufficient credits."
		if item.kind == "commodity" and cargo_used() + quantity > capacity(): return "Not enough cargo space."
		if item.kind != "commodity" and owned(id) + quantity > 99: return "Equipment locker limit reached."
	else:
		if owned(id) < quantity: return "Not enough in your cargo or locker. Unmount fitted equipment before selling it."
		if int(stock[id]) + quantity > 9999: return "The dealer cannot accept more stock."
		if credits + int(item.sell) * quantity > 1000000000: return "Credit limit reached."
	return ""


func trade(id: String, quantity: int, buying: bool) -> String:
	var error := trade_error(id, quantity, buying)
	if not error.is_empty(): return error
	var item := quote(id)
	var inventory: Dictionary = cargo if item.kind == "commodity" else locker
	inventory[id] = owned(id) + (quantity if buying else -quantity)
	if inventory[id] == 0: inventory.erase(id)
	credits += (-int(item.buy) if buying else int(item.sell)) * quantity
	stock[id] = int(stock[id]) + (-quantity if buying else quantity)
	return ""


func fit_error(id: String) -> String:
	if not ITEMS.has(id) or ITEMS[id].kind not in ["weapon", "utility"]: return "Select a weapon or utility to fit."
	if owned(id) < 1: return "Buy an item or choose one in your locker first."
	if ITEMS[id].kind == "weapon" and not weapons.has(""): return "Unmount a weapon to free a hardpoint."
	if ITEMS[id].kind == "utility" and not utility.is_empty(): return "Unmount the current utility first."
	return ""


func fit(id: String) -> String:
	var error := fit_error(id)
	if not error.is_empty(): return error
	if ITEMS[id].kind == "weapon":
		weapons[weapons.find("")] = id
	else:
		utility = id
	locker[id] = owned(id) - 1
	if locker[id] == 0: locker.erase(id)
	return ""


func unmount(slot: int) -> String:
	if slot < 0 or slot > 2: return "Invalid equipment slot."
	var id: String = utility if slot == 2 else weapons[slot]
	if id.is_empty(): return "This slot is empty."
	if id == "cargo_expander" and cargo_used() > ShipHolds.capacity(ship_class): return "Reduce cargo to %d units before removing the expansion module." % ShipHolds.capacity(ship_class)
	if int(locker.get(id, 0)) >= 99: return "Equipment locker limit reached."
	locker[id] = int(locker.get(id, 0)) + 1
	if slot == 2: utility = ""
	else: weapons[slot] = ""
	return ""


func save_state() -> bool:
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"reputation": reputation, "version": VERSION, "ship_class": ship_class, "credits": credits, "cargo": cargo, "locker": locker, "weapons": weapons, "utility": utility, "stock": stock, "market_id": market_id, "market_stocks": market_stocks}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path)) == OK


func load_state() -> bool:
	if not FileAccess.file_exists(save_path): return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not _valid_save(data): return false
	reputation = Factions.defaults()
	reputation.merge(_integer_inventory(data.get("reputation", {})), true)
	ship_class = str(data.get("ship_class", "fighter"))
	credits = int(data.credits)
	cargo = _integer_inventory(data.cargo)
	locker = _integer_inventory(data.locker)
	weapons = data.weapons.duplicate()
	utility = data.utility
	market_id = str(data.get("market_id", "planet_dock"))
	market_stocks.clear()
	for port in data.get("market_stocks", {}):
		var inventory := _initial_stock(port)
		inventory.merge(_integer_inventory(data.market_stocks[port]), true)
		market_stocks[port] = inventory
	stock = _initial_stock(market_id)
	stock.merge(_integer_inventory(data.stock), true)
	market_stocks[market_id] = stock
	return true


func _integer_inventory(source: Dictionary) -> Dictionary:
	var result := {}
	for id in source: result[id] = int(source[id])
	return result


func _whole(value: Variant, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0 and float(value) <= maximum and float(value) == floorf(float(value))


func _valid_save(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION or not _whole(data.get("credits"), 1000000000): return false
	if data.has("reputation") and not Factions.valid(data.reputation): return false
	for key in ["cargo", "locker", "stock"]:
		if not data.get(key) is Dictionary: return false
		for id in data[key]:
			if not ITEMS.has(id) or not _whole(data[key][id], 9999 if key in ["stock", "cargo"] else 99): return false
			if key == "cargo" and ITEMS[id].kind != "commodity": return false
			if key == "locker" and ITEMS[id].kind == "commodity": return false
	# New supply stock is additive; preserve all original save validation.
	for id in LEGACY_IDS:
		if not data.stock.has(id): return false
	if data.has("market_id") or data.has("market_stocks"):
		if not data.get("market_id") is String or not markets.has_port(data.market_id) or not data.get("market_stocks") is Dictionary: return false
		for port in data.market_stocks:
			if not markets.has_port(port) or not data.market_stocks[port] is Dictionary: return false
			for id in data.market_stocks[port]:
				if not ITEMS.has(id) or not _whole(data.market_stocks[port][id], 9999): return false
			for id in LEGACY_IDS:
				if not data.market_stocks[port].has(id): return false
	if not data.get("weapons") is Array or data.weapons.size() != 2: return false
	for id in data.weapons:
		if not id is String or (not id.is_empty() and (not ITEMS.has(id) or ITEMS[id].kind != "weapon")): return false
	var util: Variant = data.get("utility")
	if not util is String or (not util.is_empty() and (not ITEMS.has(util) or ITEMS[util].kind != "utility")): return false
	var hull_class: Variant = data.get("ship_class", "fighter")
	if not hull_class is String or not ShipHolds.CAPACITIES.has(hull_class): return false
	var used := 0
	for amount in data.cargo.values(): used += int(amount)
	return used <= ShipHolds.capacity(hull_class) + (10 if util == "cargo_expander" else 0)


func consume(id: String) -> String:
	if not ITEMS.has(id) or ITEMS[id].kind != "consumable": return "Invalid supply."
	var before := owned(id)
	if before < 1: return "No %s aboard. Buy supplies at the outfitter." % ITEMS[id].name
	if before == 1: locker.erase(id)
	else: locker[id] = before - 1
	if not save_state():
		locker[id] = before
		return "Supply use could not be saved; nothing was consumed."
	return ""


func trades_good(id: String) -> bool:
	return ITEMS.has(id) and (ITEMS[id].kind != "commodity" or markets.profile(market_id).quotes.has(id))


func quote(id: String) -> Dictionary:
	var item: Dictionary = ITEMS[id].duplicate()
	var prices: Array = markets.profile(market_id).quotes.get(id, [])
	if item.kind == "commodity" and prices.size() == 2:
		item.buy = int(prices[0])
		item.sell = int(prices[1])
	return item


func _initial_stock(port: String) -> Dictionary:
	var result := {}
	var profile := markets.profile(port)
	for id in ITEMS:
		result[id] = int(profile.stock.get(id, ITEMS[id].stock))
		if ITEMS[id].kind == "commodity" and not profile.quotes.has(id): result[id] = 0
	return result


func set_market(port: String) -> bool:
	if not markets.has_port(port): return false
	market_stocks[market_id] = stock
	if not market_stocks.has(port): market_stocks[port] = _initial_stock(port)
	market_id = port
	stock = market_stocks[port]
	return true


func acquire_cargo(id: String, requested: int) -> Dictionary:
	if not ITEMS.has(id) or ITEMS[id].kind != "commodity" or requested < 1: return {"taken": 0, "error": "Invalid recovered cargo."}
	var amount := mini(requested, maxi(0, capacity() - cargo_used()))
	if amount == 0: return {"taken": 0, "error": "HOLD FULL / %d OF %d" % [cargo_used(), capacity()]}
	var before := cargo.duplicate(true)
	cargo[id] = int(cargo.get(id, 0)) + amount
	if not save_state():
		cargo = before
		return {"taken": 0, "error": "Cargo recovery could not be saved; canister unchanged."}
	return {"taken": amount, "error": ""}


func set_ship_class(id: String) -> String:
	if not ShipHolds.CAPACITIES.has(id): return "Unknown ship class."
	if cargo_used() > ShipHolds.capacity(id) + (10 if utility == "cargo_expander" else 0): return "Cargo will not fit this ship."
	var before := ship_class
	ship_class = id
	if not save_state():
		ship_class = before
		return "Ship class could not be saved."
	return ""
