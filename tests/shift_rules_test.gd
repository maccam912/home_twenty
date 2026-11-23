extends "res://tests/shift_smoke.gd"

const Roadside = preload("res://world/roadside.gd")

# Job and recovery rules complement the separate complete keyboard playthrough.
func _run() -> void:
	shift = load("res://game/shift.tscn").instantiate()
	root.add_child(shift)
	current_scene = shift
	await process_frame
	# Use a known opening deal to exercise a recurrent loading-bay contract.
	shift.dispatch.rng.seed = 218
	shift.begin_shift()
	var driver = shift.driver
	var order: Dictionary = shift.dispatch.job
	check(order.kind == "windrow", "Test deal starts with a loading-bay call")
	var site: Dictionary = Route.SITES[order.site]
	var path := Route.pile_path(order.site)
	var bay = shift.loading_bays[order.site]
	var truck_at: Vector2 = path[0].lerp(path[1], .5)
	driver._truck.global_position = Vector3(truck_at.x, 0, truck_at.y)
	shift.check_job()
	check(shift.dispatch.completed == 0 and shift.hud.speaker == "IN THE CAB", "Handoffs require getting out")
	await _tap(KEY_E)
	driver._walker.global_position = Vector3(Route.HOME_PORCH.x, 0, Route.HOME_PORCH.y)
	shift.check_job()
	check(shift.dispatch.job == order and shift.field_action_label().is_empty(), "Visiting home has no effect on the active job")
	driver._walker.global_position = Vector3(site.stop.x, 0, site.stop.y)
	shift.check_job()
	check(shift.hud.subtitle.contains("orange stakes") and shift.dispatch.completed == 0, "Checking in before clearing the marked bay leaves the order open")
	# A partial pass at the far end cannot complete the assigned ridge. Clearing
	# the rest joins both pieces. The next drop of snow leaves the base lane alone.
	var heading := path[0].direction_to(path[1])
	var forward := Vector3(heading.x, 0, heading.y)
	for i in range(32, 65):
		var at := path[0] + heading * i * .125
		bay.cut(Vector3(at.x, 0, at.y), forward)
	shift.update_job_progress()
	check(shift.hud.opened == 0, "An isolated cut at the back of the loading bay is incomplete")
	for i in range(34):
		var at := path[0] + heading * i * .125
		bay.cut(Vector3(at.x, 0, at.y), forward)
	shift.update_job_progress()
	check(shift.hud.opened == shift.hud.target_length and shift.hud.opened == 8, "A continuous blade width satisfies the bay")
	shift.check_job()
	check(shift.dispatch.completed == 1 and shift.dispatch.job.site != order.site, "The outdoor sign-off gives the driver a new destination")
	shift.check_job()
	check(shift.dispatch.completed == 1, "A second tap at the previous stop cannot turn in the next job")
	shift.snow.cut(Vector3(truck_at.x, 0, truck_at.y), forward)
	var trail: float = shift.snow.clearance(truck_at)
	bay.deposit(14)
	check(bay.open_metres() == 0 and trail > .9 and shift.snow.clearance(truck_at) == trail, "Fresh loader snow preserves the existing cut beneath it")
	driver.cold=.99999
	await physics_frame
	await physics_frame
	check(driver.in_cab and driver.cold<.4,"Cold collapse recovers in the cab")
	check(shift.hud.subtitle.contains("heater"),"Collapse gives a recovery cue")
	var before_warmup:float = driver.cold
	for i in 12:
		await physics_frame
	check(driver.cold<before_warmup,"The heater steadily restores warmth")
	var next_site: Dictionary = Route.SITES[shift.dispatch.job.site]
	driver._truck.global_position = Vector3(truck_at.x, 0, truck_at.y)
	shift.directions()
	check(shift.hud.subtitle.contains(next_site.name), "CB directs the driver from the old job to the next property")
	driver._truck.global_position = Vector3(next_site.yard.x, 0, next_site.yard.y)
	shift.directions()
	check(shift.hud.subtitle == shift._onsite_instruction(), "Deb switches to field instructions on arrival")
	await _test_shoulder_crossing()
	await _test_fast_runoff()
	print("Shift rules: outdoor handoffs, loading bay, cold, radio directions, ditch crossing and powered recovery; failures: ",failures)
	await _finish()


func _test_shoulder_crossing() -> void:
	var driver = shift.driver
	var truck: CharacterBody3D = driver._truck
	var space := truck.get_world_3d().direct_space_state
	for sample: Vector2 in [Vector2(-8.9,-440), Vector2(8.9,-440), Vector2(-8.9,Route.HOME_Z), Vector2(8.9,Route.BECK_Z)]:
		var at := Vector3(sample.x, 0, sample.y)
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 3.0)
		var hit := space.intersect_ray(ray)
		var ground := Roadside.height_at(sample.x, sample.y)
		check(not hit.is_empty() and absf(hit.position.y - ground) < .08, "The first collidable ground at %s matches the visible road profile" % sample)
		check(ground < -.25 if sample.y == -440 else absf(ground) < .02, "Both ditches dip below grade and both farm entrances bridge them")
	truck.global_position = Vector3(1.6, 0, -440)
	truck.rotation = Vector3(0, -PI / 3.0, 0)
	await _tap(KEY_C)
	await _tap(KEY_B)
	var pitch := 0.0
	var roll := 0.0
	var blade_clearance := INF
	_key(KEY_W, true)
	for tick in 240:
		await physics_frame
		pitch = maxf(pitch, absf(truck.rotation.x))
		roll = maxf(roll, absf(truck.rotation.z))
		var edge: Vector3 = driver.get_blade_position()
		blade_clearance = minf(blade_clearance, edge.y - Roadside.height_at(edge.x, edge.z))
		if truck.position.x >= 8.9:
			break
	_key(KEY_W, false)
	check(truck.position.y < -.22 and pitch > .06 and roll > .04, "Driving diagonally off Q lowers and banks the chassis with the swale")
	check(blade_clearance > -.02, "The lowered plow floats over the rising bank")
	var cab_seat := truck.to_local(root.get_camera_3d().global_position)
	check(cab_seat.distance_to(Vector3(-.475, 1.76, -.287)) < .01, "The cab camera follows the seat through pitch and roll")
	await _tap(KEY_E)
	var foot: Vector3 = driver.get_driver_position()
	check(not driver.in_cab and foot.y < -.18 and absf(foot.y - Roadside.height_at(foot.x, foot.z)) < .02, "Exiting a banked truck puts the driver on the ditch floor")
	_key(KEY_W, true)
	for tick in 125:
		await physics_frame
	_key(KEY_W, false)
	var field: Vector3 = driver.get_driver_position()
	check(field.x > foot.x + 4.7 and field.y > foot.y + .12, "Walking up the outside bank reaches the field")
	_key(KEY_S, true)
	for tick in 125:
		await physics_frame
	_key(KEY_S, false)
	await _tap(KEY_E)
	check(driver.in_cab, "The driver can return to the truck from the ditch")
	_key(KEY_S, true)
	for tick in 360:
		await physics_frame
		if truck.position.x < 1.8:
			break
	_key(KEY_S, false)
	check(truck.position.x < 2 and absf(truck.position.y) < .02 and truck.basis.y.dot(Vector3.UP) > .999, "Reversing out of the ditch returns the truck to level road")


func _test_fast_runoff() -> void:
	var driver = shift.driver
	var truck: CharacterBody3D = driver._truck
	truck.global_position = Vector3(0.0, 0.0, -540.0)
	truck.rotation = Vector3.ZERO
	await _tap(KEY_B)  # Raise the blade after the low-speed crossing.
	_key(KEY_W, true)
	for tick in 650:
		await physics_frame
	check(shift.hud.mph == 50 and shift.hud.low_grip, "County Q allows 50 mph and shows the low-grip speed range")
	_key(KEY_D, true)
	for tick in 240:
		await physics_frame
		if driver.offroad_fraction == 1.0 and driver.speed_mps <= driver.FIELD_SPEED:
			break
	_key(KEY_D, false)
	_key(KEY_W, false)
	check(driver.offroad_fraction == 1.0 and driver.speed_mps > 0.0 and driver.speed_mps <= driver.FIELD_SPEED, "A fast turn off Q carries the truck into deep snow and slows it to a crawl")
	shift.directions()
	check(shift.hud.subtitle.contains("wheels straight") and shift.hud.subtitle.contains(Route.SITES[shift.dispatch.job.site].name), "Deb gives both a traction tip and the route from deep snow")
	_key(KEY_S, true)
	for tick in 600:
		await physics_frame
		if absf(truck.position.x) < 2.0:
			break
	_key(KEY_S, false)
	check(driver.in_cab and absf(truck.position.x) < 2.0 and driver.offroad_fraction == 0.0, "The driver can back onto County Q and regain road traction from inside the cab")
