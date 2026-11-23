extends RefCounted

const Route = preload("res://world/route.gd")

# Recipient pools keep the paperwork, equipment and food going somewhere that uses them.
const HAULS := {
	"mill": {"cargo": "ticket", "item": "scale ticket", "take": "Take ticket", "give": "File ticket",
		"packed": "The ticket's folded around a carbon. There's a greasy thumbprint on both copies.",
		"delivered": "You file the carbon in the outside clip and keep the driver's copy.",
		"receivers": ["station", "kroll", "quarry", "beck"]},
	"quarry": {"cargo": "grit", "item": "bag of grit", "take": "Load grit", "give": "Unload grit",
		"packed": "You tip a canvas sack over the tailgate. The grit rattles all the way to the bottom.",
		"delivered": "You leave the grit within reach of the steps, with the tied end up.",
		"receivers": ["bell", "station", "lutheran", "beck"]},
	"lutheran": {"cargo": "coffee", "item": "coffee jug", "take": "Take jug", "give": "Leave coffee",
		"packed": "There's a gingham sock over the jug to keep it warm. Smells like somebody made it strong.",
		"delivered": "You tuck the jug out of the wind. Two enamel cups hang from the handle.",
		"receivers": ["quarry", "mill", "station", "beck"]},
	"station": {"cargo": "flares", "item": "tin of flares", "take": "Load flares", "give": "Leave flares",
		"packed": "You take the red tin. Somebody printed DRY SIDE UP on both sides.",
		"delivered": "You set the flare tin under cover where the road crew can reach it.",
		"receivers": ["bell", "quarry", "mill"]},
	"kroll": {"cargo": "mitts", "item": "pair of mitts", "take": "Take mitts", "give": "Leave mitts",
		"packed": "Dry choppers, still warm in their brown paper bag. Somebody packed wool liners too.",
		"delivered": "You hang the bag high enough to stay out of the drift.",
		"receivers": ["station", "quarry", "mill"]},
}

# A returning driver gets a different visit at the same fixture.
const SITE_CALLS := {
	"beck": [
		["Propane reading", "Collect the tank reading", "Take reading", "Mrs. Beck has penciled the gauge reading on a feed envelope. You tuck it in your pocket for the supplier."],
		["Porch call", "Knock at the porch", "Knock", "Mrs. Beck knocks twice on the glass and holds up her coffee cup. They're warm and doing fine."],
	],
	"mill": [
		["Truck tally", "Read the tally card", "Read tally", "Six trucks through the scales. Bader penciled a little star beside the one that made it up the hill."],
		["Scale slips", "Collect the loose slips", "Gather slips", "You slide the loose slips under the spring clip. The wind won't get another one."],
	],
	"station": [
		["Service check", "Ring for the attendant", "Ring bell", "Two taps answer on the other side of the shutter. Pike's in there with the oil stove."],
		["Night key", "Check the night-drop slot", "Check slot", "You ease a curled tag through the slot. The ring of keys lands on the mat inside."],
	],
	"lutheran": [
		["Neighbor check", "Read the call sheet", "Read sheet", "Each name has a pencil tick. The last one says that Ruth is staying with her sister."],
		["Vestry pickup", "Gather the empty jars", "Gather jars", "Three empty soup jars, nested in a towel. You stow them upright behind the seat."],
	],
	"bell": [
		["Bus count", "Read the driver's slip", "Read slip", "Fourteen out, fourteen home. You fold the little slip back along its crease."],
		["Bus barrier", "Set the barrier flag", "Set flag", "You pull the red cloth free of the packed snow. A bus driver can see it from the turn now."],
	],
	"kroll": [
		["Milk pickup", "Read the milk hauler's tag", "Read tag", "The brass tag has been flipped to EMPTY. The milk truck made its round."],
		["Frozen latches", "Free the rack latch", "Free latch", "A sharp pull lifts the hasp. You turn it twice so the hauler can get it open in gloves."],
	],
	"quarry": [
		["Salt count", "Check the salt docket", "Read docket", "Two loads out since the last count. The foreman's pencil is tied to the box with bale twine."],
		["Hopper check", "Check the hopper tally", "Check tally", "The tally wheel has moved. There'll be enough screenings for the next truck."],
	],
	"sugar": [
		["Syrup tally", "Read the crate tag", "Read tag", "Five empties out, five washed jugs back. The pencil has a piece of twine through it."],
		["Empty bottles", "Check the bottle count", "Count jugs", "A folded towel keeps the clean bottles from knocking against one another."],
	],
	"dairy": [
		["Hauler check", "Check the hauler's receipt", "Read slip", "A wet thumbprint on the carbon. The milk truck got here before the drift closed in."],
		["Can covers", "Latch the can covers", "Latch lids", "The last lid takes a push with your elbow. It'll hold till the morning pickup."],
	],
	"grain": [
		["Moisture ticket", "Collect the sample slip", "Take slip", "The grain sample's marked dry. You fold the slip inside your glove."],
		["Scale pickup", "Gather the loose carbons", "File slips", "You put the pink copies behind the clip. One still smells of diesel."],
	],
	"garage": [
		["Wrecker check", "Ring for the mechanic", "Ring bell", "A wrench taps the inside of the shutter. The mechanic's keeping warm."],
		["Parts pickup", "Check the pickup tag", "Read tag", "A wheel bearing for the county truck. The parts man has already signed the tag."],
	],
	"hall": [
		["Call list", "Check the neighbor list", "Read list", "Every house has a tick beside it. Two families are sharing a stove."],
		["Supper count", "Read the supper count", "Read sheet", "There's a penciled number and a note to save two plates for the plow drivers."],
	],
	"pump": [
		["Water pressure", "Read the pressure card", "Read gauge", "The needle holds steady. You pencil the reading on the card inside the cover."],
		["Pump call", "Check the running light", "Check lamp", "A steady green light. With your glove against the post you can feel the pump running."],
	],
	"orchard": [
		["Apple crates", "Count the empties", "Count crates", "Three crates stacked rim to rim. Somebody tucked the receipt under a slat."],
		["Stand shutter", "Secure the storm catch", "Set catch", "The catch drops into place. The shutter quits banging in the wind."],
	],
	"timber": [
		["Chain tally", "Count the spare chains", "Count chains", "Four skidding chains on the pegs. The fifth peg has a fresh coat of frost."],
		["Landing check", "Read the load tag", "Read tag", "Two loads of pulpwood crossed off in blue pencil. The driver signed for both."],
	],
	"fire": [
		["Locker check", "Check the seal number", "Check seal", "The numbered wire is intact. You copy the last four digits onto Deb's slip."],
		["Crew call", "Read the duty card", "Read card", "A relief crew is already in. Someone wrote thanks under the duty roster."],
	],
	"freight": [
		["Waybill run", "File the loose waybills", "File bills", "The carbons are still legible. You put them under the clip in load order."],
		["Dock tally", "Read the last delivery", "Read tally", "Six pallets landed and the dockman initialed the count. Everything's under cover."],
	],
}

const WINDROWS := {
	"mill": "Bader's loader left a fresh pile in the loading bay.",
	"station": "Pike just pushed the wrecker lot. The last ridge is in the bay.",
	"lutheran": "The caretaker scraped the steps and piled the snow in the loading bay.",
	"bell": "The school crew pushed a ridge into the bus turnaround.",
	"kroll": "Kroll got the manure spreader out. There's a tractor pile in the yard now.",
	"quarry": "The loader left another ridge where the grit trucks turn.",
	"beck": "Mr. Beck cleaned up with the garden tractor. The propane truck needs the pile moved.",
	"sugar": "Somebody pulled a tractor out by the sugarhouse and left a ridge.",
	"dairy": "The barnyard loader blocked the hauler's bay.",
	"grain": "There's a fresh pile where the grain trucks unload.",
	"garage": "The shop crew shoved a ridge into the turnaround.",
	"hall": "The caretaker's piled snow where they unload the supper pots.",
	"pump": "The service crew left a pile where the pump truck backs in.",
	"orchard": "Their tractor left a hump beside the crate stand.",
	"timber": "The log loader pushed snow across the landing.",
	"fire": "The crew scraped the apron and the last pile still needs moving.",
	"freight": "There's a loader ridge across the dock bay.",
}

const PLOW_REQUESTS := {
	"beck": "The Becks have propane coming. Their truck needs the whole lane.",
	"mill": "Bader's got a grain truck coming to weigh in.",
	"station": "Pike needs the approach open for his wrecker.",
	"lutheran": "They're loading soup pots at St. Luke's for the folks on the east line.",
	"bell": "The school bus swings wide. Give the driver a clean run to the barrier.",
	"kroll": "The milk is up in the tank again. Let's get the hauler up to Kroll's.",
	"quarry": "They've got grit enough. They need a way in to load it.",
	"sugar": "They're bringing a load of stove wood up to the sugarhouse.",
	"dairy": "The bulk tank's full. Get the milk hauler a clean run.",
	"grain": "The grain truck needs a way through to the bins.",
	"garage": "There's a wrecker coming in with a car on the hook.",
	"hall": "They have soup kettles going out for the neighbors.",
	"pump": "The pump tender is coming through with a load of pipe.",
	"orchard": "They need room to get a truck to the apple crates.",
	"timber": "The pulp truck's due at the landing.",
	"fire": "The volunteers want the lane ready for the tanker.",
	"freight": "There's a freight load coming that can't turn in the snow.",
}

const SHIPPING_DESKS := {
	"grain": "mill", "freight": "mill", "hall": "lutheran", "fire": "station",
	"garage": "station", "dairy": "kroll", "timber": "kroll",
}
const DELIVERY_TYPES := {
	"ticket": ["grain", "dairy", "freight", "timber"],
	"grit": ["pump", "fire", "hall", "orchard", "garage"],
	"coffee": ["fire", "garage", "freight", "sugar", "timber"],
	"flares": ["fire", "freight", "garage", "timber"],
	"mitts": ["sugar", "timber", "pump", "orchard", "dairy"],
}
static var _route_lengths: Dictionary = {}
var _senders: Dictionary[String, String] = {}
var _receivers: Dictionary[String, Array] = {}

var completed := 0
var job: Dictionary = {}
var lane_is_open: Callable

var rng := RandomNumberGenerator.new()
var _work_bag: Array[String] = []
var _last_site := ""
var _previous_site := ""
var _site_counts: Dictionary = {}
var _visits: Dictionary = {}
var _opened: Dictionary = {}
var _freight_destination := ""
var _freight_origin := ""


func _init(shift_seed: int = -1) -> void:
	if shift_seed == -1:
		rng.randomize()
	else:
		rng.seed = shift_seed
	for id: String in Route.SITES:
		var archetype: String = Route.SITES[id].archetype
		if HAULS.has(id):
			_senders[id] = id
		elif SHIPPING_DESKS.has(archetype):
			_senders[id] = SHIPPING_DESKS[archetype]
	for desk: String in HAULS:
		var info: Dictionary = HAULS[desk]
		var recipients: Array = info.receivers.duplicate()
		for id: String in Route.SITES:
			if Route.SITES[id].archetype in DELIVERY_TYPES[info.cargo] and not id in recipients:
				recipients.append(id)
		_receivers[desk] = recipients


static func fixture_for(id: String) -> String:
	return Route.SITES[id].fixture


func start_shift() -> void:
	if job.is_empty():
		_next_order()


func finish_stop() -> Dictionary:
	if job.is_empty():
		return {}
	var response := {"speaker": job.speaker, "text": job.reply}
	_previous_site = _last_site
	_last_site = job.site
	_site_counts[_last_site] = int(_site_counts.get(_last_site, 0)) + 1
	if job.leg < job.legs:
		_delivery()
		return response

	if job.kind == "plow":
		_opened[job.site] = true
	completed += 1
	_next_order()
	return response


func _next_order() -> void:
	# A shuffled round gives each work type a turn without lengthy dry spells.
	if _work_bag.is_empty():
		_work_bag.assign(["haul", "windrow", "plow", "visit"])
		for i in range(_work_bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var held := _work_bag[i]
			_work_bag[i] = _work_bag[j]
			_work_bag[j] = held
		if not job.is_empty() and _work_bag.back() == job.kind:
			_work_bag.reverse()
	var kind: String = _work_bag.pop_back()
	if kind == "plow":
		var available := []
		for id: String in Route.SITES:
			if _opened.has(id) or (lane_is_open.is_valid() and lane_is_open.call(id)):
				continue
			if id != _last_site:
				available.append(id)
		if not available.is_empty():
			_start_plow(_next_site(available))
			return
		kind = "windrow" if job.is_empty() or job.kind != "windrow" else "haul"

	if kind == "windrow":
		_start_windrow(_next_site(Route.SITES.keys()))
	elif kind == "haul":
		var origin := _next_site(_senders.keys())
		_start_haul(origin, _next_site(_receivers[_senders[origin]], origin))
	else:
		_start_visit(_next_site(Route.SITES.keys()))


# Most jobs follow a local run. Occasional county-wide calls move the driver
# between districts, with less-visited properties first in either pool.
func _next_site(options: Array, pickup: String = "") -> String:
	var departure := _last_site if pickup.is_empty() else pickup
	var reachable := options.duplicate()
	reachable.erase(departure)
	for recent in [_last_site, _previous_site]:
		if reachable.size() > 1:
			reachable.erase(recent)
	if reachable.size() > 4 and rng.randf() < .85:
		var lengths := _distances_from(departure)
		reachable.sort_custom(func(a: String, b: String) -> bool: return lengths[a] < lengths[b])
		reachable.resize(4)
	var picks: Array[String] = []
	var best := -1
	for id: String in reachable:
		var count := int(_site_counts.get(id, 0))
		if picks.is_empty() or count < best:
			picks.clear()
			best = count
		if count == best:
			picks.append(id)
	return picks[rng.randi_range(0, picks.size() - 1)]


static func _distances_from(id: String) -> Dictionary:
	if not _route_lengths.has(id):
		var start := Vector2(0, Route.HOME_Z) if id.is_empty() else Vector2(Route.SITES[id].mouth)
		var lengths := {}
		for other: String in Route.SITES:
			lengths[other] = Route.driving_distance(start, Route.SITES[other].mouth)
		_route_lengths[id] = lengths
	return _route_lengths[id]


func _start_haul(origin: String, destination: String) -> void:
	_freight_origin = origin
	_freight_destination = destination
	var load_info: Dictionary = HAULS[_senders[origin]]
	var pickup: String = fixture_for(origin)
	var source: String = Route.SITES[origin].name
	var recipient: String = Route.SITES[destination].name
	job = {
		"site": origin, "kind": "haul", "leg": 1, "legs": 2,
		"title": String(load_info.item).capitalize() + " run",
		"brief": "Swing by %s. There's a %s by %s to take over to %s." % [source, load_info.item, pickup, recipient],
		"instruction": "Pick up the %s at %s." % [load_info.item, pickup],
		"action": load_info.take, "speaker": source.to_upper(), "reply": load_info.packed,
	}


func _delivery() -> void:
	var load_info: Dictionary = HAULS[_senders[_freight_origin]]
	var site_name: String = Route.SITES[_freight_destination].name
	var instruction := "Leave the %s at %s." % [load_info.item, fixture_for(_freight_destination)]
	job = {
		"site": _freight_destination, "kind": "haul", "leg": 2, "legs": 2, "cargo": load_info.cargo,
		"title": job.title, "brief": "Got it? Take it over to %s. %s" % [site_name, instruction],
		"instruction": instruction, "action": load_info.give, "speaker": site_name.to_upper(),
		"reply": load_info.delivered,
	}


func _start_plow(id: String) -> void:
	var site_name: String = Route.SITES[id].name
	job = {
		"site": id, "kind": "plow", "leg": 1, "legs": 1, "title": "Open the approach",
		"brief": "%s Open the lane at %s from %s, then sign off by %s." % [PLOW_REQUESTS[Route.SITES[id].archetype], site_name, Route.SITES[id].road, fixture_for(id)],
		"instruction": "Plow from the road to the yard. Sign off at %s." % fixture_for(id),
		"action": "Sign off", "speaker": site_name.to_upper(),
		"reply": "You pencil the time on the plow slip. There's room to bring a truck all the way in.",
	}


func _start_visit(id: String) -> void:
	var calls: Array = SITE_CALLS[Route.SITES[id].archetype]
	var visits := int(_visits.get(id, rng.randi_range(0, calls.size() - 1)))
	var call_info: Array = calls[visits % calls.size()]
	_visits[id] = visits + 1
	var site_name: String = Route.SITES[id].name
	var instruction := "%s at %s." % [call_info[1], fixture_for(id)]
	job = {
		"site": id, "kind": "visit", "leg": 1, "legs": 1, "title": call_info[0],
		"brief": "I could use your eyes over at %s. %s" % [site_name, instruction],
		"instruction": instruction, "action": call_info[2], "speaker": site_name.to_upper(), "reply": call_info[3],
	}


func _start_windrow(id: String) -> void:
	var site_name: String = Route.SITES[id].name
	job = {
		"site": id, "kind": "windrow", "leg": 1, "legs": 1, "title": "Clear the loading bay",
		"brief": "%s Push it through the orange stakes at %s. Sign off by %s." % [WINDROWS[Route.SITES[id].archetype], site_name, fixture_for(id)],
		"instruction": "Plow the pile between the orange stakes. Sign off at %s." % fixture_for(id),
		"action": "Sign off", "speaker": site_name.to_upper(),
		"reply": "You hang the work tag back on its hook. The loading bay's clear.",
	}
