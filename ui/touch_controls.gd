extends Control

const LETTERING := Color("#eee7d5")
const RUBBER := Color("#292e2e")
const RUBBER_RIB := Color("#535856")
const RECESS := Color("#161d1e")
const BEZEL := Color("#626963")
const ALLOY := Color("#8d9386")
const LIGHT_EDGE := Color("#a3a496")
const INSCRIPTION := Color("#d0cbb6")
const HONEY := Color("#e0a254")
const LEVER_RED := Color("#ad5c43")
const MOUSE_FINGER := -10
const STEERING: Array[StringName] = [&"steer_left", &"steer_right"]
const PEDALS: Array[StringName] = [&"reverse", &"accelerate"]

var shift: Node
var _buttons: Dictionary[StringName, Rect2] = {}
var _held: Dictionary[int, StringName] = {}
var _slide_group: Dictionary[int, Array] = {}
var _gameplay := false
var _in_cab := true
var _blade_down := false
var _near_truck := false
var _job_label := ""
var _unit := 1.0
var _safe := Rect2()
var _font: Font

func setup(session: Node) -> void:
	shift = session
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = load("res://ui/fonts/BarlowCondensed-Bold.ttf") as Font
	_sync()
	visible = _gameplay

func _process(_delta: float) -> void:
	_sync()

func _sync() -> void:
	if not is_instance_valid(shift) or shift.driver == null:
		return
	var playing: bool = shift.mode == "drive"
	if playing != _gameplay:
		_gameplay = playing
		if not playing:
			_clear_fingers()
		visible = playing
		queue_redraw()
	var cab: bool = shift.driver.in_cab
	var blade: bool = shift.driver.blade_down
	var driver_position: Vector3 = shift.driver.get_driver_position()
	var near: bool = not cab and driver_position.distance_to(shift.driver.get_truck_position()) <= 4.2
	var action_text: String = "" if cab else shift.field_action_label().to_upper()
	var safe := _safe_rect()
	if safe != _safe or cab != _in_cab or blade != _blade_down or near != _near_truck or action_text != _job_label or _buttons.is_empty():
		_safe = safe
		_in_cab = cab
		_blade_down = blade
		_near_truck = near
		_job_label = action_text
		_layout()
		for id in _held.keys():
			if _held[id] != &"" and not _buttons.has(_held[id]):
				_end(id)
		queue_redraw()

func _safe_rect() -> Rect2:
	var result := Rect2(Vector2.ZERO, size)
	if not OS.has_feature("mobile") or not is_inside_tree() or size.x <= 0:
		return result
	# DisplayServer returns physical display pixels; the HUD lives in logical viewport units.
	var available := DisplayServer.get_display_safe_area()
	var window_rect := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	var usable := available.intersection(window_rect)
	if not usable.has_area() or not window_rect.has_area():
		return result
	var scale_to_hud := size / Vector2(window_rect.size)
	return Rect2(Vector2(usable.position - window_rect.position) * scale_to_hud, Vector2(usable.size) * scale_to_hud)

func _layout() -> void:
	_buttons.clear()
	if not _safe.has_area():
		return
	_unit = minf(_safe.size.x / 960.0, _safe.size.y / 540.0)
	var span := _safe.size / _unit
	var bottom := span.y - 10.0
	_place(&"steer_left", Rect2(12, bottom - 106, 116, 106))
	_place(&"steer_right", Rect2(128, bottom - 106, 116, 106))
	_place(&"reverse", Rect2(span.x - 250, bottom - 106, 116, 106))
	_place(&"accelerate", Rect2(span.x - 126, bottom - 118, 114, 118))
	# Keep the speed counter and subtitle column clear between the two thumbs.
	var row_y := bottom - 96.0
	if _in_cab:
		_place(&"blade", Rect2(256, row_y, 76, 78))
		_place(&"interact", Rect2(340, row_y, 86, 78))
		_place(&"dispatch", Rect2(span.x - 367, row_y, 105, 78))
		_place(&"camera_view", Rect2(span.x - 380, 14, 80, 69))
		_place(&"horn", Rect2(span.x - 292, 14, 80, 69))
	else:
		if _near_truck:
			_place(&"interact", Rect2(256, row_y, 112, 78))
		if not _job_label.is_empty():
			_place(&"job", Rect2(span.x - 374, row_y, 112, 78))
	_place(&"plat", Rect2(span.x - 198, 14, 94, 69))
	_place(&"pause_shift", Rect2(span.x - 96, 14, 84, 69))

func _place(action: StringName, r: Rect2) -> void:
	_buttons[action] = Rect2(_safe.position + r.position * _unit, r.size * _unit)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(shift):
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.canceled or not event.pressed:
			if _held.has(event.index):
				_end(event.index)
				get_viewport().set_input_as_handled()
		elif shift.mode == "drive" and _start(event.index, p):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _held.has(event.index):
		_drag(event.index, get_global_transform_with_canvas().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouse and shift.mode == "drive":
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		# Android can synthesize a mouse event after a real touch. It must not operate a control twice.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			if not _held.is_empty() or _at(p) != &"":
				get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _start(MOUSE_FINGER, p):
				get_viewport().set_input_as_handled()
			elif not event.pressed and _held.has(MOUSE_FINGER):
				_end(MOUSE_FINGER)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and _held.has(MOUSE_FINGER):
			_drag(MOUSE_FINGER, p)
			get_viewport().set_input_as_handled()

func _at(p: Vector2) -> StringName:
	for action in _buttons:
		if _buttons[action].has_point(p):
			return action
	return &""

func _start(id: int, position_in_hud: Vector2) -> bool:
	var action := _at(position_in_hud)
	if action == &"":
		return false
	if _held.has(id):
		_end(id)
	if action in STEERING:
		_slide_group[id] = STEERING
	elif action in PEDALS:
		_slide_group[id] = PEDALS
	var already_down := action in _held.values()
	_held[id] = action
	if not already_down:
		_emit_action(action, true)
	queue_redraw()
	return true

func _drag(id: int, p: Vector2) -> void:
	if not _slide_group.has(id):
		return
	var current := _held[id]
	var next := _at(p)
	if next not in _slide_group[id]:
		next = &""
	# Keep control through a narrow gap or a few pixels of finger drift.
	if next == &"" and current != &"" and _buttons.has(current) and _buttons[current].grow(10 * _unit).has_point(p):
		return
	if current == next:
		return
	_held[id] = &""
	if current != &"" and not current in _held.values():
		_emit_action(current, false)
	var already_down := next in _held.values()
	_held[id] = next
	if next != &"" and not already_down:
		_emit_action(next, true)
	queue_redraw()

func _end(id: int) -> void:
	var action := _held[id]
	_held.erase(id)
	_slide_group.erase(id)
	if action != &"" and not action in _held.values():
		_emit_action(action, false)
	queue_redraw()

func _emit_action(action: StringName, down: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	event.strength = 1.0 if down else 0.0
	Input.parse_input_event(event)

func _clear_fingers() -> void:
	for id in _held.keys():
		_end(id)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE]:
		_clear_fingers()

func _draw() -> void:
	if not _gameplay or _buttons.is_empty() or _font == null:
		return
	# Hardware dimensions below are in logical HUD units. Touch targets retain the full safe-area bounds.
	draw_set_transform(_safe.position, 0.0, Vector2.ONE * _unit)
	var left := _local_button(&"steer_left")
	var right := _local_button(&"steer_right")
	_steering_controls(left.merge(right))
	_pedal(_local_button(&"reverse"), false, &"reverse" in _held.values())
	_pedal(_local_button(&"accelerate"), true, &"accelerate" in _held.values())
	if _in_cab:
		_switch_panel()
		_handset(_local_button(&"dispatch"), &"dispatch" in _held.values())
		_key_face(&"camera_view")
		_key_face(&"horn")
	else:
		for action in [&"interact", &"job"]:
			if _buttons.has(action):
				_key_face(action)
	_map_tab(_local_button(&"plat"))
	_pause_control(_local_button(&"pause_shift"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _local_button(action: StringName) -> Rect2:
	var r := _buttons[action]
	return Rect2((r.position - _safe.position) / _unit, r.size / _unit)


func _chamfer(r: Rect2, radius: float, color: Color) -> void:
	var p := r.position
	var q := r.end
	var points := PackedVector2Array([
		Vector2(p.x + radius,p.y), Vector2(q.x - radius,p.y), Vector2(q.x,p.y + radius),
		Vector2(q.x,q.y - radius), Vector2(q.x - radius,q.y), Vector2(p.x + radius,q.y),
		Vector2(p.x,q.y - radius), Vector2(p.x,p.y + radius)])
	draw_colored_polygon(points, color)


func _screw(p: Vector2) -> void:
	draw_circle(p, 2.4, RECESS)
	draw_circle(p - Vector2(0.3,0.5), 1.9, ALLOY)
	draw_line(p + Vector2(-0.9,0.9), p + Vector2(1.0,-1.0), RUBBER, 0.85, true)


func _label(r: Rect2, wording: String, font_size: int, y: float, color: Color) -> void:
	draw_string(_font, Vector2(r.position.x, y), wording, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, font_size, color)


func _steering_controls(r: Rect2) -> void:
	# A single sprung rocker can be rolled straight across with the thumb.
	var center := r.get_center()
	var plate := r.grow(-3)
	_chamfer(plate, 13, RECESS)
	_chamfer(plate.grow(-1.3), 12, BEZEL)
	_chamfer(plate.grow(-3.1), 10, RUBBER)
	for sign_x: int in [-1,1]:
		var pressed := (&"steer_left" if sign_x < 0 else &"steer_right") in _held.values()
		var x := center.x + sign_x * r.size.x * 0.25
		var y := center.y + (3 if pressed else 0)
		var p := Vector2(x,y)
		var direction := Vector2(sign_x, 0)
		var key_size := Vector2(r.size.x * 0.5 - 16, r.size.y - 26)
		var key := Rect2(p - key_size * 0.5, key_size)
		_chamfer(key, 10, Color("#414847") if not pressed else Color("#313736"))
		draw_line(key.position + Vector2(10,1), Vector2(key.end.x - 10,key.position.y + 1), RUBBER_RIB, 2, true)
		for i in range(3):
			var grip := p + direction * (26 + i * 4)
			draw_line(grip - Vector2(0,12), grip + Vector2(0,12), RUBBER, 2)
		draw_polyline(PackedVector2Array([p - direction * 8 + Vector2(0,-14), p + direction * 7, p - direction * 8 + Vector2(0,14)]), HONEY if pressed else LETTERING, 4, true)


func _pedal(r: Rect2, gas: bool, pressed: bool) -> void:
	var c := r.get_center() + Vector2(0,2 if pressed else 0)
	var face_size := Vector2(r.size.x - (20 if gas else 6), r.size.y - (8 if gas else 16))
	var shape := Rect2(c - face_size * 0.5, face_size)
	# The narrow accelerator has long channels; the wider brake has transverse ribs.
	_chamfer(Rect2(shape.position + Vector2(-1,3), shape.size), 7, Color(0.08,0.10,0.10,0.72))
	_chamfer(shape, 7, ALLOY if not pressed else HONEY)
	_chamfer(shape.grow(-1.4), 6, RUBBER)
	var top := shape.position.y
	if gas:
		for i in range(5):
			var x := shape.position.x + shape.size.x * (i + 1) / 6.0
			draw_line(Vector2(x + 1,top + 10),Vector2(x - 1,shape.end.y - 32),RECESS,4,true)
			draw_line(Vector2(x,top + 10),Vector2(x - 2,shape.end.y - 32),RUBBER_RIB,1.2,true)
	else:
		for i in range(5):
			var y := top + 11.0 + i * 9.0
			draw_line(Vector2(shape.position.x + 12,y),Vector2(shape.end.x - 12,y),RUBBER_RIB,2.8)
			draw_line(Vector2(shape.position.x + 12,y + 2.2),Vector2(shape.end.x - 12,y + 2.2),RECESS,1.5)
	var title := ("GAS" if gas else "BRAKE / REV") if _in_cab else ("WALK" if gas else "BACK")
	_label(shape, title, 20 if gas else 18, shape.end.y - 8, HONEY if pressed else LETTERING)


func _switch_panel() -> void:
	var plate := _local_button(&"blade").merge(_local_button(&"interact")).grow(1.5)
	_chamfer(Rect2(plate.position + Vector2(0,2.8), plate.size), 5, Color(0.08,0.10,0.10,0.71))
	_chamfer(plate, 5, ALLOY)
	_chamfer(plate.grow(-1.2), 4, Color("#414b48"))
	draw_line(Vector2(plate.position.x + 7,plate.position.y + 2),Vector2(plate.end.x - 7,plate.position.y + 2),LIGHT_EDGE,0.9)
	for x: float in [plate.position.x + 4.3, plate.end.x - 4.3]:
		_screw(Vector2(x,plate.position.y + 5))
		_screw(Vector2(x,plate.end.y - 5))
	_blade_lever(_local_button(&"blade"))
	_push_key(_local_button(&"interact"),&"interact",&"interact" in _held.values())


func _key_face(action: StringName) -> void:
	var r := _local_button(action)
	_chamfer(r.grow(-1), 5, BEZEL)
	_push_key(r, action, action in _held.values())


func _blade_lever(r: Rect2) -> void:
	var c := r.get_center()
	var x := c.x - 12
	var top := r.position.y
	_chamfer(Rect2(x - 9,top + 9,18,39),5,ALLOY)
	_chamfer(Rect2(x - 7,top + 11,14,35),4,RECESS)
	var end := Vector2(x, top + (42 if _blade_down else 14))
	draw_line(Vector2(x,top + 29),end,Color("#b3b5a4"),5,true)
	draw_circle(end + Vector2(0,1),7.5,RECESS)
	draw_circle(end,6.75,LEVER_RED)
	draw_line(end + Vector2(-2,-1.6),end + Vector2(2,-1.6),Color("#df8d65"),1.2)
	var legend := Rect2(c.x - 1,0,25,20)
	_label(legend,"UP",13,top + 21,HONEY if not _blade_down else INSCRIPTION)
	_label(legend,"DN",13,top + 46,HONEY if _blade_down else INSCRIPTION)
	_label(r,"PLOW",18,r.end.y - 6,LETTERING)


func _push_key(r: Rect2, action: StringName, down: bool) -> void:
	var c := r.get_center()
	var key_size := Vector2(r.size.x * 0.7, r.size.y - 34.0)
	var key := Rect2(c.x - key_size.x * 0.5,r.position.y + 6,key_size.x,key_size.y)
	_chamfer(key, 3, RECESS)
	_chamfer(Rect2(key.position + Vector2(1.5,2 if down else 0.4),key.size - Vector2(3,3)),2,Color("#757b6b") if down else Color("#929585"))
	draw_line(key.position + Vector2(4,1.4),Vector2(key.end.x - 4,key.position.y + 1.4),Color("#afb09e"),1)
	var p := key.get_center() + Vector2(0,1 if down else -1)
	var ink := RECESS
	var wording := ""
	match action:
		&"camera_view":
			wording = "VIEW"
			draw_rect(Rect2(p - Vector2(7,5),Vector2(14,10)),ink,false,1.4)
			draw_line(p + Vector2(-3,-4),p + Vector2(-3,4),ink,1)
		&"horn":
			wording = "HORN"
			draw_polyline(PackedVector2Array([p + Vector2(-7,2),p + Vector2(-2,2),p + Vector2(5,5),p + Vector2(5,-5),p + Vector2(-2,-2),p + Vector2(-7,-2),p + Vector2(-7,2)]),ink,1.5,true)
		&"interact":
			wording = "EXIT CAB" if _in_cab else "ENTER CAB"
			draw_polyline(PackedVector2Array([p + Vector2(-7,5),p + Vector2(-7,-1),p + Vector2(-3,-5),p + Vector2(7,-5),p + Vector2(7,5),p + Vector2(-7,5)]),ink,1.5,true)
			draw_line(p + Vector2(-5,0),p + Vector2(6,0),ink,1)
			draw_line(p + Vector2(2,2),p + Vector2(5,2),ink,1)
		&"job":
			wording = _job_label
			draw_rect(Rect2(p - Vector2(4,6),Vector2(8,12)),ink,false,1.4)
			draw_circle(p + Vector2(2,1),0.9,ink)
	var point := 18
	while point > 11 and _font.get_string_size(wording, HORIZONTAL_ALIGNMENT_LEFT, -1, point).x > r.size.x - 6:
		point -= 1
	_label(r,wording,point,r.end.y - 6,LETTERING)


func _handset(r: Rect2, down: bool) -> void:
	var h := r.grow(-0.5)
	_chamfer(Rect2(h.position + Vector2(0,2),h.size),9,RECESS)
	_chamfer(h,9,Color("#626660"))
	_chamfer(h.grow(-1.5),7,Color("#333a39"))
	var p := h.position
	var face := Rect2(p.x + 4,p.y + 4,h.size.x - 8,h.size.y - 8)
	_chamfer(face,5,Color("#454b46"))
	for i in range(6):
		var y := p.y + 10.5 + i * 4.4
		draw_line(Vector2(p.x + 10,y),Vector2(p.x + 38,y),RECESS,1.7)
		draw_line(Vector2(p.x + 10,y + 1),Vector2(p.x + 38,y + 1),RUBBER_RIB,0.65)
	var lamp := Vector2(h.end.x - 27,p.y + 14)
	draw_circle(lamp,3.9,RECESS)
	draw_circle(lamp,2.7,Color("#ff7655") if down else Color("#805047"))
	_label(Rect2(h.end.x - 23,p.y,20,20),"TX",12,p.y + 18,INSCRIPTION)
	var switch_box := Rect2(p.x + 8,h.end.y - 31,h.size.x - 16,25)
	_chamfer(switch_box,3,RECESS)
	_chamfer(switch_box.grow(-1),2,Color("#555b54") if not down else RUBBER)
	_label(switch_box,"ON AIR" if down else "HOLD CB",17,switch_box.end.y - 4,HONEY if down else LETTERING)


func _map_tab(r: Rect2) -> void:
	var card := r.grow(-2)
	var p := card.position
	_chamfer(Rect2(p + Vector2(0,2),card.size),3,Color(0.10,0.12,0.11,0.65))
	_chamfer(card,3,Color("#b8ae90"))
	draw_line(p + Vector2(5,4),Vector2(p.x + 5,card.end.y - 4),Color("#8b7d61"),1.1)
	var x := p.x + 19
	var y := card.get_center().y
	draw_polyline(PackedVector2Array([Vector2(x - 6,y + 5),Vector2(x - 6,y - 5),Vector2(x - 2,y - 7),Vector2(x + 2,y - 5),Vector2(x + 6,y - 7),Vector2(x + 6,y + 3),Vector2(x + 2,y + 5),Vector2(x - 2,y + 3),Vector2(x - 6,y + 5)]),RUBBER,1.2,true)
	draw_line(Vector2(x - 2,y - 7),Vector2(x - 2,y + 3),RUBBER,0.9)
	_label(Rect2(p.x + 28,p.y,card.size.x - 31,card.size.y),"PLAT",18,y + 6,RECESS)


func _pause_control(r: Rect2) -> void:
	var face := r.grow(-3)
	_chamfer(face,6,BEZEL)
	_chamfer(face.grow(-1.4),5,RUBBER)
	var center := Vector2(face.position.x + 15,face.get_center().y)
	draw_circle(center,7.8,RECESS)
	draw_line(center + Vector2(-2.3,-3.6),center + Vector2(-2.3,3.6),INSCRIPTION,1.6)
	draw_line(center + Vector2(2.3,-3.6),center + Vector2(2.3,3.6),INSCRIPTION,1.6)
	_label(Rect2(face.position.x + 24,face.position.y,face.size.x - 27,face.size.y),"PAUSE",16,center.y + 6,INSCRIPTION)
