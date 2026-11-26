extends RefCounted
## Authored local voices. A visit snapshots the roster and topics; no fabricated simulation events.
var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/artois_tavern_stories.json"))
var patrons: Array = []
var news: Array = []

func begin_visit(random: RandomNumberGenerator) -> void:
	var pool: Array = data.patrons.duplicate(true)
	_shuffle(pool, random)
	patrons = pool.slice(0, 3)
	for person in patrons:
		var available_topics: Array = person.topics
		var first := random.randi_range(0, available_topics.size() - 1)
		person.topics = [available_topics[first], available_topics[(first + 1) % available_topics.size()]]
	var articles: Array = data.news.duplicate(true)
	_shuffle(articles, random)
	news = articles.slice(0, 4)

func patron(id: String) -> Dictionary:
	for entry in patrons:
		if entry.id == id: return entry
	return {}

func trade_tip(market: RefCounted, good: String, source: String, destination: String) -> Dictionary:
	var from_port: Dictionary = market.markets.profile(source)
	var to_port: Dictionary = market.markets.profile(destination)
	var buys: Array = from_port.get("quotes", {}).get(good, [])
	var sells: Array = to_port.get("quotes", {}).get(good, [])
	if buys.size() != 2 or sells.size() != 2: return {}
	var margin := int(sells[1]) - int(buys[0])
	if margin <= 0: return {}
	return {"id": "trade_" + good, "title": "%s: %s to %s" % [market.ITEMS[good].name, from_port.name, to_port.name], "kind": "VERIFIED TRADE TIP", "text": "Buy %s at %s for %d cr per unit. %s pays %d cr per unit to buy it from you.\n\nGross margin: %d cr per unit, before combat losses or consumables. Check your hold capacity before buying.\n\nThese figures come from the current posted market prices. Allow for any docking restrictions along your route." % [market.ITEMS[good].name, from_port.name, int(buys[0]), to_port.name, int(sells[1]), margin]}

func topics(id: String, market: RefCounted) -> Array:
	var person := patron(id)
	if person.is_empty(): return []
	var result: Array = person.topics.duplicate(true)
	var routes := [["grain", "planet_dock", "border_post"], ["oxygen", "planet_dock", "embry"], ["argent_ore", "embry", "planet_dock"]]
	var route: Array = routes[[2, 2, 0, 1, 0, 0, 1, 1][int(person.cell)]]
	var tip := trade_tip(market, route[0], route[1], route[2])
	if not tip.is_empty(): result.append(tip)
	return result

func _shuffle(values: Array, random: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var value: Variant = values[i]
		values[i] = values[j]
		values[j] = value
