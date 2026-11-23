extends SceneTree

const Route = preload("res://world/route.gd")
const SHIFT = preload("res://game/shift.tscn")
const TouchControls = preload("res://ui/touch_controls.gd")
var shift
var controls
var failures := PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _send(event: InputEvent) -> void:
	root.push_input(event,true)
	Input.flush_buffered_events()

func _finger(id: int, position: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	_send(event)

func _button(action: StringName) -> Vector2:
	if not controls._buttons.has(action):
		_expect(false, "Missing touch control %s" % action)
		return Vector2(-1000,-1000)
	return controls.get_global_transform_with_canvas() * controls._buttons[action].get_center()

func _hud_point(design: Vector2) -> Vector2:
	var local: Vector2 = shift.hud._origin()+design*shift.hud._scale_factor()
	return shift.hud.get_global_transform_with_canvas()*local

func _drag(id: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = id
	event.position = position
	_send(event)

func _advance() -> void:
	await physics_frame
	await physics_frame
	await process_frame
	Input.flush_buffered_events()

func _tap(id: int, position: Vector2) -> void:
	_finger(id,position,true)
	await _advance()
	_finger(id,position,false)
	await _advance()

func _run() -> void:
	_check_layout(Vector2(1200, 540), Rect2(46, 0, 1154, 526))
	_check_layout(Vector2(960, 540), Rect2(0, 0, 960, 540))
	_check_layout(Vector2(960, 720), Rect2(0, 12, 960, 694))
	current_scene = null
	shift = SHIFT.instantiate()
	root.add_child(shift)
	current_scene = shift
	await _advance()
	controls = shift.find_child("TouchControls",true,false)
	_expect(controls!=null,"Touch suite requires the --touch-ui game argument")
	if controls!=null:
		_expect(not controls.visible,"Title screen must leave the touch overlay hidden")
		await _tap(12,_hud_point(shift.hud.ignition.PLAT.get_center()))
		var book = shift.hud.book
		var southeast: Vector2 = book.PLATE.end - Vector2(20,20)
		await _tap(13,_hud_point(southeast))
		_expect(book.page == "section" and book.cell_name(book.section) == "D4","The county index opens distant sections even before dispatch")
		await _tap(14,_hud_point(book.CLOSE.get_center()))
		await _tap(0,_hud_point(shift.hud.ignition.START.get_center()))
		_expect(controls.visible and shift.mode=="drive","Tapping the ignition must open the working controls")
		await _driving()
		await _menus()
		await _back_onto_road()
		await _door()
	shift.soundscape.shutdown()
	shift.queue_free()
	await process_frame
	# The mixer works in wall time, including when CI drives physics with --fixed-fps.
	OS.delay_msec(300)
	await process_frame
	if failures.is_empty():
		print("PASS: touch target sizes, independent fingers, driving, walking, off-road recovery and menus")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_layout(screen: Vector2, safe: Rect2) -> void:
	var layout := TouchControls.new()
	layout._safe = safe
	layout._near_truck = true
	layout._job_label = "TAKE TICKET"
	var hud_scale := minf(screen.x / 960.0, screen.y / 540.0)
	var origin := (screen - Vector2(960, 540) * hud_scale) * 0.5
	var reserved := [Rect2(18, 4, 244, 78), Rect2(178, 210, 604, 190), Rect2(446, 510, 70, 28)]
	for cab in [true, false]:
		layout._in_cab = cab
		layout._layout()
		var occupied: Array[Rect2] = []
		for action in layout._buttons:
			var r := layout._buttons[action]
			var local_size := r.size / layout._unit
			_expect(safe.encloses(r), "%s must stay inside the safe area at %s" % [action, screen])
			if action in TouchControls.STEERING or action in TouchControls.PEDALS:
				_expect(local_size.x >= 110 and local_size.y >= 100, "%s needs a full-size thumb target" % action)
			else:
				_expect(local_size.x >= 70 and local_size.y >= 64, "%s needs a full-size action button" % action)
			for other in occupied:
				_expect(not other.intersects(r), "%s overlaps another button at %s" % [action, screen])
			for area: Rect2 in reserved:
				var hud_area := Rect2(origin + area.position * hud_scale, area.size * hud_scale)
				_expect(not hud_area.intersects(r), "%s covers the dispatch slip, subtitles, prompt or speedometer at %s" % [action, screen])
			occupied.append(r)
	layout.free()

func _driving() -> void:
	_finger(1,_button(&"accelerate"),true)
	_finger(2,_button(&"steer_right"),true)
	await _advance()
	_expect(Input.is_action_pressed("steer_right") and shift.driver.speed_mps>0,"A second finger must steer while the first holds the gas")
	_drag(2,_button(&"steer_left"))
	_expect(Input.is_action_pressed("steer_left") and not Input.is_action_pressed("steer_right"),"Sliding across the rocker must release the original direction")
	_finger(3,_button(&"steer_left"),true)
	_finger(2,_button(&"steer_left"),false)
	_expect(Input.is_action_pressed("steer_left"),"Lifting one of two fingers on one direction must keep steering")
	_finger(3,_button(&"steer_left"),false,true)
	_expect(not Input.is_action_pressed("steer_left"),"A canceled final pointer must release its action")
	_finger(4,_button(&"dispatch"),true)
	await _advance()
	_expect(shift.mic_down and shift.hud.subtitle.is_empty(),"Holding the radio mic must mute incoming instructions")
	_finger(4,_button(&"dispatch"),false)
	_expect(not shift.mic_down and shift.hud.subtitle.contains(Route.SITES[shift.dispatch.job.site].name),"Releasing the mic in the cab must receive the current route")
	await _tap(5,_button(&"blade"))
	_expect(shift.driver.blade_down,"A tap on the plow rocker must change the physical blade")
	# The original throttle finger is deliberately still down when the map opens.

func _menus() -> void:
	_finger(6,_button(&"dispatch"),true)
	await _tap(7,_button(&"plat"))
	_expect(shift.mode=="book" and not controls.visible,"The map should replace the driving controls")
	_expect(not Input.is_action_pressed("accelerate") and not Input.is_action_pressed("dispatch") and not shift.mic_down,"Opening a menu must release an active pedal and CB mic")
	var book = shift.hud.book
	var target: Vector2i = book.cell_for(Route.SITES[shift.dispatch.job.site].yard)
	_expect(book.page == "county" and book.section == target, "Opening a new call's plat selects its part of the county")
	await _tap(8,_hud_point(book.SHEET.get_center()))
	_expect(book.page == "section" and book.section == target, "The paper tab opens the property directory around the assignment")
	await _tap(8,_hud_point(book.SHEET.get_center()))
	_expect(book.page == "yard" and shift.mode=="book", "Tapping Yard detail opens the current stop's driveway plan")
	await _tap(8,_hud_point(book.SHEET.get_center()))
	_expect(book.page == "county", "Tapping County map restores the county index")
	await _tap(8,_hud_point(book.PLATE.position + Vector2(20,20)))
	_expect(book.page == "section" and book.section == Vector2i.ZERO, "The northwest square opens sheet A1")
	for code in [KEY_RIGHT, KEY_DOWN]:
		_book_key(code)
	_expect(book.section == Vector2i.ONE, "Arrow keys browse adjacent printed sheets")
	_book_key(KEY_V)
	_expect(book.page == ("yard" if book.has_assigned_yard(shift.dispatch.job) else "county"), "V turns the same paper tab as a tap")
	await _tap(8,_hud_point(shift.hud.book.CLOSE.get_center()))
	_expect(shift.mode=="drive" and controls.visible,"The plat’s own close tab must restore the route")
	_expect(not Input.is_action_pressed("accelerate"),"Closing the book must not reapply the interrupted pedal")

func _book_key(code: Key) -> void:
	for down: bool in [true,false]:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.pressed = down
		_send(key)

func _back_onto_road() -> void:
	var truck: CharacterBody3D = shift.driver._truck
	truck.position = Vector3(12, 0, -440)
	truck.rotation = Vector3(0, -PI / 2, 0)
	shift.driver.speed_mps = 0
	await _advance()
	_expect(shift.driver.offroad_fraction == 1.0, "The truck starts with all four tires in the snow")
	_finger(3,_button(&"reverse"),true)
	for tick in 540:
		await physics_frame
		if truck.position.x <= 1.5:
			break
	_finger(3,_button(&"reverse"),false)
	_expect(shift.driver.in_cab and truck.position.x <= 1.5 and shift.driver.offroad_fraction == 0.0, "Holding the reverse pedal backs out of the ditch and regains the road")

func _door() -> void:
	await _tap(9,_button(&"interact"))
	_expect(not shift.driver.in_cab and controls._buttons.has(&"interact") and not controls._buttons.has(&"blade"),"The open cab door should expose on-foot actions and hide the blade switch")
	_expect(not controls._buttons.has(&"job"),"The job button stays hidden away from the assigned stop")
	var start: Vector3 = shift.driver.get_driver_position()
	var yaw: float = shift.driver._walk_yaw
	var step: Rect2 = controls._buttons[&"accelerate"]
	var walk_corner: Vector2 = controls.get_global_transform_with_canvas() * (step.position + Vector2(7, 7) * controls._unit)
	_finger(1,walk_corner,true)
	_finger(2,_button(&"steer_left"),true)
	for i in 12:
		await physics_frame
	_finger(1,walk_corner,false)
	_finger(2,_button(&"steer_left"),false)
	_expect(shift.driver.get_driver_position().distance_to(start) > 0.2 and absf(shift.driver._walk_yaw - yaw) > 0.1, "The outer corner of WALK must work while another finger turns")
	var order: Dictionary = shift.dispatch.job
	var stop: Vector2 = Route.SITES[order.site].stop
	shift.driver._walker.global_position = Vector3(stop.x,0,stop.y)
	await _advance()
	_expect(not controls._buttons.has(&"interact"),"The door action disappears when the driver leaves the truck")
	_expect(controls._job_label == order.action.to_upper(),"The field key names the assigned outdoor work")
	await _tap(10,_button(&"job"))
	if order.kind in ["plow", "windrow"]:
		_expect(shift.dispatch.job == order and shift.hud.opened < shift.hud.target_length, "Checking unfinished plowing keeps the work order open")
	else:
		_expect(shift.dispatch.job != order and shift.hud.speaker == order.speaker, "Tapping the field action advances the stop and gives a response")
	await _tap(11,_button(&"pause_shift"))
	_expect(shift.mode=="pause" and not controls.visible,"Pause must release and hide on-foot controls")
