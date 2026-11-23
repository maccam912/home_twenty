extends RefCounted

const Route = preload("res://world/route.gd")

# Recipient pools keep the paperwork, equipment and food going somewhere that uses them.
const HAULS := {
	"mill": {"cargo": "ticket", "title": "Scale ticket run", "item": "scale ticket", "take": "Take ticket", "give": "File ticket",
		"packed": "The ticket's folded around a carbon. There's a greasy thumbprint on both copies.",
		"delivered": "You file the carbon in the outside clip and keep the driver's copy.",
		"receivers": ["station", "kroll", "quarry", "beck"]},
	"quarry": {"cargo": "grit", "title": "Grit delivery", "item": "bag of grit", "take": "Load grit", "give": "Unload grit",
		"packed": "You tip a canvas sack over the tailgate. The grit rattles all the way to the bottom.",
		"delivered": "You leave the grit within reach of the steps, with the tied end up.",
		"receivers": ["bell", "station", "lutheran", "beck"]},
	"lutheran": {"cargo": "coffee", "title": "Coffee round", "item": "coffee jug", "take": "Take jug", "give": "Leave coffee",
		"packed": "There's a gingham sock over the jug to keep it warm. Smells like somebody made it strong.",
		"delivered": "You tuck the jug out of the wind. Two enamel cups hang from the handle.",
		"receivers": ["quarry", "mill", "station", "beck"]},
	"station": {"cargo": "flares", "title": "Flare delivery", "item": "tin of flares", "take": "Load flares", "give": "Leave flares",
		"packed": "You take the red tin. Somebody printed DRY SIDE UP on both sides.",
		"delivered": "You set the flare tin under cover where the road crew can reach it.",
		"receivers": ["bell", "quarry", "mill"]},
	"kroll": {"cargo": "mitts", "title": "Dry mitts", "item": "pair of mitts", "take": "Take mitts", "give": "Leave mitts",
		"packed": "Dry choppers, still warm in their brown paper bag. Somebody packed wool liners too.",
		"delivered": "You hang the bag high enough to stay out of the drift.",
		"receivers": ["station", "quarry", "mill"]},
	"pump": {"cargo": "cells", "title": "Lantern batteries", "item": "box of lantern cells", "take": "Load cells", "give": "Leave cells",
		"packed": "Four square batteries in a beer flat. There's masking tape over the springs so they won't touch.",
		"delivered": "You put the cells where a hand can find them in the dark. The dead ones are lined up beside them.",
		"receivers": ["bell", "station", "quarry"]},
	"orchard": {"cargo": "apples", "title": "Winter apples", "item": "crate of keepers", "take": "Load apples", "give": "Leave apples",
		"packed": "There's newspaper between the layers of apples. One in the corner is wrapped by itself, marked DEB.",
		"delivered": "You set the apples inside the windbreak and slip Deb's into your coat pocket.",
		"receivers": ["beck", "lutheran"]},
	"sugar": {"cargo": "kindling", "title": "Dry kindling", "item": "bundle of kindling", "take": "Take bundle", "give": "Stack wood",
		"packed": "The split ends are dry under the bark. You lift the bundle by its two loops of baler twine.",
		"delivered": "You slide the bundle under cover. Someone kept the Sunday paper to start it with.",
		"receivers": ["lutheran", "station", "beck"]},
}

# A returning driver gets a different visit at the same fixture.
const SITE_CALLS := {
	"beck": [
		["Propane reading", "Collect the tank reading", "Take reading", "Mrs. Beck has penciled the gauge reading on a feed envelope. You tuck it in your pocket for the supplier."],
		["Porch call", "Knock at the porch", "Knock", "Mrs. Beck knocks twice on the glass and holds up her coffee cup. They're warm and doing fine."],
		["Kitchen smoke", "Check on the kitchen stove", "Knock twice", "A kettle starts whistling as Mrs. Beck opens the door. She heard the flue go quiet and worried the snow had capped it."],
	],
	"mill": [
		["Truck tally", "Read the tally card", "Read tally", "Six trucks through the scales. Bader penciled a little star beside the one that made it up the hill."],
		["Scale slips", "Collect the loose slips", "Gather slips", "You slide the loose slips under the spring clip. The wind won't get another one."],
		["Feed pickup", "Pin up the feed pickup copy", "Pin copy", "You pin the green copy high and dry. The penciled order is for one bag of chick starter."],
	],
	"station": [
		["Service check", "Ring for the attendant", "Ring bell", "Two taps answer on the other side of the shutter. Pike's in there with the oil stove."],
		["Night key", "Check the night-drop slot", "Check slot", "You ease a curled tag through the slot. The ring of keys lands on the mat inside."],
		["Wrecker keys", "Free the key-drop flap", "Free flap", "A skin of ice comes away on your glove. The flap swings and settles with a tin click."],
	],
	"lutheran": [
		["Neighbor check", "Read the call sheet", "Read sheet", "Each name has a pencil tick. The last one says that Ruth is staying with her sister."],
		["Vestry pickup", "Gather the empty jars", "Gather jars", "Three empty soup jars, nested in a towel. You stow them upright behind the seat."],
		["Soup roster", "Mark off the soup route", "Mark roster", "The ladies have tied a bag of oyster crackers to each handle. You count the pots and tick the last name."],
	],
	"bell": [
		["Bus count", "Read the driver's slip", "Read slip", "Fourteen out, fourteen home. You fold the little slip back along its crease."],
		["Bus barrier", "Set the barrier flag", "Set flag", "You pull the red cloth free of the packed snow. A bus driver can see it from the turn now."],
		["Last bus home", "Check the bus driver's note", "Read note", "The note is written on the back of a spelling test. All the kids got off, even the little one who slept through his stop."],
	],
	"kroll": [
		["Milk pickup", "Read the milk hauler's tag", "Read tag", "The brass tag has been flipped to EMPTY. The milk truck made its round."],
		["Frozen latches", "Free the rack latch", "Free latch", "A sharp pull lifts the hasp. You turn it twice so the hauler can get it open in gloves."],
		["Milk run", "Turn the pickup tag", "Turn tag", "You turn the red face toward the road. The next hauler will see it before he backs in."],
	],
	"quarry": [
		["Salt count", "Check the salt docket", "Read docket", "Two loads out since the last count. The foreman's pencil is tied to the box with bale twine."],
		["Hopper check", "Check the hopper tally", "Check tally", "The tally wheel has moved. There'll be enough screenings for the next truck."],
		["Sand for the hill", "Reserve the next load", "Mark load", "You slip the county's chit under the brass weight. One bucket of sand set aside for the hill."],
	],
	"sugar": [
		["Syrup tally", "Read the crate tag", "Read tag", "Five empties out, five washed jugs back. The pencil has a piece of twine through it."],
		["Empty bottles", "Check the bottle count", "Count jugs", "A folded towel keeps the clean bottles from knocking against one another."],
		["Boiler watch", "Check for the fire tender's note", "Read note", "He went to supper at four. The back of the note says he's back, in a different pencil."],
	],
	"dairy": [
		["Hauler check", "Check the hauler's receipt", "Read slip", "A wet thumbprint on the carbon. The milk truck got here before the drift closed in."],
		["Can covers", "Latch the can covers", "Latch lids", "The last lid takes a push with your elbow. It'll hold till the morning pickup."],
		["Clean strainers", "Gather the filter sleeves", "Gather sleeves", "Clean cotton strainers rolled up in a flour sack. You tuck them under the cover for the morning crew."],
	],
	"grain": [
		["Moisture ticket", "Collect the sample slip", "Take slip", "The grain sample's marked dry. You fold the slip inside your glove."],
		["Scale pickup", "Gather the loose carbons", "File slips", "You put the pink copies behind the clip. One still smells of diesel."],
		["Sample tags", "Tie down the sample tags", "Tie tags", "You thread the wire back through the eyelet. None of these samples will lose its name in the wind."],
	],
	"garage": [
		["Wrecker check", "Ring for the mechanic", "Ring bell", "A wrench taps the inside of the shutter. The mechanic's keeping warm."],
		["Parts pickup", "Check the pickup tag", "Read tag", "A wheel bearing for the county truck. The parts man has already signed the tag."],
		["Shop call", "Check on the tow driver", "Ring bell", "A man raises one greasy hand behind the glass. You can just make out a pair of boots warming by the stove."],
	],
	"hall": [
		["Call list", "Check the neighbor list", "Read list", "Every house has a tick beside it. Two families are sharing a stove."],
		["Supper count", "Read the supper count", "Read sheet", "There's a penciled number and a note to save two plates for the plow drivers."],
		["Blanket count", "Check the blanket list", "Count rolls", "Seven wool blankets rolled up with their army stamps showing. Three cots still need bedding."],
	],
	"pump": [
		["Water pressure", "Read the pressure card", "Read gauge", "The needle holds steady. You pencil the reading on the card inside the cover."],
		["Pump call", "Check the running light", "Check lamp", "A steady green light. With your glove against the post you can feel the pump running."],
		["Relief shift", "Read the pump tender's initials", "Read card", "Fresh initials below a row of frozen ones. Somebody made it in to relieve the night man."],
	],
	"orchard": [
		["Apple crates", "Count the empties", "Count crates", "Three crates stacked rim to rim. Somebody tucked the receipt under a slat."],
		["Stand shutter", "Secure the storm catch", "Set catch", "The catch drops into place. The shutter quits banging in the wind."],
		["Storm cover", "Tie the stand cover back down", "Tie cover", "You pull a corner tight and loop the cord over a nail. The old blue tarp settles against the crates."],
	],
	"timber": [
		["Chain tally", "Count the spare chains", "Count chains", "Four skidding chains on the pegs. The fifth peg has a fresh coat of frost."],
		["Landing check", "Read the load tag", "Read tag", "Two loads of pulpwood crossed off in blue pencil. The driver signed for both."],
		["Cable receipt", "File the cable receipt", "File receipt", "One coil of cable signed for. You fold the yellow copy into the tab on the rack."],
	],
	"fire": [
		["Locker check", "Check the seal number", "Check seal", "The numbered wire is intact. You copy the last four digits onto Deb's slip."],
		["Crew call", "Read the duty card", "Read card", "A relief crew is already in. Someone wrote thanks under the duty roster."],
		["Lantern count", "Read the lantern tags", "Read tags", "Three lanterns checked out. One is across the street with the woman whose pilot light blew out."],
	],
	"freight": [
		["Waybill run", "File the loose waybills", "File bills", "The carbons are still legible. You put them under the clip in load order."],
		["Dock tally", "Read the last delivery", "Read tally", "Six pallets landed and the dockman initialed the count. Everything's under cover."],
		["Dry freight", "Check the tarp seal", "Check seal", "You work a glove under the flap. The brown paper there is still bone dry."],
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
	"pump": "pump", "orchard": "orchard", "sugar": "sugar",
}
const DELIVERY_TYPES := {
	"ticket": ["grain", "dairy", "freight", "timber"],
	"grit": ["pump", "fire", "hall", "orchard", "garage"],
	"coffee": ["fire", "garage", "freight", "sugar", "timber"],
	"flares": ["fire", "freight", "garage", "timber"],
	"mitts": ["sugar", "timber", "pump", "orchard", "dairy"],
	"cells": ["garage", "fire", "hall", "freight", "dairy", "timber"],
	"apples": ["hall", "fire", "freight", "dairy", "grain"],
	"kindling": ["garage", "dairy", "fire", "hall", "freight", "timber"],
}
# Dispatch works a little over a mile at a time. On a sparse outer road there
# must still be at least one neighbor, even beyond the usual working radius.
const LOCAL_RUN := 1950.0
const NEIGHBOR_MARGIN := 550.0
const ADJOINING_RUN := 3000.0
const PRIORITY_CALLS := [
	{"after": 3, "properties": 3, "site": "station", "fixture": "the outside payphone", "stop": Route.PHONE,
		"title": "Pike’s outside line",
		"brief": "This one first, hon. Pike can hear the payphone ringing from inside his shop. He can't leave the lift. Would you get it?",
		"instruction": "Answer the outside payphone beside the pump canopy.",
		"action": "Pick up phone", "speaker": "PAYPHONE",
		"reply": "The heater fan in your own cab comes through the receiver. Then Deb, close to your ear. “Why won't you answer the radio, hon?”",
		"followup": "I haven't used the phone, hon. I've been right here on nineteen."},
	{"after": 8, "properties": 5, "site": "bell", "fixture": "the district noticeboard", "stop": Route.NOTICE,
		"title": "The extra bus stop",
		"brief": "Hold the list a minute. The school driver says somebody put a stop back on her route. Can you read me the sheet on Bell's noticeboard?",
		"instruction": "Read the route sheet on the noticeboard beside the school barrier.",
		"action": "Lift route sheet", "speaker": "DISTRICT NOTICEBOARD",
		"reply": "The top sheet lists today's stops. Penciled on the one underneath: PINERY RD. · ONE CHILD. The paper is dated December 1958.",
		"followup": "Pinery Road? Hang on. I've got my book open. There isn't a line there."},
]

static var _distances_by_site: Dictionary = {}
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
var _next_priority := 0


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


static func stop_for(order: Dictionary) -> Vector2:
	return order.get("stop", Route.SITES[order.site].stop)


static func stop_fixture(order: Dictionary) -> String:
	return order.get("fixture", fixture_for(order.site))


func start_shift(from: Vector2 = Route.HOME_PARK) -> void:
	if job.is_empty():
		_next_order(_local_calls(_distances(from, "")))


func finish_stop(driver_at: Vector2 = Vector2.INF) -> Dictionary:
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
	var followup: String = job.get("followup", "")
	var lengths := _site_distances(_last_site) if not driver_at.is_finite() else _distances(driver_at, _last_site)
	if not _take_priority(lengths):
		_next_order(_local_calls(lengths))
	if not followup.is_empty():
		job.brief = followup + " " + job.brief
	return response


func _take_priority(lengths: Dictionary) -> bool:
	if _next_priority >= PRIORITY_CALLS.size():
		return false
	var call_info: Dictionary = PRIORITY_CALLS[_next_priority]
	if completed < call_info.after or _site_counts.size() < call_info.properties:
		return false
	# Hold the slip if the truck is across the county or already at this yard.
	if lengths.get(call_info.site, INF) > ADJOINING_RUN * 1.5:
		return false
	job = call_info.duplicate()
	job.merge({"kind": "story", "leg": 1, "legs": 1})
	_next_priority += 1
	return true


func _next_order(nearby: Array) -> void:
	# Draw work types without replacement. Ineligible contracts stay on Deb's
	# county list: an open lane or a long freight run is no reason to leave town.
	if _work_bag.is_empty():
		_work_bag.assign(["haul", "windrow", "plow", "visit"])
		for i in range(_work_bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var held := _work_bag[i]
			_work_bag[i] = _work_bag[j]
			_work_bag[j] = held
		if not job.is_empty() and _work_bag.back() == job.kind:
			_work_bag.reverse()

	while not _work_bag.is_empty():
		var kind: String = _work_bag.pop_back()
		match kind:
			"plow":
				var uncleared := nearby.filter(func(id: String) -> bool:
					return not _opened.has(id) and not (lane_is_open.is_valid() and lane_is_open.call(id)))
				if not uncleared.is_empty():
					_start_plow(_pick(uncleared))
					return
			"haul":
				var runs := {}
				for id: String in nearby:
					if _senders.has(id):
						var receivers := _local_calls(_site_distances(id)).filter(func(other: String) -> bool: return other in _receivers[_senders[id]])
						if not receivers.is_empty():
							runs[id] = receivers
				if not runs.is_empty():
					var pickup := _pick(runs.keys())
					_start_haul(pickup, _pick(runs[pickup]))
					return
			"windrow":
				_start_windrow(_pick(nearby))
				return
			"visit":
				_start_visit(_pick(nearby))
				return
	# The last type in this round was unavailable. Start a fresh round.
	_next_order(nearby)


static func _site_distances(id: String) -> Dictionary:
	if not _distances_by_site.has(id):
		_distances_by_site[id] = _distances(Route.SITES[id].mouth, id)
	return _distances_by_site[id]


static func _distances(from: Vector2, exclude: String) -> Dictionary:
	var lengths := {}
	for id: String in Route.SITES:
		if id != exclude:
			lengths[id] = Route.driving_distance(from, Route.SITES[id].mouth)
	return lengths


func _local_calls(lengths: Dictionary) -> Array:
	var nearest := float(lengths.values().min())
	var limit := maxf(nearest, clampf(nearest + NEIGHBOR_MARGIN, LOCAL_RUN, ADJOINING_RUN))
	var local := lengths.keys().filter(func(id: String) -> bool: return lengths[id] <= limit)
	var fewest := INF
	for id: String in local:
		fewest = minf(fewest, _site_counts.get(id, 0))
	# Once the immediate district has had its turn, allow a less-served
	# neighbor just across the line. Even those hops stay under two miles.
	if fewest > 0:
		for id: String in lengths:
			if lengths[id] > limit and lengths[id] <= ADJOINING_RUN and _site_counts.get(id, 0) < fewest:
				local.append(id)
	return local


func _pick(options: Array) -> String:
	var picks: Array[String] = []
	var best := INF
	for id: String in options:
		# Prefer a fresh property, especially over immediately retracing a leg.
		var cost := float(_site_counts.get(id, 0))
		if id == _last_site or id == _previous_site:
			cost += 2.0
		if cost < best:
			picks.clear()
			best = cost
		if cost == best:
			picks.append(id)
	return picks[rng.randi_range(0, picks.size() - 1)]


func _start_haul(origin: String, destination: String) -> void:
	_freight_origin = origin
	_freight_destination = destination
	var load_info: Dictionary = HAULS[_senders[origin]]
	var pickup: String = fixture_for(origin)
	var source: String = Route.SITES[origin].name
	var recipient: String = Route.SITES[destination].name
	job = {
		"site": origin, "kind": "haul", "leg": 1, "legs": 2,
		"title": load_info.title,
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
