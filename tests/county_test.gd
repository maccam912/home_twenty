extends SceneTree

const Route = preload("res://world/route.gd")
const Snow = preload("res://world/plowed_snow.gd")
const Township = preload("res://world/township.gd")
const Roadside = preload("res://world/roadside.gd")
var failures := PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func expect(condition: bool, explanation: String) -> void:
	if not condition:
		failures.append(explanation)

func _run() -> void:
	var snow := Snow.new()
	var town := Township.new()
	root.add_child(snow)
	root.add_child(town)
	await physics_frame
	await physics_frame
	_check_survey()
	_check_roadside_spacing()
	# Sample the entire expansion from junction to junction. A collider or
	# a two-metre gap here can strand every contract beyond the broken road.
	for road: Dictionary in Route.ROADS:
		_check_corridor(snow, town, road.a, road.b, road.name)
	for id: String in Route.SITES:
		var site: Dictionary = Route.SITES[id]
		_check_corridor(snow, town, site.mouth, site.yard, site.name)
		var blade_path := Route.pile_path(id)
		_check_corridor(snow, town, blade_path[0], blade_path[1], site.name + " plow bay")
		var heading: Vector2 = site.mouth.direction_to(site.yard)
		snow.stop_pass()
		for i in range(ceili(site.mouth.distance_to(site.yard)) * 2):
			var point: Vector2 = site.mouth + heading * i * .5
			snow.cut(Vector3(point.x,0,point.y), Vector3(heading.x,0,heading.y))
		expect(snow.lane_opened(id) == Route.lane_length(id), "A through pass must finish the job at " + site.name)
		for other: Dictionary in Route.SITES.values():
			var a: Vector2 = other.mouth
			var b: Vector2 = site.mouth
			var path := Route._road_path(a, b)
			expect(not path.is_empty() and path[0] == a and path[-1] == b, "Missing road directions between %s and %s" % [other.name, site.name])
			for n in range(1, path.size()):
				var street := Route._street_between(path[n-1],path[n])
				expect(not street.is_empty(), "Navigation crossed an open field on the route to " + site.name)
			var words := Route.directions(other.yard, id)
			expect(site.landmark in words, "CB directions should identify the destination at " + site.name)
			expect(words.length() < 280, "Long CB routes should give the next turns and ask for a callback")
		expect(site.yard.distance_to(site.stop) < 12, "The outdoor handoff should be near the parking area at " + site.name)
	expect(snow.open_length() == Route.FULL_LANE, "Working the section loop must preserve the original Beck cutting")
	town.free()
	snow.free()
	if failures.is_empty():
		print("PASS: both 12.8 km county crossings, 35 physical approaches and plow bays, and 1,225 public-road routes")
	else:
		for failure in failures:
			push_error(failure)
	quit(int(not failures.is_empty()))

func _check_corridor(snow: Snow, town: Township, a: Vector2, b: Vector2, label: String) -> void:
	var space := town.get_world_3d().direct_space_state
	var side := a.direction_to(b).orthogonal()
	for lateral: float in [-1.15, 0.0, 1.15]:
		var p := a + side * lateral
		var q := b + side * lateral
		var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x,1.2,p.y),Vector3(q.x,1.2,q.y),1)
		expect(space.intersect_ray(ray).is_empty(), "Truck clearance blocked on " + label)
		var steps := maxi(1, ceili(a.distance_to(b) / 2))
		for i in range(steps+1):
			var sample := p.lerp(q, float(i)/steps)
			if not snow.on_surface(sample):
				expect(false, "Missing snow on " + label)
				break
			if absf(Roadside.height_at(sample.x,sample.y)) > .02:
				expect(false, "A drainage ditch cuts the signed approach at " + label)
				break

func _check_roadside_spacing() -> void:
	# A quarter mile is a spacing measure. The weather controls what the cab can see.
	var points: Array[Vector2] = [Route.HOME_PORCH, Vector2(9.3, Route.COOP_Z)]
	for site: Dictionary in Route.SITES.values():
		points.append(site.yard)
	for landmark: Dictionary in Route.LANDMARKS:
		points.append(landmark.position)
	var samples := 0
	var empty := 0
	var solitary := 0
	var longest_gap := 0
	const STEP := 20
	for road: Dictionary in Route.ROADS:
		var start: Vector2 = road.a
		var end: Vector2 = road.b
		var heading := start.direction_to(end)
		var gap := 0
		for metres in range(0, roundi(start.distance_to(end)), STEP):
			var position := start + heading * metres
			var nearby := 0
			for point in points:
				if position.distance_squared_to(point) <= 400.0 * 400.0:
					nearby += 1
			samples += 1
			if nearby <= 1:
				solitary += 1
			if nearby == 0:
				empty += 1
				gap += STEP
				longest_gap = maxi(longest_gap, gap)
			else:
				gap = 0
	expect(solitary >= samples * .9, "Most road should have at most one property or landmark within 400 metres")
	expect(empty >= samples * .4, "Open country should occupy a substantial share of the road")
	expect(longest_gap >= 1800, "At least one stretch should give the driver over a minute of open country at full speed")

func _check_survey() -> void:
	expect(Route.SITES.size() >= 35, "The county must offer its outer holdings and the central contracts")
	for road: Dictionary in Route.ROADS:
		if road.kind == "county":
			expect(is_equal_approx(Route.driving_distance(road.a,road.b),12800), "The signed thoroughfare must run eight miles edge to edge")
	var bound := Route.COUNTY_BOUNDS
	expect(bound.size == Vector2(12800,12800), "Plow country must span eight miles in both axes")
	var road_distance := Route.driving_distance(Vector2(-3000,4400), Vector2(-3000,800))
	expect(is_equal_approx(road_distance,6900), "Cross-field positions need the shorter road around the marsh")
	var middle := Route.directions(Vector2(-1460,800),"dahl")
	expect("east on County H" in middle, "Deb must name the east-west road when a path midpoint falls on Q")
	for mark: Dictionary in Route.LANDMARKS:
		var near := Route._nearest_road(mark.position)
		var offset: float = mark.position.distance_to(Route._projection(mark.position,near))
		expect(bound.has_point(mark.position) and offset > 10 and offset < 100, "Unreachable roadside landmark " + mark.name)
	for id: String in Route.SITES:
		var site: Dictionary = Route.SITES[id]
		expect(bound.has_point(site.yard) and bound.has_point(site.stop), "Outdoor work lies beyond the survey for " + id)
		expect(not site.fixture.is_empty() and not site.archetype.is_empty() and site.region == Route.region_at(site.mouth),
			"Work slips, atlas and scenery need the same survey at " + id)
	var strips := Route.surfaces()
	for i in strips.size():
		var first := Rect2(strips[i][0],strips[i][1]-strips[i][0])
		for j in range(i+1,strips.size()):
			var second := Rect2(strips[j][0],strips[j][1]-strips[j][0])
			var overlap := first.intersection(second)
			expect(minf(overlap.size.x,overlap.size.y) < .001, "Two surfaces cover the same stretch of road")
