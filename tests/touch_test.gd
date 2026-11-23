extends SceneTree

const SHIFT = preload("res://game/shift.tscn")
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
	current_scene = null
	shift = SHIFT.instantiate()
	root.add_child(shift)
	current_scene = shift
	await _advance()
	controls = shift.find_child("TouchControls",true,false)
	_expect(controls!=null,"Touch suite requires the --touch-ui game argument")
	if controls!=null:
		_expect(not controls.visible,"Title screen must leave the touch overlay hidden")
		await _tap(0,_hud_point(shift.hud.ignition.START.get_center()))
		_expect(controls.visible and shift.mode=="drive","Tapping the ignition must open the working controls")
		await _driving()
		await _menus()
		await _door()
	shift.soundscape.shutdown()
	shift.queue_free()
	await process_frame
	# The mixer works in wall time, including when CI drives physics with --fixed-fps.
	OS.delay_msec(300)
	await process_frame
	if failures.is_empty():
		print("PASS: touchscreen ignition, independent fingers, radio, menu cancellation and porch interaction")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

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
	_expect(not shift.mic_down and shift.hud.subtitle.contains("Beck"),"Releasing the mic in the cab must receive the current route")
	await _tap(5,_button(&"blade"))
	_expect(shift.driver.blade_down,"A tap on the plow rocker must change the physical blade")
	# The original throttle finger is deliberately still down when the map opens.

func _menus() -> void:
	_finger(6,_button(&"dispatch"),true)
	await _tap(7,_button(&"plat"))
	_expect(shift.mode=="book" and not controls.visible,"The map should replace the driving controls")
	_expect(not Input.is_action_pressed("accelerate") and not Input.is_action_pressed("dispatch") and not shift.mic_down,"Opening a menu must release an active pedal and CB mic")
	await _tap(8,_hud_point(shift.hud.book.CLOSE.get_center()))
	_expect(shift.mode=="drive" and controls.visible,"The plat’s own close tab must restore the route")
	_expect(not Input.is_action_pressed("accelerate"),"Closing the book must not reapply the interrupted pedal")

func _door() -> void:
	await _tap(9,_button(&"interact"))
	_expect(not shift.driver.in_cab and controls._buttons.has(&"interact") and not controls._buttons.has(&"blade"),"The open cab door should expose on-foot actions and hide the blade switch")
	_expect(not controls._buttons.has(&"job"),"A player standing by the truck cannot knock on a distant porch")
	# Stage a walker's arrival at the porch; the route smoke test covers the full journey there.
	shift.driver._walker.global_position = Vector3(shift.BECK_PORCH.x,0,shift.BECK_PORCH.y)
	await _advance()
	_expect(not controls._buttons.has(&"interact"),"The cab door action should disappear at the Becks’ porch")
	await _tap(10,_button(&"job"))
	_expect(shift.stage==0 and shift.hud.speaker.contains("BECK"),"An early porch knock must receive the Becks’ contextual reply and preserve the unpaid job")
	await _tap(11,_button(&"pause_shift"))
	_expect(shift.mode=="pause" and not controls.visible,"Pause must release and hide on-foot controls")
