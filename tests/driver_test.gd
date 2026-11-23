extends SceneTree

const Driver = preload("res://vehicle/driver.gd")

var driver := Driver.new()
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func ticks(count: int) -> void:
	for i in count:
		await physics_frame


func reset_truck(speed := 0.0) -> void:
	# Begin on County Q. Each test supplies wheel contact and snow load explicitly.
	driver._truck.global_position = Vector3.ZERO
	driver._truck.rotation = Vector3.ZERO
	driver.speed_mps = speed
	driver._truck.velocity = Vector3.FORWARD * speed
	driver._steering = 0.0
	driver.snow_load = 0.0
	driver.offroad_fraction = 0.0
	driver.blade_down = false


func measure_slip(speed: float) -> float:
	reset_truck(speed)
	Input.action_press("accelerate", speed / Driver.ROAD_SPEED)
	Input.action_press("steer_right")
	await ticks(90)
	var slip := driver.get_forward().slide(Vector3.UP).angle_to(driver._truck.velocity)
	check(absf(driver._truck.rotation.y) > 0.35, "Steering still changes heading at %.1f m/s" % speed)
	Input.action_release("steer_right")
	await ticks(180)
	check(driver.get_forward().slide(Vector3.UP).angle_to(driver._truck.velocity) < 0.03, "The tires settle when the wheel straightens")
	Input.action_release("accelerate")
	return slip


func braking_distance(speed: float) -> float:
	reset_truck(speed)
	Input.action_press("reverse")
	for i in 240:
		await physics_frame
		if driver.speed_mps <= 0.0:
			break
	check(driver.speed_mps <= 0.0, "Brake input stops the truck from %.1f m/s" % speed)
	var distance := -driver.get_truck_position().z
	await ticks(90)
	check(driver.speed_mps < -1.0 and driver.speed_mps >= -5.3, "Holding reverse after stopping backs the truck slowly")
	Input.action_release("reverse")
	return distance


func check_corner_braking() -> void:
	reset_truck(Driver.ROAD_SPEED)
	Input.action_press("accelerate")
	Input.action_press("steer_right")
	await ticks(90)
	Input.action_release("accelerate")
	Input.action_press("reverse")
	for i in 120:
		await physics_frame
		if driver.speed_mps < Driver.GRIP_LIMIT:
			break
	check(driver.speed_mps < Driver.GRIP_LIMIT and driver.get_forward().slide(Vector3.UP).angle_to(driver._truck.velocity) < 0.02,
		"Braking below 35 mph restores tracking even with the wheel held over")
	Input.action_release("reverse")
	Input.action_release("steer_right")


func _run() -> void:
	root.add_child(driver)
	await physics_frame
	for load: float in [0.0, 0.28]:
		reset_truck()
		driver.snow_load = load
		Input.action_press("accelerate")
		await ticks(660)
		check(is_equal_approx(driver.speed_mps, Driver.ROAD_SPEED), "Blade-up truck reaches 50 mph on road load %.2f" % load)
		check(absf(driver._truck.position.x) < 0.01, "A straight truck tracks straight at speed")
		Input.action_release("accelerate")
	var stopping_at_35 := await braking_distance(35 * 0.44704)
	var stopping_at_50 := await braking_distance(50 * 0.44704)
	check(stopping_at_35 > 12.0 and stopping_at_35 < 14.0, "At 35 mph the brakes retain low-speed traction")
	var full_grip_distance := stopping_at_35 * pow(50.0 / 35.0, 2)
	check(stopping_at_50 > full_grip_distance * 1.15, "Reduced grip at 50 mph needs more road than speed alone would require")
	await check_corner_braking()

	reset_truck()
	driver.snow_load = 0.62
	driver.blade_down = true
	Input.action_press("accelerate")
	await ticks(180)
	check(driver.speed_mps > 5.5 and driver.speed_mps < 7.0, "Working a loaded plow keeps its deliberate speed")
	Input.action_release("accelerate")

	var at_35 := await measure_slip(35 * 0.44704)
	var at_40 := await measure_slip(40 * 0.44704)
	var at_50 := await measure_slip(50 * 0.44704)
	check(at_35 < 0.01 and at_40 > at_35 + 0.07 and at_50 > at_40 + 0.05, "Body-to-travel slip increases from 35 to 40 to 50 mph")

	reset_truck(Driver.ROAD_SPEED)
	driver.offroad_fraction = 1.0
	driver.snow_load = 0.9
	Input.action_press("accelerate")
	await ticks(60)
	var impact_distance := -driver.get_truck_position().z
	check(impact_distance > 6.0 and impact_distance < 14.0, "Snow catches a fast truck over several metres")
	check(is_equal_approx(driver.speed_mps, Driver.FIELD_SPEED), "The truck crawls through deep snow with the gas held")
	Input.action_press("steer_right")
	await ticks(90)
	check(driver.speed_mps < Driver.FIELD_SPEED * 0.8 and absf(driver._truck.rotation.y) > 0.25, "Turning the wheels in powder costs pulling speed but still steers")
	Input.action_release("steer_right")
	Input.action_release("accelerate")
	Input.action_press("reverse")
	await ticks(165)
	check(is_equal_approx(driver.speed_mps, -Driver.FIELD_REVERSE_SPEED), "The truck can reverse through deep snow under its own power")
	driver.offroad_fraction = 0.5
	await ticks(90)
	check(driver.speed_mps < -Driver.FIELD_REVERSE_SPEED, "Tires on the road regain pulling speed while the other two are in snow")
	Input.action_release("reverse")
	driver.queue_free()
	await process_frame
	print("Slip angles at 35/40/50 mph: %.1f / %.1f / %.1f degrees. First second in the bank: %.1f m." % [
		rad_to_deg(at_35), rad_to_deg(at_40), rad_to_deg(at_50), impact_distance])
	print("Braking distances at 35/50 mph: %.1f / %.1f m." % [stopping_at_35, stopping_at_50])
	print("Driver acceleration, high-speed slip, braking and drift recovery failures: ", failures)
	quit(1 if failures else 0)
