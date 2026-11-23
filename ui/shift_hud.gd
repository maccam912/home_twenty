extends Control

signal menu_action(action: String)
const Route = preload("res://world/route.gd")
const TYPE := preload("res://ui/fonts/CourierPrime-Regular.ttf")
const PENCIL := preload("res://ui/fonts/Kalam-Regular.ttf")
const GAUGE := preload("res://ui/fonts/BarlowCondensed-Bold.ttf")
const MILK := Color("#e6e1ca")
const PENCIL_INK := Color("#2a4148")
const BLUE_RULE := Color("#95a8a4")
const RED_INK := Color("#825448")
const DASH := Color("#262b29")
const SPEEDO := Color("#d9d9b4")
const MAP_WIDTH := 960.0
const MAP_HEIGHT := 540.0
var mode := "title"
var touch_enabled := false
var opened := 0
var target_length := 0
var work_order: Dictionary = {}:
	set(value):
		if book != null and work_order.get("site") != value.get("site"):
			book.open_order(value)
		work_order = value
		queue_redraw()
var completed_jobs := 0
var cab := true
var blade := false
var mph := 0
var low_grip := false
var area := "COUNTY Q"
var mic := false
var prompt := ""
var speaker := ""
var subtitle := ""
var hover := Vector2(-1,-1)
var cold_fx: ShaderMaterial
var book
var ignition

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	book = load("res://ui/plat_book.gd").new()
	book.open_order(work_order)
	ignition = load("res://ui/ignition_menu.gd").new()
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cold_fx = ShaderMaterial.new()
	cold_fx.shader = preload("res://ui/film.gdshader")
	overlay.material = cold_fx
	overlay.show_behind_parent = true
	add_child(overlay)

func set_cold(value:float) -> void:
	cold_fx.set_shader_parameter("exposure_cold",value)

func _scale_factor() -> float:
	return minf(size.x/MAP_WIDTH,size.y/MAP_HEIGHT)

func _origin() -> Vector2:
	return (size-Vector2(MAP_WIDTH,MAP_HEIGHT)*_scale_factor())*.5

func _gui_input(event:InputEvent) -> void:
	var press := false
	if event is InputEventScreenTouch:
		hover = (event.position-_origin())/_scale_factor()
		press = event.pressed and not event.canceled
	elif event is InputEventMouse:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		hover = (event.position-_origin())/_scale_factor()
		press = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	else:
		return
	if mode=="drive":
		return
	queue_redraw()
	if press:
		var choice: String = book.hit(hover) if mode=="book" else ignition.hit_test(hover)
		if not choice.is_empty():
			accept_event()
			if choice == "sheet":
				book.next_sheet(work_order)
			elif choice != "browse":
				menu_action.emit(choice)

func _input(event: InputEvent) -> void:
	if mode != "book" or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_V: book.next_sheet(work_order)
		KEY_LEFT: book.browse(Vector2i.LEFT)
		KEY_RIGHT: book.browse(Vector2i.RIGHT)
		KEY_UP: book.browse(Vector2i.UP)
		KEY_DOWN: book.browse(Vector2i.DOWN)
		_: return
	queue_redraw()
	get_viewport().set_input_as_handled()

func _text(x:float,y:float,value:String,font:Font,point:int,color:Color) -> void:
	draw_string(font,Vector2(x,y),value,HORIZONTAL_ALIGNMENT_LEFT,-1,point,color)

func _line(x:float,y:float,u:float,v:float,color:Color,width:=1.0) -> void:
	draw_line(Vector2(x,y),Vector2(u,v),color,width,true)

func _paper(points:PackedVector2Array,color:Color) -> void:
	draw_colored_polygon(points,color)

func _rect(x:float,y:float,w:float,h:float,color:Color) -> void:
	draw_rect(Rect2(x,y,w,h),color)

func _draw() -> void:
	draw_set_transform(_origin(),0,Vector2.ONE*_scale_factor())
	if mode=="title" or mode=="pause":
		ignition.draw(self,mode,hover,touch_enabled)
	elif mode=="book":
		book.draw(self)
	else:
		_dispatch_slip()
		if cab:
			_instruments()
		if not subtitle.is_empty():
			_subtitles()
		if not prompt.is_empty():
			var y := 396 if touch_enabled else 453
			_caption(prompt,Vector2(480,y),TYPE,15,Color("#ffdfab"),4)

func _dispatch_slip() -> void:
	if work_order.is_empty():
		return
	# A torn copy of Deb's work order tucked under the edge of the visor.
	var base := Vector2(22,10)
	draw_set_transform(_origin()+base*_scale_factor(),-.032,Vector2.ONE*_scale_factor())
	var edge := PackedVector2Array([Vector2(1,0),Vector2(234,1),Vector2(232,68),Vector2(211,67),Vector2(208,70),Vector2(186,68),Vector2(180,71),Vector2(159,68),Vector2(144,70),Vector2(121,68),Vector2(102,70),Vector2(82,68),Vector2(67,70),Vector2(52,68),Vector2(35,69),Vector2(19,67),Vector2(0,69)])
	var shadow := edge.duplicate()
	for i in shadow.size():
		shadow[i] += Vector2(2,3)
	_paper(shadow,Color(.08,.1,.09,.38))
	_paper(edge,Color("#c0b79b"))
	_rect(6,2,1,64,Color("#b6af98"))
	_line(12,24,224,24,BLUE_RULE,.8)
	_line(12,49,223,49,BLUE_RULE,.8)
	var site: Dictionary = Route.SITES[work_order.site]
	var detail: String = site.road.to_upper()
	if work_order.legs > 1:
		detail += "   ·   STOP %d/%d" % [work_order.leg, work_order.legs]
	if target_length > 0:
		detail += "   %d/%d M" % [opened, target_length]
	_fit(13,19,site.name.to_upper(),TYPE,13,140,RED_INK)
	_text(162,18,"CALL %02d" % (completed_jobs + 1),GAUGE,12,Color("#686e60"))
	_fit(13,46,work_order.title,PENCIL,25,207,PENCIL_INK)
	_fit(13,63,detail,TYPE,12,207,Color("#3b524e"))
	# Fold, crimp and the dark wire of a spring clip.
	_paper(PackedVector2Array([Vector2(218,1),Vector2(234,1),Vector2(233,16)]),Color("#bcb49a"))
	_line(79,-5,99,-4,Color("#333d3b"),4.0)
	_line(77,-4,79,5,Color("#606767"),2)
	_line(79,5,97,5,Color("#858a80"),1.0)
	draw_set_transform(_origin(),0,Vector2.ONE*_scale_factor())

func _fit(x: float, y: float, value: String, font: Font, point: int, width: float, color: Color) -> void:
	while point > 11 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, point).x > width:
		point -= 1
	draw_string(font, Vector2(x, y), value, HORIZONTAL_ALIGNMENT_LEFT, width, point, color)

func _instruments() -> void:
	if touch_enabled:
		# The controls are their own cab hardware. Put speed on the small counter between them.
		_odometer(452,513,mph)
		return
	var center := Vector2(59,520)
	draw_circle(center+Vector2(1,1),54,Color("#161c1b"),true,-1,true)
	draw_circle(center,51,Color("#5b625a"),true,-1,true)
	draw_circle(center,48,DASH,true,-1,true)
	draw_arc(center,44,deg_to_rad(154),deg_to_rad(383),37,Color("#7c8070"),1.1,true)
	draw_arc(center,44,deg_to_rad(267.5),deg_to_rad(380),22,Color("#d99b56"),1.8,true)
	for i in range(15):
		var angle := deg_to_rad(155.0+i*(225.0/14.0))
		var outer := Vector2.from_angle(angle)
		var major := i%2==0
		draw_line(center+outer*(35 if major else 39),center+outer*43,SPEEDO,1.6 if major else .8,true)
		if major and i<14:
			var pos := center+outer*29+Vector2(0,3)
			_center(str(i*5),pos,GAUGE,10,SPEEDO)
	var a := deg_to_rad(155+clampf(mph,0,70)/70*225)
	var arm := Vector2.from_angle(a)
	draw_line(center-arm*6,center+arm*35,Color("#d17641"),2.4,true)
	draw_circle(center,3.7,Color("#979b8e"),true,-1,true)
	_text(51,534,"MPH",GAUGE,10,SPEEDO)
	# Textured Dymo strip and blade telltale are stuck to the cluster's right edge.
	_paper(PackedVector2Array([Vector2(114,513),Vector2(220,510),Vector2(221,532),Vector2(113,534)]),Color("#222d29"))
	draw_circle(Vector2(123,523),3.4,Color("#d88d3b") if blade else Color("#627466"))
	_text(132,528,"BLADE  "+("DOWN" if blade else "UP"),TYPE,12,MILK)
	if area in ["HOME PLACE", "COUNTY Q"] and completed_jobs==0 and opened==0 and mph<2:
		_paper(PackedVector2Array([Vector2(261,510),Vector2(716,508),Vector2(713,532),Vector2(258,535)]),Color("#b4af94"))
		_text(273,527,"WASD drive   B blade   E door   R mic   M book",TYPE,14,Color("#324440"))
	_radio_face()

func _odometer(x:float,y:float,speed:int) -> void:
	_rect(x-4,y-1,67,24,DASH)
	for i in 2:
		_rect(x+i*13,y+2,12,18,Color("#131916"))
		_text(x+2+i*13,y+17,("%02d" % speed)[i],GAUGE,17,Color("#ffb464") if low_grip else SPEEDO)
	_text(x+30,y+16,"MPH",GAUGE,12,Color("#b9c1ac"))

func _radio_face() -> void:
	var x := 813
	var y := 495
	_paper(PackedVector2Array([Vector2(x+4,y),Vector2(944,y),Vector2(948,y+5),Vector2(948,y+42),Vector2(x,y+42),Vector2(x,y+5)]),Color("#313734"))
	_line(x+6,y+2,942,y+2,Color("#74786a"),1.2)
	for i in 8:
		_line(x+9+i*4,y+9,x+9+i*4,y+31,Color("#151d1c"),2.1)
	_rect(x+50,y+6,36,29,Color("#161a14"))
	_seven_segment(Vector2(x+53,y+9),1)
	_seven_segment(Vector2(x+68,y+9),9)
	draw_circle(Vector2(x+99,y+13),2.8,Color("#bb4a35") if mic else Color("#583f32"))
	_text(x+104,y+16,"TX",GAUGE,10,MILK)
	draw_circle(Vector2(x+99,y+27),2.8,Color("#a7bc83") if speaker.begins_with("DEB") and subtitle!="" and not mic else Color("#3e4939"))
	_text(x+104,y+30,"RX",GAUGE,10,MILK)
	for pin:Vector2 in [Vector2(x+4,y+5),Vector2(942,y+35)]:
		draw_circle(pin,1.7,Color("#8b9188"))

func _seven_segment(p:Vector2,n:int) -> void:
	var seg := [Vector4(2,0,8,0),Vector4(10,2,10,8),Vector4(10,12,10,18),Vector4(2,20,8,20),Vector4(0,12,0,18),Vector4(0,2,0,8),Vector4(2,10,8,10)]
	for i in 7:
		var lit := (i in [1,2]) if n==1 else (i!=4)
		var line:Vector4 = seg[i]
		draw_line(p+Vector2(line.x,line.y),p+Vector2(line.z,line.w),Color("#e39145") if lit else Color("#382f22"),1.9,true)

func _center(value:String,p:Vector2,font:Font,point:int,tint:Color) -> void:
	var w := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,point).x
	_text(p.x-w*.5,p.y,value,font,point,tint)

func _caption(value:String,p:Vector2,font:Font,point:int,tint:Color,outline:int) -> void:
	var w := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,point).x
	var start := Vector2(roundf(p.x-w*.5),p.y)
	draw_string_outline(font,start,value,HORIZONTAL_ALIGNMENT_LEFT,-1,point,outline,Color(.035,.05,.05,.9))
	draw_string(font,start,value,HORIZONTAL_ALIGNMENT_LEFT,-1,point,tint)

func _subtitles() -> void:
	var rows := PackedStringArray()
	for paragraph in subtitle.split("\n"):
		var row := ""
		for word in paragraph.split(" "):
			var candidate := word if row.is_empty() else row+" "+word
			if GAUGE.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,23).x>590 and not row.is_empty():
				rows.append(row)
				row=word
			else:
				row=candidate
		rows.append(row)
	var bottom := 359 if touch_enabled else 431
	var top := bottom-26*(rows.size()-1)
	_caption(speaker.replace("   /   ","  ·  "),Vector2(480,top-24),TYPE,13,Color("#f5d7a5"),3)
	for i in rows.size():
		_caption(rows[i],Vector2(480,top+i*26),GAUGE,23,Color("#fff5d9"),4)
