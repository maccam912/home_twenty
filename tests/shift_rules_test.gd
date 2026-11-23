extends "res://tests/shift_smoke.gd"

# Job and recovery rules complement the separate complete keyboard playthrough.
func _run() -> void:
	shift = load("res://game/shift.tscn").instantiate()
	root.add_child(shift)
	current_scene = shift
	await process_frame
	shift.begin_shift()
	var driver = shift.driver
	# An unreported job must never silently complete simply because a porch is nearby.
	driver._truck.global_position = Vector3(43,0,-33)
	shift.check_job()
	check(shift.stage==0 and shift.hud.speaker=="IN THE CAB","House interactions require getting out")
	await _tap(KEY_E)
	driver._walker.global_position = Vector3(43,0,-30)
	shift.check_job()
	check(shift.stage==0 and shift.hud.speaker=="AT THE BECKS’ DOOR","Mrs. Beck checks lane completion")
	driver._walker.global_position = Vector3(-12,0,38)
	shift.check_job()
	check(shift.stage==0 and shift.hud.speaker.begins_with("DEB"),"Home stays visitable before the first contract is done")
	shift.stage = 1
	shift.check_job()
	check(shift.stage==1,"The wrong porch cannot advance the welfare check")
	driver._walker.global_position = Vector3(43,0,-30)
	shift.check_job()
	check(shift.stage==2 and shift.hud.speaker.begins_with("MRS. BECK"),"Delivery leads to the right conversation")
	shift.check_job()
	check(shift.stage==2,"Repeating a knock doesn't duplicate the job")
	driver._walker.global_position = Vector3(-12,0,38)
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
	for example: Array in [[Vector3(0,0,36),"co-op"],[Vector3(0,0,-80),"south"],[Vector3(18,0,-38),"Lower the blade"],[Vector3(-23,0,-25),"telephone poles"]]:
		driver._truck.global_position=example[0]
		shift.directions()
		check(shift.hud.subtitle.contains(example[1]),"Dispatch follows the truck's location at %s" % example[0])
	shift.stage=2
	driver._truck.global_position=Vector3(18,0,-38)
	shift.directions()
	check(shift.hud.subtitle.contains("left"),"Return dispatch changes with job stage")
	print("Shift rules: porch gates, cold, warmth, radio route branches; failures: ",failures)
	await _finish()
