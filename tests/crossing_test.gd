extends "res://tests/shift_smoke.gd"

# Run a full township crossing at the normal physics rate. This catches road
# gaps and old world-edge colliders that a distance measurement would miss.
func _run() -> void:
	shift = load("res://game/shift.tscn").instantiate()
	root.add_child(shift)
	current_scene = shift
	await process_frame
	shift.begin_shift()
	var county_h: Dictionary
	for road: Dictionary in Route.ROADS:
		if road.name == "County H":
			county_h = road
			break
	var start: Vector2 = county_h.a
	var end: Vector2 = county_h.b
	var truck: CharacterBody3D = shift.driver._truck
	truck.position = Vector3(start.x, 0, start.y + 1.6)
	truck.rotation.y = -PI / 2
	var elapsed := 0
	var peak_tiles := 0
	var hz := Engine.physics_ticks_per_second
	_key(KEY_W, true)
	while truck.position.x < end.x and elapsed < 620 * hz:
		await physics_frame
		elapsed += 1
		if elapsed % hz == 0:
			peak_tiles = maxi(peak_tiles, shift.snow.visible_tiles.size())
			if shift.driver.stuck or (elapsed > 5 * hz and shift.driver.speed_mps < 0.1):
				break
	_key(KEY_W, false)
	var seconds := float(elapsed) / hz
	check(truck.position.x >= end.x, "Truck reached the east end of County H from its west boundary")
	check(seconds > 550 and seconds < 620, "An uninterrupted blade-up county crossing takes roughly ten minutes")
	check(peak_tiles < 240, "The truck streams nearby snow throughout the crossing")
	print("Driven crossing: %.2f km in %.1f game seconds, peak %d visible snow tiles." % [start.distance_to(end) / 1000.0, seconds, peak_tiles])
	await _finish()
