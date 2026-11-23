extends SceneTree

const Encounters = preload("res://world/roadside_encounters.gd")
var shift
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, why: String) -> void:
	if not condition:
		push_error(why)
		failures += 1


func _tap(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame


func _park(at: Vector2, yaw: float) -> void:
	shift.driver._truck.global_position = Vector3(at.x, 0, at.y)
	shift.driver._truck.rotation.y = yaw
	await physics_frame
	await physics_frame


func _walk_to(at: Vector2, reach: float) -> void:
	for tick in 650:
		var foot: Vector3 = shift.driver.get_driver_position()
		var to_target := at - Vector2(foot.x, foot.z)
		if to_target.length() <= reach:
			break
		var facing: Vector3 = -root.get_camera_3d().global_basis.z
		var turn := Vector2(facing.x, facing.z).angle_to(to_target)
		for kv in [["steer_left", turn < -.05], ["steer_right", turn > .05], ["accelerate", absf(turn) < .22]]:
			if kv[1]:
				Input.action_press(kv[0])
			else:
				Input.action_release(kv[0])
		await physics_frame
	for action in ["steer_left", "steer_right", "accelerate"]:
		Input.action_release(action)
	await physics_frame


func _stop(at: Vector2, target: Vector2, action: String, clue: String) -> void:
	var order: Dictionary = shift.dispatch.job.duplicate(true)
	await _park(at, PI)
	expect(shift.field_action_label().is_empty(), "Investigating the %s requires stepping outside" % clue)
	await _tap(KEY_E)
	expect(not shift.driver.in_cab, "Can park and leave the road to investigate")
	await _walk_to(target, 2.65)
	expect(shift.field_action_label() == action and shift.hud.prompt.contains(action), "The nearby %s offers its field action" % clue)
	await _tap(KEY_X)
	expect(shift.encounters.investigated.has(clue) and shift.hud.speaker == "OUTSIDE", "The field action inspects the %s" % clue)
	expect(shift.field_action_label().is_empty(), "The field observation is made once")
	expect(shift.dispatch.job == order and shift.dispatch.completed == 0, "A detour preserves Deb's unfinished order")
	await _walk_to(at, 3.6)
	await _tap(KEY_E)
	expect(shift.driver.in_cab, "Can return from the %s to the truck" % clue)


func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(1))
	shift = load("res://game/shift.tscn").instantiate()
	root.add_child(shift)
	await _tap(KEY_ENTER)
	var scenes: Encounters = shift.encounters
	await _stop(Vector2(2.0, -285.0), scenes.wagon_window, "Tap the glass", "wagon")
	expect(not scenes.tail_lights.is_visible_in_tree(), "Tapping the window extinguishes both rear lamps")
	# Drive by the standing figure and come back. Missing the first crossing leaves the tracks available.
	await _park(Encounters.FIRST_PRINT + Vector2(-31, 6), -PI / 2)
	var first := scenes.figure.position
	for i in 60:
		await physics_frame
	expect(scenes.walked and scenes.figure.visible and first.distance_to(scenes.figure.position) > .7, "The figure walks as the truck approaches")
	expect(scenes.prints.multimesh.visible_instance_count > 0, "The walker leaves physical tracks")
	await _park(Encounters.FIRST_PRINT + Vector2(-180, 6), -PI / 2)
	expect(not scenes.walked and scenes.investigated.size() == 1, "Passing the figure leaves it available on a return drive")
	await _stop(Encounters.FIRST_PRINT + Vector2(0, 6.6), Encounters.FIRST_PRINT, "Study tracks", "prints")
	scenes.update_sightings(20, Encounters.FIRST_PRINT)
	expect(scenes.walk_finished and not scenes.figure.visible and scenes.prints.multimesh.visible_instance_count > 10, "Bootprints remain after the walker disappears")
	await _stop(Vector2(2, 389.0), scenes.lamp_stoop, "Still the lamp", "lamp")
	expect(absf(scenes.lamp.rotation.x - .44) < .04, "The lit shade hangs crooked after the stop")
	if failures == 0:
		print("PASS: drove by, revisited and investigated roadside scenes using the field controls")
	shift.soundscape.shutdown()
	shift.queue_free()
	var finish := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < finish:
		OS.delay_msec(10)
		await process_frame
	quit(1 if failures else 0)
