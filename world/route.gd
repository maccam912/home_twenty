extends RefCounted

# World coordinates are metres. County Q follows the north-south section line.
const Survey = preload("res://world/county_survey.gd")
const COUNTY_BOUNDS := Survey.BOUNDS
const ROAD_NORTH_Z := COUNTY_BOUNDS.position.y
const ROAD_SOUTH_Z := COUNTY_BOUNDS.end.y
const HOME_Z := 38.0
const BECK_Z := -1572.0
const COOP_Z := -880.0
const HOME_HOUSE := Vector3(-96.0, 0.0, HOME_Z)
const BECK_HOUSE := Vector3(124.5, 0.0, BECK_Z + 13.4)
const HOME_PORCH := Vector2(-89.0, HOME_Z)
const BECK_PORCH := Vector2(122.0, BECK_Z + 8.0)
const HOME_PARK := Vector2(-76.0, HOME_Z)
const BECK_PARK := Vector2(124.0, BECK_Z)
const BECK_MAILBOX := Vector3(5.8, 0.0, BECK_Z + 4.9)
const TANK := Vector3(125.0, 0.0, BECK_Z - 6.0)
# Ground positions of the tank centre and the mailbox timber under its overhanging door.
const SNOW_CONTACTS := Vector4(TANK.x, TANK.z, BECK_MAILBOX.x + .05, BECK_MAILBOX.z - .13)
const FIRST_SLICE := 4
const LAST_SLICE := 117
const FULL_LANE := LAST_SLICE - FIRST_SLICE + 1

# Public centerlines, used by the folded plat and Deb's directions.
const ROADS := Survey.ROADS
const LANDMARKS := Survey.LANDMARKS
const CORE_SITES := {
	"beck": {"archetype": "beck", "fixture": "the Beck porch", "name": "Beck Farm", "road": "County Q", "mouth": Vector2(0, BECK_Z), "yard": BECK_PARK, "stop": BECK_PORCH, "landmark": "the Beck mailbox"},
	"mill": {"archetype": "mill", "fixture": "the scale box", "name": "Bader Feed Mill", "road": "Mill Road", "mouth": Vector2(210, -1780), "yard": Vector2(210, -1850), "stop": Vector2(216, -1850), "landmark": "the twin grain bins"},
	"station": {"archetype": "station", "fixture": "the service bell", "name": "Pike Service", "road": "Mill Road", "mouth": Vector2(470, -1780), "yard": Vector2(470, -1729), "stop": Vector2(464, -1729), "landmark": "the striped pump canopy"},
	"lutheran": {"archetype": "lutheran", "fixture": "the church box", "name": "St. Luke’s", "road": "Line Road", "mouth": Vector2(640, -1460), "yard": Vector2(572, -1460), "stop": Vector2(572, -1454), "landmark": "the little white steeple"},
	"bell": {"archetype": "bell", "fixture": "the school barrier", "name": "Bell School", "road": "School Road", "mouth": Vector2(448, -720), "yard": Vector2(448, -652), "stop": Vector2(442, -652), "landmark": "the yellow bus shelter"},
	"kroll": {"archetype": "kroll", "fixture": "the milk-can rack", "name": "Kroll Dairy", "road": "School Road", "mouth": Vector2(182, -720), "yard": Vector2(182, -787), "stop": Vector2(188, -787), "landmark": "the red dairy barn"},
	"quarry": {"archetype": "quarry", "fixture": "the scale box", "name": "Town Gravel Pit", "road": "County Q", "mouth": Vector2(0, -2120), "yard": Vector2(82, -2120), "stop": Vector2(82, -2126), "landmark": "the gravel hopper"},
}
const PHONE := Vector2(479, -1725)
const NOTICE := Vector2(458, -652)
const LANE_START := 6 # metres from the road centre, clear of the turn
const YARD_MARGIN := 7

static var SITES: Dictionary = Survey.sites(CORE_SITES)
static var _road_graph := AStar2D.new()
static var _node_ids: Dictionary[Vector2,int] = {}
static var _street_nodes: Dictionary[String, PackedVector2Array] = {}
static var _junctions := PackedVector2Array()

static func region_at(p: Vector2) -> String:
	return Survey.region_at(p)

static func pile_path(site_id: String) -> PackedVector2Array:
	var site: Dictionary = SITES[site_id]
	var along: Vector2 = site.mouth.direction_to(site.yard)
	var side := -1.0 if not CORE_SITES.has(site_id) or site_id in ["beck", "quarry", "lutheran"] else 1.0
	var center: Vector2 = site.yard + along.orthogonal() * side * 3.3
	return PackedVector2Array([center - along * 4, center + along * 4])

static func lane_length(site_id: String) -> int:
	if site_id == "beck":
		return FULL_LANE
	var site: Dictionary = SITES[site_id]
	return roundi(site.mouth.distance_to(site.yard)) - YARD_MARGIN - LANE_START + 1

static func road_half_width(road_name: String) -> float:
	return 4.3 if road_name.begins_with("County ") else 3.6

# Return nonoverlapping public strips, including the full width of the road
# around bends. Earlier roads own the shared snow in the middle of junctions.
static func _public_strips() -> Array[Rect2]:
	var strips: Array[Rect2] = []
	for road: Dictionary in ROADS:
		var a: Vector2 = road.a
		var b: Vector2 = road.b
		var wide := road_half_width(road.name)
		var axis := a.direction_to(b)
		var side := axis.orthogonal().abs() * wide
		if roads_at(a).size() > 1:
			a -= axis * wide
		if roads_at(b).size() > 1:
			b += axis * wide
		var low := a.min(b) - side
		var pieces: Array[Rect2] = [Rect2(low,a.max(b)+side-low)]
		for used in strips:
			var remainder: Array[Rect2] = []
			for piece in pieces:
				var cut := piece.intersection(used)
				if not cut.has_area():
					remainder.append(piece)
					continue
				# Top/bottom take full width. The two sides occupy the middle band.
				for part: Rect2 in [
					Rect2(piece.position,Vector2(piece.size.x,cut.position.y-piece.position.y)),
					Rect2(Vector2(piece.position.x,cut.end.y),Vector2(piece.size.x,piece.end.y-cut.end.y)),
					Rect2(Vector2(piece.position.x,cut.position.y),Vector2(cut.position.x-piece.position.x,cut.size.y)),
					Rect2(Vector2(cut.end.x,cut.position.y),Vector2(piece.end.x-cut.end.x,cut.size.y))]:
					if part.has_area():
						remainder.append(part)
			pieces = remainder
		strips.append_array(pieces)
	return strips

static func surfaces() -> Array:
	var bounds := [
		[Vector2(4.3, BECK_Z - 2.7), Vector2(118.0, BECK_Z + 2.7)],
		[Vector2(118.0, BECK_Z - 12.5), Vector2(138.0, BECK_Z + 6.0)],
		[Vector2(-78.0, HOME_Z - 2.8), Vector2(-4.3, HOME_Z + 2.8)],
		[Vector2(-91.0, HOME_Z - 8.5), Vector2(-78.0, HOME_Z + 8.5)],
	]
	for strip in _public_strips():
		bounds.append([strip.position, strip.end])
	for id: String in SITES:
		if id == "beck":
			continue # The original tanker yard has an asymmetric apron.
		var site: Dictionary = SITES[id]
		var mouth: Vector2 = site.mouth
		var yard: Vector2 = site.yard
		var direction := mouth.direction_to(yard)
		var start := mouth + direction * road_half_width(site.road)
		var end := yard - direction * YARD_MARGIN
		var shoulder := direction.orthogonal().abs() * 3.15
		bounds.append([start.min(end) - shoulder, start.max(end) + shoulder])
		var apron_end := yard + direction * 10
		var apron_side := direction.orthogonal().abs() * 9
		bounds.append([end.min(apron_end) - apron_side, end.max(apron_end) + apron_side])
	return bounds

static func _projection(p: Vector2, road: Dictionary) -> Vector2:
	var a: Vector2 = road.a
	var b: Vector2 = road.b
	return p.clamp(a.min(b), a.max(b))

static func roads_at(p: Vector2) -> Array[Dictionary]:
	var roads: Array[Dictionary] = []
	for road: Dictionary in ROADS:
		if p.distance_squared_to(_projection(p, road)) < .00001:
			roads.append(road)
	return roads

static func _nearest_road(p: Vector2) -> Dictionary:
	var best: Dictionary = ROADS[0]
	var distance := INF
	for road: Dictionary in ROADS:
		var d := p.distance_squared_to(_projection(p, road))
		if d < distance:
			distance = d
			best = road
	return best

static func _in_lane(p: Vector2, start: Vector2, end: Vector2) -> bool:
	var on_lane := Geometry2D.get_closest_point_to_segment(p, start, end)
	return p.distance_to(on_lane) < 10 and start.distance_to(on_lane) > 5

static func area_at(p: Vector2) -> String:
	if _in_lane(p, Vector2(0, BECK_Z), BECK_PARK):
		return "BECK LANE"
	if _in_lane(p, Vector2(0, HOME_Z), HOME_PORCH):
		return "HOME PLACE"
	for site: Dictionary in SITES.values():
		if _in_lane(p, site.mouth, site.yard):
			return site.name.to_upper()
	var road := _nearest_road(p)
	return road.name.to_upper() if p.distance_to(_projection(p, road)) < 9 else "OPEN COUNTRY"

static func junctions() -> PackedVector2Array:
	_prepare_graph()
	return _junctions

static func _add_node(point: Vector2) -> void:
	if not _node_ids.has(point):
		var id := _node_ids.size()
		_node_ids[point] = id
		_road_graph.add_point(id, point)

# Include interior intersections as well as T intersections and bends.
# Sorting by survey station makes every permanent node share its road edges.
static func _prepare_graph() -> void:
	if not _node_ids.is_empty():
		return
	for road: Dictionary in ROADS:
		_add_node(road.a)
		_add_node(road.b)
		if road.a.x == road.b.x:
			for crossroad: Dictionary in ROADS:
				if crossroad.a.y == crossroad.b.y:
					var crossing := Vector2(road.a.x, crossroad.a.y)
					if crossing == _projection(crossing, road) and crossing == _projection(crossing, crossroad):
						_junctions.append(crossing)
						_add_node(crossing)
	for site: Dictionary in SITES.values():
		_add_node(site.mouth)
	_add_node(Vector2(0, HOME_Z))
	for road: Dictionary in ROADS:
		var ordered: Array[Vector2] = []
		for p: Vector2 in _node_ids:
			if p == _projection(p, road):
				ordered.append(p)
		ordered.sort() # All street definitions run west to east or north to south.
		_street_nodes[road.name] = PackedVector2Array(ordered)
		for i in range(1, ordered.size()):
			_road_graph.connect_points(_node_ids[ordered[i-1]], _node_ids[ordered[i]])

static func _at_station(p: Vector2, road: Dictionary) -> int:
	if _node_ids.has(p):
		return _node_ids[p]
	var stations := _street_nodes[String(road.name)]
	var i := stations.bsearch(p)
	var id := _road_graph.get_available_point_id()
	_road_graph.add_point(id,p)
	if i > 0:
		_road_graph.connect_points(id,_node_ids[stations[i-1]])
	if i < stations.size():
		_road_graph.connect_points(id,_node_ids[stations[i]])
	return id

static func _road_path(start: Vector2, end: Vector2) -> PackedVector2Array:
	_prepare_graph()
	var first := _nearest_road(start)
	var last := _nearest_road(end)
	start = _projection(start, first)
	end = _projection(end, last)
	if start == end:
		return PackedVector2Array([start])
	if _projection(start, last) == start or _projection(end, first) == end:
		return PackedVector2Array([start,end])
	# Mid-block radio calls temporarily attach to the two nearest permanent
	# stations. The stored graph stays small across any number of dispatches.
	var a := _at_station(start, first)
	var b := _at_station(end, last)
	var path := _road_graph.get_point_path(a,b)
	if not _node_ids.has(start):
		_road_graph.remove_point(a)
	if not _node_ids.has(end):
		_road_graph.remove_point(b)
	return path

static func driving_distance(from_mouth: Vector2, to_mouth: Vector2) -> float:
	var path := _road_path(from_mouth, to_mouth)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i-1].distance_to(path[i])
	return length

static func _bearing(a: Vector2, b: Vector2) -> String:
	var delta := b - a
	if absf(delta.x) > absf(delta.y):
		return "east" if delta.x > 0 else "west"
	return "south" if delta.y > 0 else "north"

static func _distance_phrase(metres: float) -> String:
	if metres < 550:
		return ""
	if metres < 1160:
		return " for about half a mile"
	if metres < 2020:
		return " for about a mile"
	if metres < 2700:
		return " for a mile and a half"
	return " for about %d miles" % roundi(metres / 1609.344)

# A segment midpoint can land exactly on a crossing. Require both stations
# on the same street when naming a run through that intersection.
static func _street_between(a: Vector2, b: Vector2) -> Dictionary:
	for road: Dictionary in ROADS:
		if _projection(a,road) == a and _projection(b,road) == b:
			return road
	return {}

static func _wayside(a: Vector2, b: Vector2, road: Dictionary) -> String:
	var nearest := INF
	var landmark := ""
	for mark: Dictionary in LANDMARKS:
		if mark.road != road.name:
			continue
		var station := _projection(mark.position, road)
		var along := (station-a).dot(a.direction_to(b))
		if along >= 30 and along < a.distance_to(b)-20 and along < nearest:
			nearest = along
			landmark = mark.name
	return landmark

static func directions(from: Vector2, site_id: String) -> String:
	var site: Dictionary = SITES[site_id]
	var near := _nearest_road(from)
	var start := _projection(from, near)
	if _in_lane(from, site.mouth, site.yard):
		if site_id == "beck":
			return "You’re past the Beck mailbox. The tank and the porch are at the far end."
		return "You’re in the drive for %s. Go on to %s." % [site.name, site.landmark]
	var path := _road_path(start, site.mouth)
	var lines := PackedStringArray()
	var previous_heading := Vector2.ZERO
	if from.distance_to(start) > 12:
		previous_heading = from.direction_to(start)
		lines.append("Come %s to %s." % [_bearing(from,start),near.name])
	var i := 1
	var legs := 0
	var passed_landmark := false
	while i < path.size():
		var a := path[i-1]
		var b := path[i]
		var heading := a.direction_to(b)
		var road := _street_between(a,b)
		# Crossing a side road doesn't interrupt a run on the same street.
		while i+1 < path.size() and heading.dot(b.direction_to(path[i+1])) > .999:
			i += 1
			b = path[i]
		var cross := previous_heading.cross(heading)
		var action := "Go" if absf(cross) < .75 else ("Turn right," if cross > 0 else "Turn left,")
		var phrase := "%s %s on %s%s" % [action,_bearing(a,b),road.name,_distance_phrase(a.distance_to(b))]
		if not passed_landmark:
			var wayside := _wayside(a,b,road)
			if not wayside.is_empty():
				phrase += ", past the " + wayside
				passed_landmark = true
		lines.append(phrase + ".")
		previous_heading = heading
		legs += 1
		i += 1
		if legs == 2 and i < path.size():
			lines.append("Key me again on %s. It’s %s, by %s." % [road.name,site.name,site.landmark])
			return " ".join(lines)
	var turn := previous_heading.cross(site.mouth.direction_to(site.yard))
	var direction := _bearing(site.mouth, site.yard)
	if absf(turn) > .75:
		direction = "right" if turn > 0 else "left"
	if Survey.BUSINESS_SIGNS.has(site_id):
		lines.append("Turn %s by %s. That's %s, with %s back in the yard." % [direction, Survey.BUSINESS_SIGNS[site_id].mark, site.name, site.landmark])
	else:
		lines.append("Turn %s at %s for %s." % [direction, site.landmark, site.name])
	return " ".join(lines)
