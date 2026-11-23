extends SceneTree

## From project root: godot --headless --fixed-fps 60 --script res://tests/shift_smoke.gd

const Route = preload("res://world/route.gd")

var shift
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# A runtime error in an awaited test must still terminate headless CI.
	create_timer(550.0, true, false, true).timeout.connect(_timed_out)
	var scene := load("res://game/shift.tscn") as PackedScene
	if scene == null:
		push_error("Could not load the shift scene")
		quit(1)
		return
	shift = scene.instantiate()
	root.add_child(shift)
	current_scene = shift
	await process_frame
	check(shift.mode == "title", "Fresh game opens on its title screen")
	await _tap(KEY_ENTER)
	check(shift.mode == "drive" and shift.stage == 0, "Starting the shift opens the first job")
	if "--route" in OS.get_cmdline_user_args():
		await _drive_delivery()
		if failures == 0:
			print("PASS: drove Q, cleared the Beck lane with the truck, walked to both porches and finished the route")
		await _finish()
		return
	await _test_cab()
	await _test_radio()
	await _test_menus_and_driving()
	await _test_lane()
	if failures == 0:
		print("PASS: title, controls, cab, radio, map, pause, driving and plow progress")
	else:
		printerr("Shift smoke test failed ", failures, " check(s)")
	await _finish()


func _finish() -> void:
	shift.soundscape.shutdown()
	shift.queue_free()
	await process_frame
	# --fixed-fps advances simulated time faster than the audio output thread.
	var finish := Time.get_ticks_msec()+300
	while Time.get_ticks_msec()<finish:
		OS.delay_msec(10)
		await process_frame
	quit(0 if failures==0 else 1)


func check(condition: bool, detail: String) -> void:
	if not condition:
		failures += 1
		push_error(detail)


func _timed_out() -> void:
	push_error("Shift smoke test timed out")
	quit(1)


func _key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(keycode: Key) -> void:
	_key(keycode, true)
	await physics_frame
	_key(keycode, false)
	await physics_frame


func _test_cab() -> void:
	check(shift.driver.in_cab, "Player starts in the truck")
	var initial_blade: bool = shift.driver.blade_down
	await _tap(KEY_B)
	check(shift.driver.blade_down != initial_blade, "B toggles the blade")
	await _tap(KEY_B)
	check(shift.driver.blade_down == initial_blade, "Second B restores initial blade position")
	await _tap(KEY_E)
	check(not shift.driver.in_cab, "E exits a parked truck")
	await _tap(KEY_E)
	check(shift.driver.in_cab, "E next to the parked cab re-enters it")


func _test_radio() -> void:
	_key(KEY_R, true)
	for tick in range(12):
		await physics_frame
		check(shift.hud.mic and shift.hud.subtitle.is_empty(), "Deb waits while the mic key is down")
	_key(KEY_R, false)
	await process_frame
	check(not shift.hud.mic and not shift.hud.subtitle.is_empty(), "Releasing R receives Deb's directions")


func _test_menus_and_driving() -> void:
	await _tap(KEY_M)
	check(shift.mode == "book", "M opens the plat book")
	await _tap(KEY_M)
	check(shift.mode == "drive", "Closing the plat book returns to the shift")
	await _tap(KEY_ESCAPE)
	check(shift.mode == "pause", "Escape pauses the shift")
	var parked: Vector3 = shift.driver.get_truck_position()
	_key(KEY_W, true)
	for tick in range(20):
		await physics_frame
	_key(KEY_W, false)
	check(shift.driver.get_truck_position().distance_to(parked) < 0.08, "The truck stays parked while paused")
	await _tap(KEY_ESCAPE)
	check(shift.mode == "drive", "Escape resumes the shift")
	_key(KEY_W, true)
	for tick in range(75):
		await physics_frame
	_key(KEY_W, false)
	check(shift.driver.get_truck_position().distance_to(parked) > 1.0, "Holding W drives the truck")


func _cut_lane(from_x: float, to_x: float) -> void:
	# Exercise the same blade contact and job evaluator as a live driving pass.
	shift.snow.stop_pass()
	var start := roundi(from_x * 4)
	var finish := roundi(to_x * 4)
	for quarter_meter in range(start, finish + 1):
		shift.snow.cut(Vector3(quarter_meter * 0.25, 0.0, Route.BECK_Z), Vector3.RIGHT)
	shift.snow.stop_pass()
	shift.update_job_progress()


func _test_lane() -> void:
	check(shift.snow.open_length() == 0, "The contracted lane starts unplowed")
	_cut_lane(Route.LAST_SLICE - 10, Route.LAST_SLICE + 2)
	check(shift.snow.open_length() == 0 and shift.stage == 0, "An isolated strip at the tank is incomplete")
	_cut_lane(3.0, 14.0)
	var partial: int = shift.snow.open_length()
	check(partial > 0 and partial < Route.FULL_LANE and shift.stage == 0, "The entrance earns partial progress")
	_cut_lane(3.0, 14.0)
	check(shift.snow.open_length() == partial and shift.stage == 0, "Plowing an existing strip gives no extra length")
	shift.check_job()
	check(shift.stage == 0, "A partially open lane cannot be signed off")
	_key(KEY_R, true)
	await physics_frame
	_cut_lane(13.0, Route.LAST_SLICE - 9)
	check(shift.snow.open_length() == Route.FULL_LANE and shift.stage == 1, "Connecting both strips opens the full lane and advances to the porch")
	check(shift.hud.mic and shift.hud.subtitle.is_empty(), "Completing a job while transmitting does not let an ordinary reply through")
	_key(KEY_R, false)
	await process_frame
	check(not shift.hud.subtitle.is_empty(), "Deb gives the next instruction when the mic opens")
	shift.update_job_progress()
	shift.check_job()
	check(shift.stage == 1, "A completed lane cannot overlap or bypass the on-foot check")


# Optional full-route playthrough: add `-- --route` to the invocation above.
# This pass only touches the normal keyboard controls and observes player position.
func _drive_delivery() -> void:
	await _travel(Vector2(-6.0, Route.HOME_Z), 8.0)
	await _travel(Vector2(1.6, Route.HOME_Z - 16.0), 5.0)
	await _travel(Vector2(1.6, Route.BECK_Z + 5.9), 12.5)
	await _tap(KEY_B)
	await _travel(Vector2(14.0, Route.BECK_Z), 4.0)
	await _travel(Route.BECK_PARK, 5.0)
	await _tap(KEY_E)
	check(not shift.driver.in_cab, "Can park and get out at the Becks")
	check(shift.stage == 1, "A real blade pass completes the truck-width lane (meters open: %s)" % shift.snow.open_length())
	var truck_at: Vector3 = shift.driver.get_truck_position()
	var truck_dir: Vector3 = shift.driver.get_forward()
	var passenger_side := Vector2(-truck_dir.z, truck_dir.x)
	await _round_hood()
	await _travel(Route.BECK_PORCH, 2.9)
	await _tap(KEY_X)
	check(shift.stage == 2, "Knocking on foot at the Becks sends the driver home")
	await _travel(Vector2(truck_at.x, truck_at.z) + passenger_side * 2.5, 2.9)
	await _tap(KEY_E)
	check(shift.driver.in_cab, "Can get back into the truck from the Becks' porch")
	await _tap(KEY_B)
	# Turn in the unloading yard before pulling back onto the lane.
	await _travel(Route.BECK_PARK + Vector2(8, -6), 3.5)
	await _travel(Route.BECK_PARK + Vector2(6, 0), 3.0, true)
	await _travel(Route.BECK_PARK + Vector2(-9, 0), 4.0)
	await _travel(Vector2(4.5, Route.BECK_Z), 8.0)
	await _travel(Vector2(-1.8, Route.BECK_Z + 16.0), 4.5)
	await _travel(Vector2(-1.8, Route.HOME_Z - 6), 12.5)
	await _travel(Vector2(-16.0, Route.HOME_Z), 4.5)
	await _travel(Route.HOME_PORCH + Vector2(7, 0), 7.0)
	await _tap(KEY_E)
	await _round_hood()
	await _travel(Route.HOME_PORCH, 2.9)
	await _tap(KEY_X)
	check(shift.stage == 3, "The home kitchen interaction completes the contract")


func _position() -> Vector2:
	var where: Vector3 = shift.driver.get_driver_position()
	return Vector2(where.x, where.z)


func _round_hood() -> void:
	var forward: Vector3 = shift.driver.get_forward()
	var nose := _position() + Vector2(forward.x, forward.z) * 5.0
	await _travel(nose, 2.9)
	await _travel(nose + Vector2(-forward.z, forward.x) * 4.5, 2.9)


func _held(keycode: Key, wanted: bool) -> void:
	if Input.is_physical_key_pressed(keycode) != wanted:
		_key(keycode, wanted)


func _travel(goal: Vector2, cruise_mps: float, reverse := false) -> void:
	var max_ticks := ceili((_position().distance_to(goal) / 2.0 + 10.0) * 60.0)
	for tick in range(max_ticks):
		var to_goal := goal - _position()
		if to_goal.length() < 0.75:
			break
		var facing: Vector3 = shift.driver.get_forward() if shift.driver.in_cab else -root.get_camera_3d().global_basis.z
		if reverse:
			facing = -facing
		var aim := to_goal
		# Follow the right-hand tire line on the long straight. Steering directly
		# at a mailbox a mile away would allow a small heading error to cross a field.
		if absf(goal.x) < 2.0 and absf(to_goal.y) > 18.0:
			aim.y = signf(to_goal.y) * 18.0
		var turn := Vector2(facing.x, facing.z).angle_to(aim)
		var steering := -turn if reverse else turn
		_held(KEY_A, steering < -0.044)
		_held(KEY_D, steering > 0.044)
		if shift.driver.in_cab:
			var target_speed := minf(cruise_mps, 2.6 + to_goal.length() * 0.13)
			_held(KEY_W, not reverse and absf(shift.driver.speed_mps) < target_speed)
			_held(KEY_S, reverse and absf(shift.driver.speed_mps) < target_speed)
		else:
			_held(KEY_W, absf(turn) < 0.22)
		await physics_frame
	for key in [KEY_A, KEY_D, KEY_W, KEY_S]:
		_held(key, false)
	check(_position().distance_to(goal) < 1.05, "Waypoint %s reached; actual position %s" % [goal, _position()])
