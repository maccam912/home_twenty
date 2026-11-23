extends Node3D

const Driver = preload("res://vehicle/driver.gd")
const Township = preload("res://world/township.gd")
const PlowedSnow = preload("res://world/plowed_snow.gd")
const Soundscape = preload("res://audio/soundscape.gd")
const ShiftHUD = preload("res://ui/shift_hud.gd")
const Route = preload("res://world/route.gd")
const PORCH_REACH := 3.7
const PICTURE_LINES := 320.0
const SHOVEL_STROKES := 3
const STROKE_SECONDS := 0.95
var town: Township
var driver
var snow
var spray: CPUParticles3D
var hud
var soundscape
var mode := "title"
var stage := 0
var shift_started := false
var closing := false
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
var cleared_scoops := 0
var stroke_time := 0.0

func _ready() -> void:
	get_tree().auto_accept_quit = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_size_picture)
	_size_picture()
	town = Township.new()
	town.name = "Township"
	add_child(town)
	snow = PlowedSnow.new()
	snow.name = "Snow"
	add_child(snow)
	spray = snow.create_spray()
	driver = Driver.new()
	driver.name = "Driver"
	driver.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(driver)
	soundscape = Soundscape.new()
	soundscape.name = "Soundscape"
	add_child(soundscape)
	driver.horn_used.connect(func(): soundscape.play_cue("horn"))
	driver.cab_changed.connect(_on_cab_changed)
	driver.blade_changed.connect(func(): soundscape.play_cue("blade_drop" if driver.blade_down else "blade_lift"))
	driver.collapse_recovered.connect(_on_collapse)
	driver.bogged_down.connect(_on_bogged_down)
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
		say("DEB   /   CB 19","There you are, hon. The Becks need their propane. Left at the end of our drive, then a mile north on Q. Turn right at their box and plow through to the tank.",10.5)

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

func _on_bogged_down() -> void:
	cleared_scoops = 0
	town.pack_wheel_snow(driver.get_truck_position(), driver.get_forward())
	say("IN THE CAB", "The wheels have packed the snow solid. There’s a shovel in the bed.", 5)

func _shovel_wheels(delta: float) -> void:
	if not driver.can_dig_out() or not Input.is_action_pressed("unstick"):
		stroke_time = 0.0
		driver.set_shovel_stroke(-1.0)
		return
	if stroke_time == 0.0:
		soundscape.play_cue("shovel")
	stroke_time += delta
	driver.set_shovel_stroke(stroke_time / STROKE_SECONDS)
	if stroke_time >= STROKE_SECONDS:
		stroke_time = 0.0
		cleared_scoops += 1
		town.clear_wheel_snow(1.0 - float(cleared_scoops) / SHOVEL_STROKES)
		if cleared_scoops == SHOVEL_STROKES:
			driver.dig_out()
			driver.set_shovel_stroke(-1.0)
			say("AT THE WHEELS", "That’s room to get rolling. Ease it back onto the road.", 4)

func say(who: String, what: String, seconds: float) -> void:
	hud.speaker = who
	hud.subtitle = what
	message_left = seconds
	hud.queue_redraw()

func _area(p: Vector2) -> String:
	if absf(p.y - Route.BECK_Z) < 14 and p.x > 4.3 and p.x < Route.TANK.x + 15:
		return "BECK LANE"
	if absf(p.y - Route.HOME_Z) < 14 and p.x < -4.3 and p.x > Route.HOME_HOUSE.x - 10:
		return "HOME PLACE"
	if absf(p.x) < 9 and p.y >= Route.ROAD_NORTH_Z and p.y <= Route.ROAD_SOUTH_Z:
		return "COUNTY Q"
	return "OPEN COUNTRY"

func directions() -> void:
	var v: Vector3 = driver.get_truck_position()
	var p := Vector2(v.x,v.z)
	var area := _area(p)
	var words: String
	if driver.stuck:
		words = "You buried her, hon? Grab the shovel and clear the packed snow by the tires. Take it easy coming back up."
	elif stage >= 2:
		if area == "HOME PLACE":
			words = "Come up to the house, hon. I left the kitchen light on for you."
		elif area == "BECK LANE":
			words = "Back out to Q and take a left. It’s a mile south to our drive. Look for our box on the right."
		elif absf(p.y - Route.HOME_Z) < 12 and area == "COUNTY Q":
			words = "That’s our turn. Take the west drive all the way up to the kitchen porch."
		elif p.y > Route.HOME_Z:
			words = "Come north on Q. Turn left at our box. The kitchen light’s on up the drive."
		else:
			words = "Follow Q south. Our mailbox is on the west side. Take the drive up to the house."
	elif stage == 1:
		words = "The Becks’ porch is on the south side of the lane, across from their tank. Park up and give them a knock."
	elif area == "HOME PLACE":
		words = "Come down our drive and turn left on Q. Go a mile north, past the co-op sign, to the Becks’ mailbox."
	elif area == "BECK LANE":
		words = "That’s their lane. Lower the blade and open one truck-width all the way from the mailbox to the tank."
	elif area == "OPEN COUNTRY":
		words = "Look for the telephone poles on Q. The Becks’ turn is on the east side, by their mailbox."
	elif absf(p.y - Route.BECK_Z) < 12:
		words = "You’re at their turn. The lane runs east here. Put the blade down and take it all the way to the tank."
	elif p.y < Route.BECK_Z:
		words = "You’re past them. Come south on Q, then go left at the Beck mailbox."
	elif absf(p.y - Route.COOP_Z) < 40:
		words = "You’re by the co-op sign. Keep north. It’s a little under half a mile to their turn."
	elif p.y < Route.COOP_Z:
		words = "Keep north on Q. The next drive on the right is the Becks’. Look for the red flag on their box."
	else:
		words = "Head north on Q past the co-op sign. Take the east drive at the Beck mailbox."
	say("DEB   /   CB 19",words,8)

func check_job() -> void:
	var v: Vector3 = driver.get_driver_position()
	var p := Vector2(v.x,v.z)
	if driver.in_cab:
		say("IN THE CAB","Park and get out to knock at the porch.",3)
	elif stage==1 and p.distance_to(Route.BECK_PORCH)<=PORCH_REACH:
		stage = 2
		say("MRS. BECK   /   AT THE DOOR","Oh, thank goodness. We were down to a quarter tank. Tell Deb I still have her pie plate.",8)
	elif stage==2 and p.distance_to(Route.HOME_PORCH)<=PORCH_REACH:
		stage = 3
		say("DEB   /   AT HOME","There you are. Leave your boots by the stove, hon. I kept the coffee hot.",10)
	elif p.distance_to(Route.BECK_PORCH)<=PORCH_REACH:
		say("AT THE BECKS’ DOOR","You can still see the ridge from the door. The propane truck needs a clear run." if stage==0 else "Through the window, Mrs. Beck waves you on home.",5)
	elif p.distance_to(Route.HOME_PORCH)<=PORCH_REACH:
		say("DEB   /   AT HOME","Coffee’s hot whenever you want it. The Becks are counting on you." if stage<3 else "Sit a little. It can snow without us for a minute.",6)
	else:
		say("OUTSIDE","Get close enough to reach the porch door.",2.5)
	hud.stage = stage

func update_job_progress() -> void:
	if stage!=0 or last_revision==snow.revision:
		return
	last_revision = snow.revision
	hud.opened = snow.open_length()
	if hud.opened>=Route.FULL_LANE:
		stage = 1
		hud.stage = 1
		if not mic_down:
			say("DEB   /   CB 19","They can get a truck in there now. Would you knock at the porch across from the tank? I’d sleep better.",9)
			soundscape.play_cue("radio_squelch")

func _physics_process(delta: float) -> void:
	town.set_truck_pose(driver.get_truck_position(), driver.get_forward(), driver.get_truck_up())
	driver.set_storm_strength(town.gust_strength)
	soundscape.set_gust(town.gust_strength)
	if mode!="drive":
		return
	var truck_at: Vector3 = driver.get_truck_position()
	driver.set_snowbank_contact(not snow.on_surface(Vector2(truck_at.x, truck_at.z)))
	_shovel_wheels(delta)
	var blade_tip: Vector3 = driver.get_blade_position()
	var forward: Vector3 = driver.get_forward()
	var ahead := blade_tip + forward*.5
	var p := Vector2(ahead.x,ahead.z)
	var on_road: bool = snow.on_surface(p)
	var uncut: float = 1.0-snow.clearance(p)
	driver.snow_load = (.28 if on_road else .9)*uncut
	if driver.in_cab and driver.blade_down and driver.speed_mps>.15:
		driver.snow_load = (.62 if on_road else 1.0)*uncut
		if snow.cut(blade_tip,forward):
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
	hud.area = _area(pos)
	hud.stage = stage
	hud.mph = roundi(absf(driver.speed_mps)*2.237)
	hud.low_grip = driver.speed_mps > Driver.GRIP_LIMIT
	hud.cab = driver.in_cab
	hud.blade = driver.blade_down
	hud.prompt = ""
	if driver.stuck and driver.in_cab:
		hud.prompt = "Wheels buried · Exit cab to shovel" if touch_enabled else "Wheels buried · [E] Get out to shovel"
	elif driver.can_dig_out():
		hud.prompt = "Hold SHOVEL to dig out the wheels" if touch_enabled else "Hold [F] to dig out the wheels"
		if stroke_time > 0 or cleared_scoops > 0:
			hud.prompt += "  ·  %d/%d" % [cleared_scoops, SHOVEL_STROKES]
	elif driver.stuck:
		hud.prompt = "Walk up beside a buried wheel"
	elif not driver.in_cab and (pos.distance_to(Route.BECK_PORCH)<=PORCH_REACH or pos.distance_to(Route.HOME_PORCH)<=PORCH_REACH):
		hud.prompt = "[X]  Knock at the porch" if stage!=2 or pos.distance_to(Route.HOME_PORCH)>PORCH_REACH else "[X]  Join Deb for coffee"
	elif not driver.in_cab and player.distance_to(driver.get_truck_position())<4:
		hud.prompt = "[E]  Climb into the cab"
	elif stage==0 and driver.in_cab and not driver.blade_down and hud.area=="BECK LANE":
		hud.prompt = "[B]  Lower the blade"
	elif mic_down:
		hud.prompt = "Transmitting  ·  release R to listen"
	if touch_enabled and hud.prompt!="":
		hud.prompt = hud.prompt.replace("[X]  ","").replace("[E]  ","").replace("[B]  ","").replace("release R to listen","release the mic to listen")
	hud.set_cold(driver.cold)
	if message_left>0:
		message_left -= delta
		if message_left<=0:
			hud.subtitle = ""
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
	soundscape.shutdown()
	# Let the audio mixer release its decoded MP3 buffers before the engine exits.
	await get_tree().create_timer(.25,true,false,true).timeout
	get_tree().quit()
