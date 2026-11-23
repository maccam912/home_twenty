extends "res://tests/shift_smoke.gd"

const Roadside = preload("res://world/roadside.gd")

# Job and recovery rules complement the separate complete keyboard playthrough.
func _run() -> void:
	shift = load("res://game/shift.tscn").instantiate()
	root.add_child(shift)
	current_scene = shift
	await process_frame
	shift.begin_shift()
	var driver = shift.driver
	check(absf((Route.HOME_Z - Route.BECK_Z) - 1609.344) < 80, "The mile in Deb’s directions agrees with the road distance")
	# An unreported job must never silently complete simply because a porch is nearby.
	driver._truck.global_position = Vector3(Route.BECK_PARK.x, 0, Route.BECK_Z)
	shift.check_job()
	check(shift.stage==0 and shift.hud.speaker=="IN THE CAB","House interactions require getting out")
	await _tap(KEY_E)
	driver._walker.global_position = Vector3(Route.BECK_PORCH.x, 0, Route.BECK_PORCH.y)
	shift.check_job()
	check(shift.stage==0 and shift.hud.speaker=="AT THE BECKS’ DOOR","Mrs. Beck checks lane completion")
	driver._walker.global_position = Vector3(Route.HOME_PORCH.x, 0, Route.HOME_PORCH.y)
	shift.check_job()
	check(shift.stage==0 and shift.hud.speaker.begins_with("DEB"),"Home stays visitable before the first contract is done")
	shift.stage = 1
	shift.check_job()
	check(shift.stage==1,"The wrong porch cannot advance the welfare check")
	driver._walker.global_position = Vector3(Route.BECK_PORCH.x, 0, Route.BECK_PORCH.y)
	shift.check_job()
	check(shift.stage==2 and shift.hud.speaker.begins_with("MRS. BECK"),"Delivery leads to the right conversation")
	shift.check_job()
	check(shift.stage==2,"Repeating a knock doesn't duplicate the job")
	driver._walker.global_position = Vector3(Route.HOME_PORCH.x, 0, Route.HOME_PORCH.y)
	shift.check_job()
	check(shift.stage==3,"Only a visit home completes the return")
	driver.cold=.99999
	await physics_frame
	await physics_frame
	check(driver.in_cab and driver.cold<.4,"Cold collapse recovers in the cab")
	check(shift.hud.subtitle.contains("heater"),"Collapse gives a recovery cue")
	var before_warmup:float = driver.cold
	for i in 12:
		await physics_frame
	check(driver.cold<before_warmup,"The heater steadily restores warmth")
	shift.stage = 0
	for example: Array in [[Vector3(0,0,36),"co-op"],[Vector3(0, 0, Route.BECK_Z - 40),"south"],[Vector3(18, 0, Route.BECK_Z),"Lower the blade"],[Vector3(-23,0,-25),"telephone poles"],[Vector3(0,0,Route.COOP_Z),"half a mile"]]:
		driver._truck.global_position=example[0]
		shift.directions()
		check(shift.hud.subtitle.contains(example[1]),"Dispatch follows the truck's location at %s" % example[0])
	shift.stage=2
	driver._truck.global_position=Vector3(18, 0, Route.BECK_Z)
	shift.directions()
	check(shift.hud.subtitle.contains("left"),"Return dispatch changes with job stage")
	await _test_shoulder_crossing()
	print("Shift rules: porch gates, cold, warmth, radio directions and ditch crossing; failures: ",failures)
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
