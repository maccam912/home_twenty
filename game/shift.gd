extends Node3D

const Driver = preload("res://vehicle/driver.gd")
const Township = preload("res://world/township.gd")
const PlowedSnow = preload("res://world/plowed_snow.gd")
const Soundscape = preload("res://audio/soundscape.gd")
const ShiftHUD = preload("res://ui/shift_hud.gd")
const LoadingBay = preload("res://world/loading_bay.gd")
const RoadsideEncounters = preload("res://world/roadside_encounters.gd")
const Dispatch = preload("res://game/dispatch.gd")
const Route = preload("res://world/route.gd")
const STOP_REACH := 3.7
const PICTURE_LINES := 320.0
var town: Township
var driver
var snow
var spray: CPUParticles3D
var hud
var soundscape
var mode := "title"
var shift_started := false
var closing := false
var dispatch := Dispatch.new()
var encounters := RoadsideEncounters.new()
var pending_order_call := false
var pending_route_call := false
var phone_bell := AudioStreamPlayer3D.new()
var loading_bays: Dictionary[String, LoadingBay] = {}
var last_bay_revision := -1
var touch_enabled := OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args()
var title_camera := Camera3D.new()
var drive_camera: Camera3D
var mode_before_book := "drive"
var message_left := 0.0
var since_check := 0.0
var last_revision := -1
var mic_down := false
var last_cut := 0.0
var previous_mouse_mode := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	get_tree().auto_accept_quit = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_size_picture)
	_size_picture()
	town = Township.new()
	town.name = "Township"
	add_child(town)
	encounters.name = "RoadsideEncounters"
	add_child(encounters)
	snow = PlowedSnow.new()
	snow.name = "Snow"
	add_child(snow)
	spray = snow.create_spray()
	dispatch.lane_is_open = func(site: String) -> bool:
		return snow.lane_opened(site) >= Route.lane_length(site)
	driver = Driver.new()
	driver.name = "Driver"
	driver.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(driver)
	soundscape = Soundscape.new()
	soundscape.name = "Soundscape"
	add_child(soundscape)
	phone_bell.name = "PikePayphone"
	phone_bell.stream = preload("res://audio/generated/payphone.mp3")
	phone_bell.position = Vector3(Route.PHONE.x, 1.45, Route.PHONE.y)
	phone_bell.unit_size = 9.0
	phone_bell.max_distance = 72.0
	phone_bell.volume_db = -5.0
	phone_bell.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(phone_bell)
	driver.horn_used.connect(func(): soundscape.play_cue("horn"))
	driver.cab_changed.connect(_on_cab_changed)
	driver.blade_changed.connect(func(): soundscape.play_cue("blade_drop" if driver.blade_down else "blade_lift"))
	driver.collapse_recovered.connect(_on_collapse)
	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)
	hud = ShiftHUD.new()
	hud.touch_enabled = touch_enabled
	hud_layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.menu_action.connect(_act_menu)
	if touch_enabled:
		get_tree().quit_on_go_back = false
		var touch = load("res://ui/touch_controls.gd").new()
		touch.name = "TouchControls"
		hud_layer.add_child(touch)
		touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		touch.setup(self)
	drive_camera = get_viewport().get_camera_3d()
	add_child(title_camera)
	title_camera.fov = 54
	var yard := Transform3D(Basis.looking_at(driver.get_forward()), driver.get_truck_position())
	title_camera.position = yard * Vector3(6.1, 2.2, -7.9)
	title_camera.look_at(yard * Vector3(2.25, 1.36, 1.0))
	title_camera.make_current()
	_show_menu("title")

func _size_picture() -> void:
	# The road stays at TV resolution while the map and subtitles use the full canvas.
	var viewport := get_viewport()
	var line_pitch := maxf(1.0, get_window().size.y / PICTURE_LINES)
	viewport.scaling_3d_scale = 1.0 / line_pitch
	$Display/CRT.material.set_shader_parameter("line_pitch", line_pitch)

func _show_menu(next: String) -> void:
	if mode=="drive":
		previous_mouse_mode = Input.mouse_mode
		if mic_down:
			mic_down = false
			hud.mic = false
	mode = next
	hud.mode = mode
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE if mode=="drive" else Control.MOUSE_FILTER_STOP
	get_tree().paused = mode!="drive"
	Input.mouse_mode = previous_mouse_mode if mode=="drive" else Input.MOUSE_MODE_VISIBLE
	hud.queue_redraw()

func begin_shift() -> void:
	_show_menu("drive")
	if not shift_started:
		shift_started = true
		soundscape.start_truck()
		if is_instance_valid(drive_camera):
			drive_camera.make_current()
		var truck: Vector3 = driver.get_truck_position()
		dispatch.start_shift(Vector2(truck.x, truck.z))
		_dispatch_changed()
		_call_order()

func _act_menu(action: String) -> void:
	match action:
		"begin":
			begin_shift()
		"book":
			mode_before_book = mode
			_show_menu("book")
			soundscape.play_cue("plat_fold")
		"close":
			_show_menu(mode_before_book)
			soundscape.play_cue("plat_fold")

func _input(event: InputEvent) -> void:
	if closing or hud == null or event.is_echo():
		return
	if event.is_action_pressed("plat"):
		_act_menu("close" if mode=="book" else "book")
	elif event.is_action_pressed("pause_shift"):
		if mode=="book":
			_act_menu("close")
		elif mode=="drive":
			_show_menu("pause")
		elif mode=="pause":
			begin_shift()
	elif mode!="drive":
		if event.is_action_pressed("ui_accept"):
			_act_menu("close" if mode=="book" else "begin")
		else:
			return
	elif event.is_action_pressed("dispatch"):
		if driver.in_cab:
			mic_down = true
			hud.mic = true
			hud.subtitle = ""
			soundscape.play_cue("radio_key")
		else:
			say("TRUCK RADIO","The handset is in the cab.",2.5)
	elif event.is_action_released("dispatch") and mic_down:
		mic_down = false
		hud.mic = false
		soundscape.play_cue("radio_squelch")
		directions()
	elif event.is_action_pressed("job"):
		check_job()
	else:
		return
	hud.queue_redraw()
	get_viewport().set_input_as_handled()

func _on_cab_changed() -> void:
	soundscape.play_cue("door")
	if mic_down:
		mic_down = false
		hud.mic = false
	snow.stop_pass()

func _on_collapse() -> void:
	say("IN THE CAB","The door is shut. The heater is running. You remember the wind, then nothing.",8)

func say(who: String, what: String, seconds: float) -> void:
	hud.speaker = who
	hud.subtitle = what
	message_left = seconds
	hud.queue_redraw()

func directions() -> void:
	pending_route_call = false
	var v: Vector3 = driver.get_truck_position()
	var p := Vector2(v.x, v.z)
	var order := dispatch.job
	var site: Dictionary = Route.SITES[order.site]
	var words := Route.directions(p, order.site)
	if p.distance_to(site.yard) < 22:
		words = _onsite_instruction()
	elif order.kind == "plow" and p.distance_to(site.mouth) < 16:
		words = "That's the turn for %s. Lower the blade and open a truck-width from the road to the yard." % site.name
	elif driver.offroad_fraction >= 0.75:
		words = "Easy in that snow, hon. She’ll pull better with the wheels straight. " + words
	say("DEB   /   CB 19", words, maxf(7.0, words.length() / 17.0))

func _onsite_instruction() -> String:
	if hud.opened < hud.target_length:
		if dispatch.job.kind == "windrow":
			return "There's a pile in the yard. Drop the blade and run the length of the bay between the orange stakes."
		return "There's still a ridge across the run. Open a truck-width all the way from the road to the yard."
	if hud.target_length > 0:
		return "That's open, hon. Park and sign the slip at %s." % Dispatch.fixture_for(dispatch.job.site)
	return dispatch.job.instruction

func _at_stop(p: Vector2) -> bool:
	if dispatch.job.is_empty():
		return false
	var stop := Dispatch.stop_for(dispatch.job)
	return p.distance_squared_to(stop) <= STOP_REACH * STOP_REACH

func field_action_label() -> String:
	if driver.in_cab:
		return ""
	var v: Vector3 = driver.get_driver_position()
	if _at_stop(Vector2(v.x, v.z)):
		return dispatch.job.action
	return encounters.action_at(Vector2(v.x, v.z))

func check_job() -> void:
	if driver.in_cab:
		say("IN THE CAB", "Park and step outside to lend a hand.", 3)
		return
	var v: Vector3 = driver.get_driver_position()
	if not _at_stop(Vector2(v.x, v.z)):
		var observation := encounters.investigate_at(Vector2(v.x, v.z))
		if observation.is_empty():
			say("OUTSIDE", "Your stop is marked on Deb's slip in the plat book.", 3)
		else:
			say("OUTSIDE", observation, maxf(6.0, observation.length() / 17.0))
		return
	update_job_progress()
	if hud.opened < hud.target_length:
		say("AT THE TURNOUT", _onsite_instruction(), 6)
		return
	if dispatch.job.get("stop") == Route.NOTICE:
		town.uncover_bus_route()
	var response := dispatch.finish_stop(Vector2(v.x, v.z))
	say(response.speaker, response.text, maxf(6.0, response.text.length() / 17.0))
	_dispatch_changed()

func _dispatch_changed() -> void:
	var order := dispatch.job
	if order.get("stop") == Route.PHONE:
		phone_bell.play()
	else:
		phone_bell.stop()
	driver.set_cargo(order.get("cargo", ""))
	hud.completed_jobs = dispatch.completed
	hud.work_order = order
	hud.opened = 0
	hud.target_length = 0
	if order.kind == "plow":
		hud.target_length = Route.lane_length(order.site)
		hud.opened = snow.lane_opened(order.site)
	elif order.kind == "windrow":
		if not loading_bays.has(order.site):
			var bay := LoadingBay.new()
			add_child(bay)
			bay.setup(Route.pile_path(order.site))
			loading_bays[order.site] = bay
		var bay := loading_bays[order.site]
		bay.deposit(dispatch.completed)
		hud.target_length = bay.length_metres
		last_bay_revision = bay.revision
	last_revision = snow.revision
	pending_order_call = true
	pending_route_call = false

func update_job_progress() -> void:
	var order := dispatch.job
	var previous: int = hud.opened
	if order.kind == "plow" and last_revision != snow.revision:
		last_revision = snow.revision
		hud.opened = snow.lane_opened(order.site)
	elif order.kind == "windrow":
		var bay := loading_bays[order.site]
		if bay.revision != last_bay_revision:
			last_bay_revision = bay.revision
			hud.opened = bay.open_metres()
	if previous < hud.target_length and hud.opened == hud.target_length and driver.in_cab and not mic_down:
		say("DEB   /   CB 19", _onsite_instruction(), 7)
		soundscape.play_cue("radio_squelch")

func _call_order() -> void:
	pending_order_call = false
	pending_route_call = true
	soundscape.play_cue("radio_squelch")
	var words: String = dispatch.job.brief
	say("DEB   /   CB 19", words, maxf(8.0, words.length() / 17.0))

func _physics_process(delta: float) -> void:
	town.set_truck_pose(driver.get_truck_position(), driver.get_forward(), driver.get_truck_up())
	driver.set_storm_strength(town.gust_strength)
	soundscape.set_gust(town.gust_strength)
	if mode!="drive":
		return
	var truck_at: Vector3 = driver.get_truck_position()
	snow.stream_to(Vector2(truck_at.x, truck_at.z))
	driver.sample_tires(snow)
	var blade_tip: Vector3 = driver.get_blade_position()
	var forward: Vector3 = driver.get_forward()
	var ahead := blade_tip + forward*.5
	var p := Vector2(ahead.x,ahead.z)
	var on_road: bool = snow.on_surface(p)
	var uncut: float = 1.0-snow.clearance(p)
	driver.snow_load = (.28 if on_road else .9)*uncut
	if driver.in_cab and driver.blade_down and driver.speed_mps>.15:
		driver.snow_load = (.62 if on_road else 1.0)*uncut
		var cut: bool = snow.cut(blade_tip, forward)
		for bay: LoadingBay in loading_bays.values():
			if bay.cut(blade_tip, forward):
				cut = true
				driver.snow_load = 1.0
		if cut:
			last_cut = .16
			var side := forward.cross(Vector3.UP)
			spray.global_position = blade_tip + side*1.16 + Vector3.UP*.14
			spray.basis = Basis.looking_at(forward)
	else:
		snow.stop_pass()
	if absf(driver.speed_mps)>.12:
		snow.press_tires(driver.get_truck_position()-forward*1.3,forward)
	last_cut = maxf(0,last_cut-delta)
	spray.emitting = last_cut>0
	soundscape.update_state(driver.in_cab,driver.speed_mps,last_cut>0)
	since_check += delta
	if since_check >= .25:
		since_check = 0
		update_job_progress()
	var player: Vector3 = driver.get_driver_position()
	var pos := Vector2(player.x,player.z)
	encounters.update_sightings(delta, pos)
	hud.area = Route.area_at(pos)
	hud.mph = roundi(absf(driver.speed_mps)*2.237)
	hud.low_grip = driver.speed_mps > Driver.GRIP_LIMIT
	hud.cab = driver.in_cab
	hud.blade = driver.blade_down
	hud.prompt = ""
	var field_action := field_action_label()
	if not field_action.is_empty():
		hud.prompt = "[X]  " + field_action
	elif not driver.in_cab and player.distance_to(driver.get_truck_position())<4:
		hud.prompt = "[E]  Climb into the cab"
	elif mic_down:
		hud.prompt = "Transmitting  ·  release R to listen"
	elif driver.in_cab and not driver.blade_down and hud.opened < hud.target_length:
		var site: Dictionary = Route.SITES[dispatch.job.site]
		var blade_start: Vector2 = site.mouth if dispatch.job.kind == "plow" else site.yard
		if pos.distance_squared_to(blade_start) < 18.0 * 18.0:
			hud.prompt = "[B]  Lower the blade"
	if touch_enabled and hud.prompt!="":
		hud.prompt = hud.prompt.replace("[X]  ","").replace("[E]  ","").replace("[B]  ","").replace("release R to listen","release the mic to listen")
	hud.set_cold(driver.cold)
	if message_left>0:
		message_left -= delta
		if message_left<=0:
			hud.subtitle = ""
	if driver.in_cab and not mic_down and message_left <= 0:
		if pending_order_call:
			_call_order()
		elif pending_route_call:
			soundscape.play_cue("radio_squelch")
			directions()
	hud.queue_redraw()

func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(soundscape):
		_close_game()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST and touch_enabled and is_instance_valid(hud):
		match mode:
			"drive":
				_show_menu("pause")
			"pause":
				begin_shift()
			"book":
				_act_menu("close")
			"title":
				_close_game()

func _close_game() -> void:
	if closing:
		return
	closing = true
	mode = "closing"
	get_tree().paused = true
	phone_bell.stop()
	phone_bell.stream = null
	soundscape.shutdown()
	# Let the audio mixer release its decoded MP3 buffers before the engine exits.
	await get_tree().create_timer(.25,true,false,true).timeout
	get_tree().quit()
