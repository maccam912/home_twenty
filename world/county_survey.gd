extends RefCounted

# Survey coordinates in metres. Keep the working Q section in the middle of
# the county and leave a mile or two of open land between outlying holdings.
const BOUNDS := Rect2(-6400, -6400, 12800, 12800)
const ROADS := [
	{"name": "County Q", "a": Vector2(0,-6400), "b": Vector2(0,6400), "kind": "county"},
	{"name": "Mill Road", "a": Vector2(0,-1780), "b": Vector2(640,-1780), "kind": "town"},
	{"name": "Line Road", "a": Vector2(640,-1780), "b": Vector2(640,-720), "kind": "town"},
	{"name": "School Road", "a": Vector2(0,-720), "b": Vector2(640,-720), "kind": "town"},
	{"name": "County H", "a": Vector2(-6400,800), "b": Vector2(6400,800), "kind": "county"},
	{"name": "Alder Road", "a": Vector2(-4650,-4460), "b": Vector2(4730,-4460), "kind": "town"},
	{"name": "Cranberry Road", "a": Vector2(-4650,-4460), "b": Vector2(-4650,4400), "kind": "town"},
	{"name": "Church Line", "a": Vector2(4730,-4460), "b": Vector2(4730,4400), "kind": "town"},
	{"name": "Creamery Road", "a": Vector2(-4650,4400), "b": Vector2(4730,4400), "kind": "town"},
]

# Markers used in the paper atlas, CB directions, and roadside scenery.
const LANDMARKS := [
	{"name": "Line water tower", "kind": "water_tower", "position": Vector2(664,-1798), "road": "Mill Road"},
	{"name": "Pinery lookout", "kind": "lookout", "position": Vector2(-39,-4950), "road": "County Q"},
	{"name": "Cranberry trestle", "kind": "trestle", "position": Vector2(-4688,-2130), "road": "Cranberry Road"},
	{"name": "Heller lime kiln", "kind": "kiln", "position": Vector2(-465,-4425), "road": "Alder Road"},
	{"name": "Aermotor windmill", "kind": "windmill", "position": Vector2(-4770,764), "road": "County H"},
	{"name": "Marsh elevator", "kind": "elevator", "position": Vector2(-2820,4436), "road": "Creamery Road"},
	{"name": "Wayside chapel", "kind": "chapel", "position": Vector2(4764,4110), "road": "Church Line"},
]

const ARCHETYPES := {
	"sugar": ["the sugarhouse chimney", "the syrup crate"],
	"dairy": ["the red milking barn", "the milk-can stand"],
	"grain": ["the corrugated bins", "the grain ticket box"],
	"garage": ["the double shop doors", "the service bell"],
	"hall": ["the meeting hall flagpole", "the notice case"],
	"pump": ["the blue pump shed", "the meter box"],
	"orchard": ["the rows of apple trees", "the produce stand"],
	"timber": ["the stack of sawlogs", "the chain rack"],
	"fire": ["the tall hose tower", "the equipment locker"],
	"freight": ["the raised freight dock", "the bill box"],
}

# Contract, owner, building, street, station along the street, signed lane length.
# On a vertical road positive lane length leads east; on a horizontal road it leads south.
const HOLDINGS := [
	["spruce", "Spruce River Landing", "timber", "County Q", -6060, -75],
	["moen", "Moen Sugar Bush", "sugar", "County Q", -3770, 63],
	["union", "Union Grange", "hall", "County Q", 1880, -62],
	["rush", "Rush Creek Waterworks", "pump", "County Q", 2950, 52],
	["south_fire", "South Fork Fire Co.", "fire", "County Q", 5960, -58],
	["goose", "Goose Siding", "freight", "County H", -6050, 85],
	["lind", "Lind Orchard", "orchard", "County H", -5330, -81],
	["mink", "Mink Hollow Dairy", "dairy", "County H", -3180, 74],
	["reese", "Reese Repair", "garage", "County H", -1200, -52],
	["dahl", "Dahl Transfer", "freight", "County H", 1460, 63],
	["east_hall", "East Line Hall", "hall", "County H", 3690, -69],
	["hudson", "Hudson Grain", "grain", "County H", 5830, 83],
	["alder", "Alder Freight House", "freight", "Alder Road", -3930, -62],
	["pinery_fire", "Pinery Fire Co.", "fire", "Alder Road", -1820, 56],
	["tamarack", "Tamarack Maple", "sugar", "Alder Road", 1280, -93],
	["torp", "Torp Dairy", "dairy", "Alder Road", 3560, 84],
	["brekke", "Brekke Sugar Camp", "sugar", "Cranberry Road", -3470, -102],
	["sandhill", "Sandhill Lift Station", "pump", "Cranberry Road", -1230, 57],
	["marsh_hall", "West Marsh Hall", "hall", "Cranberry Road", 2190, -79],
	["kirsch", "Kirsch Orchard", "orchard", "Cranberry Road", 3650, 104],
	["paulsen", "Paulsen Timber", "timber", "Church Line", -3200, 112],
	["nelson", "Nelson Garage", "garage", "Church Line", -1020, -49],
	["fairbanks", "Fairbanks Grain", "grain", "Church Line", 2050, 77],
	["clover", "Clover Bend Dairy", "dairy", "Church Line", 3450, -90],
	["borg", "Borg Seed", "grain", "Creamery Road", -3830, 66],
	["fox", "Fox Meadow Orchard", "orchard", "Creamery Road", -1720, -96],
	["fork", "Fork Cartage", "freight", "Creamery Road", 1430, -72],
	["maplewood", "Maplewood Town Hall", "hall", "Creamery Road", 3420, 74],
]

static func region_at(p: Vector2) -> String:
	if absf(p.x) < 1700 and p.y > -2600 and p.y < 1600:
		return "Q Section"
	if p.y < 800:
		return "Pinery" if p.x <= 0 else "Tamarack"
	return "West Marsh" if p.x < 0 else "South Fork"

static func sites(original: Dictionary) -> Dictionary:
	var all := original.duplicate(true)
	for site: Dictionary in all.values():
		site.region = region_at(site.mouth)
	var streets := {}
	for road: Dictionary in ROADS:
		streets[road.name] = road
	for holding: Array in HOLDINGS:
		var road: Dictionary = streets[holding[3]]
		var length := float(holding[5])
		var mouth := Vector2(road.a.x,holding[4]) if road.a.x == road.b.x else Vector2(holding[4],road.a.y)
		var lane := Vector2(length,0) if road.a.x == road.b.x else Vector2(0,length)
		var yard := mouth + lane
		var side := lane.normalized().orthogonal()
		var archetype: String = holding[2]
		all[holding[0]] = {
			"name": holding[1], "road": road.name, "archetype": archetype, "region": region_at(mouth),
			"mouth": mouth, "yard": yard, "stop": yard + side * 6.0,
			"landmark": ARCHETYPES[archetype][0], "fixture": ARCHETYPES[archetype][1],
		}
	return all
