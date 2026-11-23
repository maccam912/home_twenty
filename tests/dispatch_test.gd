extends SceneTree

const Dispatch = preload("res://game/dispatch.gd")
const Route = preload("res://world/route.gd")

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	var opening_sites := {}
	var opening_kinds := {}
	for seed_value in 2400:
		var deck := Dispatch.new(seed_value)
		deck.start_shift()
		opening_sites[deck.job.site] = true
		opening_kinds[deck.job.kind] = true
		var initial := deck.job.duplicate()
		deck.start_shift()
		check(deck.job == initial and deck.completed == 0, "Resuming a shift replaced its active order")
	check(opening_sites.size() == Route.SITES.size(), "Every worksite should be reachable on a first order")
	check(opening_kinds.size() == 4, "The first call should draw from the full work rotation")

	var deck := Dispatch.new(1998)
	deck.lane_is_open = func(id: String) -> bool: return id == "beck"
	deck.start_shift()
	var retired := {}
	var kinds := {}
	var counts_at_two_hundred := {}
	var haul_pairs := {}
	var freight := {}
	var pickup := ""
	var previous := ""
	while deck.completed < 600:
		var job := deck.job
		check(Route.SITES.has(job.site) and job.site != previous, "Each stop should send the driver to a different outdoor fixture")
		previous = job.site
		for field in ["brief", "instruction", "action", "speaker", "reply", "title"]:
			check(not String(job[field]).is_empty(), "Missing player-facing text for %s" % field)
		if job.kind == "plow":
			check(job.site != "beck" and not retired.has(job.site), "A permanently cleared approach was offered again")
			retired[job.site] = true
		check(job.has("cargo") == (job.kind == "haul" and job.leg == 2), "Only a collected shipment should appear in the pickup")
		if job.kind == "haul":
			if job.leg == 1:
				pickup = job.site
			else:
				haul_pairs[pickup + "/" + job.site] = true
				freight[job.cargo] = true
		var before := deck.completed
		var receipt := deck.finish_stop()
		check(receipt.text == job.reply and receipt.speaker == job.speaker, "Turn-in returned the wrong receipt")
		if job.leg < job.legs:
			check(deck.completed == before and deck.job.leg == 2 and deck.job.title == job.title, "Freight needs a second site before it counts")
		else:
			check(deck.completed == before + 1, "A signed order must advance exactly once")
			kinds[job.kind] = int(kinds.get(job.kind, 0)) + 1
			if deck.completed == 200:
				counts_at_two_hundred = kinds.duplicate()
	check(retired.size() == Route.SITES.size() - 1, "Each uncleared site should eventually get a plow order")
	for kind in ["visit", "windrow", "haul"]:
		check(kinds[kind] > counts_at_two_hundred[kind] + 40, "Long-running shifts should keep generating %s work" % kind)
	check(freight.size() == Dispatch.HAULS.size(), "Each shipment needs its own visible freight")
	check(haul_pairs.size() >= 12, "Freight routes should vary both destination and cargo")
	print("Dispatch: randomized ignition, continuous handoffs, lane persistence and 600 contracts. Failures: ", failures)
	quit(1 if failures else 0)
