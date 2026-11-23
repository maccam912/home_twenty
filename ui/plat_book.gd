extends RefCounted

## Draws inside the caller's 960 × 540 HUD coordinate system.
const Route = preload("res://world/route.gd")
const Dispatch = preload("res://game/dispatch.gd")
const LETTER := preload("res://ui/fonts/BarlowCondensed-Bold.ttf")
const TYPE := preload("res://ui/fonts/CourierPrime-Regular.ttf")
const HAND := preload("res://ui/fonts/Kalam-Regular.ttf")
const CHARCOAL := Color("#3c392f")
const FADED := Color("#655f4c")
const RED := Color("#8e362c")
const PENCIL := Color("#354953")
const PAPER := Color("#d7cba9")
const CLOSE := Rect2(752, 463, 148, 44)
const SHEET := Rect2(375, 54, 161, 44)
const YARD_SCALE := 4.5
const MAP_FRAME := Rect2(58,110,477,302)

const SHEETS_PER_SIDE := 4
const PLATE := Rect2(73,124,276,276)
const MILE := 1609.344
const PRINT_GREEN := Color("#687658")
const ROAD_PAPER := Color("#e9dec0")
const SELECTION := Color("#8d3e30")

var page := "county"
var section := Vector2i(2,2)
var sites_by_cell: Dictionary = {}
var landmarks_by_cell: Dictionary = {}
var landmarks: Array = Route.LANDMARKS.duplicate()
var surfaces: Array = Route.surfaces()
var canvas: Control
var grain: Texture2D
var mottling: Texture2D


func _init() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 818
	noise.frequency = 0.79
	grain = ImageTexture.create_from_image(noise.get_image(720, 410))
	noise.frequency = 0.035
	mottling = ImageTexture.create_from_image(noise.get_image(368, 211))

	for id: String in Route.SITES:
		var cell := cell_for(Route.SITES[id].yard)
		if not sites_by_cell.has(cell):
			sites_by_cell[cell] = []
		sites_by_cell[cell].append(id)
	landmarks.append({"name":"Home place","position":Route.HOME_PORCH})
	landmarks.append({"name":"Co-op sign","position":Vector2(9.3,Route.COOP_Z)})
	for landmark: Dictionary in landmarks:
		var cell := cell_for(landmark.position)
		if not landmarks_by_cell.has(cell):
			landmarks_by_cell[cell] = []
		landmarks_by_cell[cell].append(landmark)


static func cell_for(position: Vector2) -> Vector2i:
	var fraction := (position - Route.COUNTY_BOUNDS.position) / Route.COUNTY_BOUNDS.size
	return Vector2i((fraction * SHEETS_PER_SIDE).floor()).clampi(0,SHEETS_PER_SIDE-1)


static func cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65+cell.x),cell.y+1]


func open_order(order: Dictionary) -> void:
	page = "county"
	section = cell_for(Route.HOME_PORCH if order.is_empty() else Route.SITES[order.site].yard)


func browse(direction: Vector2i) -> void:
	if page == "yard":
		page = "section"
	section = (section+direction).clampi(0,SHEETS_PER_SIDE-1)


func next_sheet(order: Dictionary) -> void:
	if page == "county":
		page = "section"
	elif page == "section" and has_assigned_yard(order):
		page = "yard"
	else:
		page = "county"


func has_assigned_yard(order: Dictionary) -> bool:
	return not order.is_empty() and section == cell_for(Route.SITES[order.site].yard)


func hit(point: Vector2) -> String:
	if CLOSE.has_point(point):
		return "close"
	if SHEET.has_point(point):
		return "sheet"
	if page == "county" and PLATE.has_point(point):
		section = Vector2i(((point-PLATE.position)/PLATE.size*SHEETS_PER_SIDE).floor())
		page = "section"
		return "browse"
	return ""


func draw(hud: Control) -> void:
	canvas = hud
	var order: Dictionary = hud.work_order
	var site_id := String(order.get("site", ""))
	canvas.draw_rect(Rect2(-3000, -2000, 7000, 5000), Color(.04,.045,.04,.68))
	_paper()
	_text(Vector2(59,55),"MARATHON COUNTY, WISCONSIN", TYPE, 13)
	var title := "COUNTY ROAD ATLAS"
	var tab := "Section " + cell_name(section)
	if page == "section":
		title = "SECTION " + cell_name(section)
		tab = "Yard detail" if has_assigned_yard(order) else "County map"
	elif page == "yard":
		title = "YARD DETAIL"
		tab = "County map"
	_text(Vector2(57,92),title,LETTER,40)
	_paper_tab(SHEET,tab,"" if hud.touch_enabled else "V",SHEET.has_point(hud.hover))
	_line(Vector2(59,100),Vector2(535,100),CHARCOAL,1.6)
	if page == "county":
		_county_plat(site_id,hud.touch_enabled)
	elif page == "section":
		_section_plat(site_id,hud.touch_enabled)
	else:
		_yard_detail(order)
	_text(Vector2(616,87),"Deb’s list", HAND, 39, PENCIL)
	if order.is_empty():
		_text(Vector2(616,119),"WINTER ’98   /   CB CH. 19",TYPE,13,FADED)
		_wrapped(Vector2(614,178),"Start the truck, hon. I’ll give you the first call on nineteen.",HAND,24,269,29,PENCIL)
	else:
		_work_order(hud)
	_paperclip()
	_legend(hud.touch_enabled, CLOSE.has_point(hud.hover))
	canvas = null


func _paper_tab(bounds: Rect2, label: String, key: String, over: bool) -> void:
	var face := bounds.grow_individual(-2,-5,-2,-4)
	canvas.draw_rect(face,Color("#c5b487") if over else Color("#d4c49c"))
	canvas.draw_rect(face,Color("#a49570"),false)
	_line(face.position + Vector2(2,2),Vector2(face.end.x-2,face.position.y+2),Color("#e4d7b5"))
	_text(face.position + Vector2(12,23),label,LETTER,20)
	if not key.is_empty():
		var width := TYPE.get_string_size(key,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
		_text(Vector2(face.end.x-width-10,face.position.y+22),key,TYPE,12,FADED)


func _text(pos: Vector2, words: String, font: Font, size: int, color: Color = CHARCOAL) -> void:
	canvas.draw_string(font, pos, words, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _line(a: Vector2, b: Vector2, ink: Color = CHARCOAL, width: float = 1.0) -> void:
	canvas.draw_line(a, b, ink, width, true)


func _path(points: Array, ink: Color, width: float = 1.0) -> void:
	canvas.draw_polyline(PackedVector2Array(points), ink, width, true)


func _polygon(points: Array, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array(points), color)


func _paper() -> void:
	var spread := Rect2(35,25,890,477)
	# Four unequal panel edges and one curled corner show the folded map thickness.
	for i in range(9, 0, -1):
		canvas.draw_rect(Rect2(35+i, 26+i, 890, 477), Color(.08,.065,.045,.075))
	_polygon([Vector2(34,27),Vector2(553,23),Vector2(922,28),Vector2(927,490),Vector2(909,505),Vector2(552,501),Vector2(36,505)],Color("#a79775"))
	_polygon([Vector2(34,25),Vector2(551,22),Vector2(923,26),Vector2(925,489),Vector2(907,502),Vector2(553,497),Vector2(36,501)],PAPER)
	canvas.draw_texture_rect(mottling, spread, false, Color(.53,.38,.19,.18))
	canvas.draw_texture_rect(grain, spread, false, Color(.74,.70,.54,.16))
	# A crease across the printed sheet, then the softened fold at the spine.
	_path([Vector2(36,301),Vector2(163,299),Vector2(357,300),Vector2(551,297)],Color(.31,.27,.18,.13),2)
	_path([Vector2(36,302),Vector2(163,300),Vector2(357,301),Vector2(551,298)],Color(.99,.93,.75,.48),1)
	for i in range(17):
		var tint := (17.0-i)/17.0
		_line(Vector2(552-i,24),Vector2(554-i,498),Color(.24,.20,.13,tint*.18))
		_line(Vector2(553+i,24),Vector2(555+i,497),Color(1,.94,.73,tint*.25))
	# Dispatch pad laid over the map's reverse, with a loose torn top from the pad.
	var slip := [Vector2(576,44),Vector2(626,45),Vector2(635,43),Vector2(647,45),Vector2(765,42),Vector2(804,43),Vector2(833,41),Vector2(899,44),Vector2(899,468),Vector2(572,469)]
	_polygon([Vector2(580,49),Vector2(901,46),Vector2(905,471),Vector2(575,473)],Color(.25,.20,.13,.28))
	_polygon(slip,Color("#ecdcb8"))
	canvas.draw_texture_rect(grain,Rect2(578,45,319,421),false,Color(.61,.52,.34,.12))
	for y in range(105,452,22):
		_line(Vector2(575,y),Vector2(898,y-2),Color(.32,.47,.51,.28))
	_line(Vector2(600,46),Vector2(597,468),Color(.62,.31,.28,.40))
	_line(Vector2(603,46),Vector2(600,468),Color(.63,.33,.27,.24))
	# A faint coffee-ring crescent, outside the writing area.
	canvas.draw_arc(Vector2(866,392),30,deg_to_rad(-54),deg_to_rad(132),22,Color(.53,.36,.17,.12),2.4,true)
	canvas.draw_arc(Vector2(866,392),32,deg_to_rad(-22),deg_to_rad(82),14,Color(.53,.36,.17,.10),1,true)
	_polygon([Vector2(907,502),Vector2(909,489),Vector2(925,489)],Color("#efe3c3"))
	_line(Vector2(907,502),Vector2(909,489),Color(.38,.31,.19,.38))


func _yard_detail(order: Dictionary) -> void:
	var site: Dictionary = Route.SITES[order.site]
	var frame := MAP_FRAME
	canvas.draw_rect(frame,Color(.91,.87,.70,.33))
	var lane: Vector2 = site.yard - site.mouth
	var vertical := absf(lane.y) > absf(lane.x)
	var scale := minf(2.4,(174.0 if vertical else 210.0)/lane.length())
	var mouth: Vector2 = frame.get_center() - lane * scale * 0.5
	var yard: Vector2 = mouth + lane * scale
	var stop: Vector2 = yard + (site.stop-site.yard) * YARD_SCALE
	var left := frame.position.x
	var right := frame.end.x
	var top := frame.position.y
	var bottom := frame.end.y
	# Survey hatching and fence lines outside the draw-in distinguish fields from the yard.
	for corner: Vector2 in [frame.position+Vector2(3,3), frame.end-Vector2(66,37)]:
		for row in 8:
			var at := corner + Vector2(row*6,0)
			_line(at,at+Vector2(15,30),Color(.39,.43,.29,.25))
	var road_a := Vector2(left+1,mouth.y) if vertical else Vector2(mouth.x,top+1)
	var road_b := Vector2(right-1,mouth.y) if vertical else Vector2(mouth.x,bottom-1)
	_line(road_a,road_b,CHARCOAL,8)
	_line(road_a,road_b,Color("#d3c6a4"),5)
	for bounds: Array in surfaces:
		var apron := Rect2(bounds[0], bounds[1]-bounds[0])
		if apron.has_point(site.yard):
			var plan := Rect2(yard+(apron.position-site.yard)*YARD_SCALE,apron.size*YARD_SCALE)
			canvas.draw_rect(plan,Color("#c7bb98"))
			canvas.draw_rect(plan,FADED,false,1)
			break
	_line(mouth,yard,Color("#7f7966"),6)
	_line(mouth,yard,Color("#dfd4b3"),3.8)
	var lane_mid := mouth.lerp(yard,.45)
	var lane_label := lane_mid + (Vector2(10,0) if vertical else Vector2(-19,-7))
	_text(lane_label,"drive",HAND,17,FADED)
	var road_label := Vector2(left+13,mouth.y-9) if vertical else Vector2(mouth.x+8,bottom-18)
	_text(road_label,site.road.to_upper(),TYPE,13)
	if order.kind == "plow":
		var direction := mouth.direction_to(yard)
		var half_width := direction.orthogonal()*3.0
		var tip := yard - direction * 12
		canvas.draw_dashed_line(mouth + direction*6,tip,RED,1.3,5)
		_path([tip-direction*7+half_width,tip,tip-direction*7-half_width],RED,1.4)
	elif order.kind == "windrow":
		var pile := Route.pile_path(order.site)
		var ink := Color("#a0522c")
		var mark_a: Vector2 = yard + (pile[0]-site.yard)*YARD_SCALE
		var mark_b: Vector2 = yard + (pile[1]-site.yard)*YARD_SCALE
		var across := mark_a.direction_to(mark_b).orthogonal() * 2.4
		_line(mark_a,mark_b,ink,3.5)
		_line(mark_a-across,mark_a+across,ink,2)
		_line(mark_b-across,mark_b+across,ink,2)
		_line(Vector2(left+18,top+17),Vector2(left+33,top+17),ink,3.5)
		_text(Vector2(left+39,top+21),"staked bay",TYPE,13,ink)
	canvas.draw_circle(stop,3.3,RED,true,-1,true)
	canvas.draw_arc(stop,8.5,-.28,5.84,24,RED,1.5,true)
	var fixture: String = Dispatch.fixture_for(order.site).trim_prefix("the ")
	var width := HAND.get_string_size(fixture,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
	var text_at := stop + Vector2(18,26)
	if text_at.x+width > right-12:
		text_at.x = stop.x-width-19
	if text_at.y > bottom-8:
		text_at.y = stop.y-14
	var end := Vector2(text_at.x+width+2 if text_at.x < stop.x else text_at.x-3,text_at.y-5)
	_line(stop.lerp(end,.34),end,RED)
	_text(text_at,fixture,HAND,18,RED)
	_north_arrow(Vector2(505,146))
	canvas.draw_rect(frame,Color("#78705a"),false,1.2)
	_site_caption(site)


func _section_bounds() -> Rect2:
	var size := Route.COUNTY_BOUNDS.size / SHEETS_PER_SIDE
	return Rect2(Route.COUNTY_BOUNDS.position + Vector2(section)*size,size)


func _local_view(ids: Array, local_marks: Array) -> Rect2:
	var nominal := _section_bounds().grow(270)
	var stations := PackedVector2Array()
	for id: String in ids:
		stations.append(Route.SITES[id].yard)
		stations.append(Route.SITES[id].mouth)
	for landmark: Dictionary in local_marks:
		stations.append(landmark.position)
	for junction: Vector2 in Route.junctions():
		if nominal.has_point(junction):
			stations.append(junction)
	if stations.is_empty():
		return nominal
	var interest := Rect2(stations[0],Vector2.ZERO)
	for station in stations:
		interest = interest.expand(station)
	# Individual sheets fit the inhabited stretch and its crossings, with a fresh scale bar.
	var side := clampf(maxf(interest.size.x,interest.size.y)+540,1650,nominal.size.x)
	return Rect2(interest.get_center()-Vector2.ONE*side*.5,Vector2.ONE*side)


func _on_paper(world: Vector2, bounds: Rect2) -> Vector2:
	return PLATE.position + (world-bounds.position)*PLATE.size/bounds.size


func _plate(bounds: Rect2) -> void:
	canvas.draw_rect(PLATE,Color(.91,.87,.70,.33))
	# Light survey rules continue between sheets. They divide the land at one-mile intervals.
	var rule := Color(.42,.39,.29,.19)
	for i in range(1,8):
		var survey := Route.COUNTY_BOUNDS.position + Vector2(i,i)*1600
		var p := _on_paper(survey,bounds)
		if p.x > PLATE.position.x and p.x < PLATE.end.x:
			_line(Vector2(p.x,PLATE.position.y),Vector2(p.x,PLATE.end.y),rule)
		if p.y > PLATE.position.y and p.y < PLATE.end.y:
			_line(Vector2(PLATE.position.x,p.y),Vector2(PLATE.end.x,p.y),rule)
	canvas.draw_rect(PLATE,FADED,false,1)


func _roads(bounds: Rect2, local: bool) -> Array:
	var visible := []
	# All survey roads follow section lines. Clip their centerlines at the printed border.
	for road: Dictionary in Route.ROADS:
		var lo: Vector2 = Vector2(road.a).min(road.b).max(bounds.position)
		var hi: Vector2 = Vector2(road.a).max(road.b).min(bounds.end)
		if lo.x > hi.x or lo.y > hi.y:
			continue
		var a := _on_paper(lo,bounds)
		var b := _on_paper(hi,bounds)
		var major: bool = road.kind == "county"
		visible.append({"name":road.name,"major":major,"a":a,"b":b})
		_line(a,b,CHARCOAL,(4.3 if local else 3.4) if major else (2.3 if local else 1.8))
	for road: Dictionary in visible:
		if road.major:
			_line(road.a,road.b,ROAD_PAPER,1.6)
	return visible


func _mark_roads(roads: Array, used: Array[Rect2], local: bool) -> void:
	for road: Dictionary in roads:
		var a: Vector2 = road.a
		var b: Vector2 = road.b
		if a.distance_to(b) < (29 if local else 95):
			continue
		var title: String = String(road.name).replace(" Road"," Rd.").to_upper()
		var width := LETTER.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
		var offsets := [Vector2(-width*.5,-4),Vector2(-width*.5,14),Vector2(-width*.5,-15)]
		if is_equal_approx(a.x,b.x):
			offsets = [Vector2(4,-2),Vector2(-width-4,-2)]
		var label := Rect2()
		for offset: Vector2 in offsets:
			for fraction: float in [.48,.22,.77,.08,.92]:
				var pos := a.lerp(b,fraction)+offset
				pos.x = clampf(pos.x,PLATE.position.x+3,PLATE.end.x-width-3)
				pos.y = clampf(pos.y,PLATE.position.y+12,PLATE.end.y-2)
				var area := Rect2(pos-Vector2(1,10),Vector2(width+2,12))
				var free := true
				for other: Rect2 in used:
					if area.intersects(other):
						free = false
						break
				if free:
					label = area
					break
			if label.has_area():
				break
		if label.has_area():
			canvas.draw_rect(label,Color(PAPER,.82))
			_text(label.position+Vector2(1,10),title,LETTER,12,FADED)
			used.append(label)


func _county_plat(active: String, touch: bool) -> void:
	var bounds := Route.COUNTY_BOUNDS
	_plate(bounds)
	var cell_size := PLATE.size/SHEETS_PER_SIDE
	var selected := Rect2(PLATE.position+Vector2(section)*cell_size,cell_size)
	canvas.draw_rect(selected,Color(RED,.08))
	var roads := _roads(bounds,false)
	for i in SHEETS_PER_SIDE:
		var tick := PLATE.position + (Vector2(i,i)+Vector2(.5,.5))*cell_size
		_text(Vector2(tick.x-4,120),String.chr(65+i),TYPE,13,FADED)
		_text(Vector2(59,tick.y+4),str(i+1),TYPE,13,FADED)
		if i > 0:
			var p := PLATE.position + Vector2(i,i)*cell_size
			canvas.draw_dashed_line(Vector2(p.x,PLATE.position.y),Vector2(p.x,PLATE.end.y),Color(FADED,.54),1,4)
			canvas.draw_dashed_line(Vector2(PLATE.position.x,p.y),Vector2(PLATE.end.x,p.y),Color(FADED,.54),1,4)
	for site: Dictionary in Route.SITES.values():
		var mouth := _on_paper(site.mouth,bounds)
		var point := mouth+Vector2(site.mouth).direction_to(site.yard)*4.2
		_line(mouth,point,CHARCOAL,.9)
		canvas.draw_rect(Rect2(point-Vector2(1.8,1.8),Vector2(3.6,3.6)),CHARCOAL)
	var used: Array[Rect2] = []
	for landmark: Dictionary in landmarks:
		var point := _on_paper(landmark.position,bounds)
		_path([point+Vector2(-2.6,1),point+Vector2(0,-3.8),point+Vector2(2.6,1)],PRINT_GREEN,1.6)
	if not active.is_empty():
		var site: Dictionary = Route.SITES[active]
		var point := _on_paper(site.mouth,bounds)+Vector2(site.mouth).direction_to(site.yard)*4.2
		canvas.draw_arc(point,6.8,-.3,5.87,22,RED,1.6,true)
		used.append(Rect2(point-Vector2(8,8),Vector2(16,16)))
	_mark_roads(roads,used,false)
	canvas.draw_rect(selected.grow(-1.4),SELECTION,false,1.45)
	_text(Vector2(365,143),"WINTER 1998",TYPE,13,FADED)
	_line(Vector2(364,151),Vector2(532,151),FADED)
	_text(Vector2(363,179),"Sheet "+cell_name(section),LETTER,26)
	var district := Route.region_at(_section_bounds().get_center())
	_text(Vector2(363,200),district,HAND,19,PENCIL)
	_wrapped(Vector2(365,236),"Tap a square to open its section." if touch else "Click a square, or use arrows and V.",TYPE,14,164,18,CHARCOAL)
	_line(Vector2(365,294),Vector2(385,294),CHARCOAL,3.8)
	_line(Vector2(365,294),Vector2(385,294),ROAD_PAPER,1.4)
	_text(Vector2(394,298),"County highway",TYPE,12)
	_line(Vector2(365,316),Vector2(385,316),CHARCOAL,1.8)
	_text(Vector2(394,320),"Town road",TYPE,12)
	canvas.draw_rect(Rect2(373,335,4,4),CHARCOAL)
	_text(Vector2(394,341),"Contract yard",TYPE,12)
	_path([Vector2(371,358),Vector2(375,351),Vector2(379,358)],PRINT_GREEN,1.6)
	_text(Vector2(394,359),"Landmark",TYPE,12)
	_scale_bar(bounds,2)
	if active.is_empty():
		_text(Vector2(59,440),"MARATHON COUNTY   /   WINTER ROAD INDEX",TYPE,14)
		_text(Vector2(59,469),"Our base is on County Q just south of School Road.",HAND,20,PENCIL)
	else:
		_site_caption(Route.SITES[active])


func _section_plat(active: String, touch: bool) -> void:
	var ids: Array = sites_by_cell.get(section,[])
	var local_marks: Array = landmarks_by_cell.get(section,[])
	var bounds := _local_view(ids,local_marks)
	_plate(bounds)
	var roads := _roads(bounds,true)
	var used: Array[Rect2] = []
	var selected_site := active if active in ids else ""
	var line_y := 150
	_text(Vector2(365,129),"PROPERTY INDEX",TYPE,13,FADED)
	_line(Vector2(364,136),Vector2(532,136),FADED)
	for i in ids.size():
		var id: String = ids[i]
		var site: Dictionary = Route.SITES[id]
		var point := _on_paper(site.yard,bounds)
		_line(_on_paper(site.mouth,bounds),point,CHARCOAL,1.5)
		var color := RED if id == selected_site else CHARCOAL
		var marker := str(i+1)
		_print_marker(point,marker,color,used)
		_text(Vector2(365,line_y+5),marker,TYPE,13,color)
		_fit(Vector2(386,line_y+5),site.name,LETTER,18,145,color)
		line_y += 20
	if ids.is_empty():
		_text(Vector2(365,line_y+5),"Open country",HAND,18,FADED)
		line_y += 20
	if not local_marks.is_empty():
		line_y += 12
		_text(Vector2(365,line_y),"LANDMARKS",TYPE,12,FADED)
		line_y += 19
		for i in local_marks.size():
			var landmark: Dictionary = local_marks[i]
			var letter := String.chr(97+i)
			var point := _on_paper(landmark.position,bounds)
			_print_marker(point,letter,PRINT_GREEN,used)
			_text(Vector2(365,line_y),letter,TYPE,13,PRINT_GREEN)
			_fit(Vector2(386,line_y),landmark.name,HAND,17,144,PRINT_GREEN)
			line_y += 19
	_mark_roads(roads,used,true)
	_scale_bar(bounds,.5 if PLATE.size.x*MILE/bounds.size.x > 136 else 1.0)
	if selected_site.is_empty():
		_text(Vector2(59,439),"%s   /   SHEET %s" % [Route.region_at(_section_bounds().get_center()).to_upper(),cell_name(section)],TYPE,14)
		_text(Vector2(59,470),"Choose another square on the county map." if touch else "Arrow keys turn to the neighboring sheet.",HAND,21,PENCIL)
	else:
		_site_caption(Route.SITES[active])


func _print_marker(point: Vector2, mark: String, color: Color, used: Array[Rect2]) -> void:
	# The number can sit beside a cramped driveway. A short rule keeps it tied to the true site.
	var center := point
	for offset: Vector2 in [Vector2.ZERO,Vector2(0,-11),Vector2(10,-8),Vector2(11,5),Vector2(-10,7),Vector2(-10,-8),Vector2(0,14)]:
		center = (point+offset).clamp(PLATE.position+Vector2(8,8),PLATE.end-Vector2(8,8))
		var area := Rect2(center-Vector2(7,7),Vector2(14,14))
		var clear := true
		for other: Rect2 in used:
			if other.intersects(area):
				clear = false
				break
		if clear:
			break
	if center.distance_to(point)>7:
		_line(point,center,color,1.1)
	canvas.draw_circle(center,6.8,color,true,-1,true)
	canvas.draw_string(LETTER,center+Vector2(-7,4.3),mark,HORIZONTAL_ALIGNMENT_CENTER,14,13,Color("#f4ead2"))
	used.append(Rect2(center-Vector2(7,7),Vector2(14,14)))


func _scale_bar(bounds: Rect2, miles: float) -> void:
	var width := PLATE.size.x/bounds.size.x*MILE*miles
	var start := Vector2(366,389)
	var end := start+Vector2(width,0)
	_line(start,end,CHARCOAL,2)
	_line(start-Vector2(0,4),start+Vector2(0,2),CHARCOAL)
	_line(end-Vector2(0,4),end+Vector2(0,2),CHARCOAL)
	_text(start-Vector2(1,8),"½ MILE" if miles < 1 else ("%d MILE%s" % [int(miles),"S" if miles>1 else ""]),TYPE,12,FADED)
	_path([Vector2(521,391),Vector2(521,373),Vector2(517,379),Vector2(521,373),Vector2(525,379)],CHARCOAL)
	_text(Vector2(517,370),"N",LETTER,13)


func _north_arrow(at: Vector2) -> void:
	_text(at+Vector2(-4,-13),"N",LETTER,16)
	_path([at+Vector2(0,-8),at+Vector2(-6,11),at+Vector2(0,7),at+Vector2(6,11),at+Vector2(0,-8)],CHARCOAL)
	_line(at+Vector2(0,-6),at+Vector2(0,25),CHARCOAL)


func _site_caption(site: Dictionary) -> void:
	_text(Vector2(59,438),"%s   /   %s" % [site.road.to_upper(),site.name],TYPE,14)
	_fit(Vector2(58,470),"Look for " + site.landmark + ".",HAND,23,473,RED)


func _work_order(hud: Control) -> void:
	var order: Dictionary = hud.work_order
	var site: Dictionary = Route.SITES[order.site]
	_text(Vector2(616,117),"CALL %02d   /   PLAT %s" % [hud.completed_jobs + 1, cell_name(cell_for(site.yard))],TYPE,13,FADED)
	var bottom := _wrapped(Vector2(614,155),order.title,HAND,29,271,27,PENCIL)
	var next_y := maxf(196,bottom+13)
	_fit(Vector2(616,next_y),site.name.to_upper(),LETTER,20,269,CHARCOAL)
	next_y = _wrapped(Vector2(616,next_y+21),site.road,TYPE,14,267,16,FADED)
	_line(Vector2(615,next_y+1),Vector2(876,next_y),Color(RED,.36))
	next_y += 29
	if order.legs > 1:
		_text(Vector2(616,next_y),"STOP %d OF %d" % [order.leg,order.legs],TYPE,12,RED)
		next_y += 24
	_wrapped(Vector2(614,next_y),order.instruction,HAND,21,270,23,PENCIL)
	if hud.target_length > 0:
		_text(Vector2(615,400),"%d of %d m open" % [hud.opened,hud.target_length],HAND,21,RED)


func _fit(pos: Vector2, wording: String, font: Font, point: int, width: float, ink: Color) -> void:
	while point > 10 and font.get_string_size(wording,HORIZONTAL_ALIGNMENT_LEFT,-1,point).x > width:
		point -= 1
	canvas.draw_string(font,pos,wording,HORIZONTAL_ALIGNMENT_LEFT,width,point,ink)


func _wrapped(pos: Vector2, words: String, font: Font, point: int, width: float, leading: int, ink: Color) -> float:
	var line := ""
	for word in words.split(" ", false):
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,point).x > width:
			_text(pos,line,font,point,ink)
			pos.y += leading
			line = word
		else:
			line = candidate
	_text(pos,line,font,point,ink)
	return pos.y + leading


func _paperclip() -> void:
	# An actual bent-wire paper clip catches both sheets at the upper right.
	var clip := [Vector2(855,59),Vector2(854,37),Vector2(856,30),Vector2(861,28),Vector2(865,31),Vector2(866,63),Vector2(864,70),Vector2(859,72),Vector2(855,68),Vector2(855,48)]
	_path(clip,Color(.15,.13,.10,.63),3.0)
	_path(clip,Color("#b3a98e"),1.45)


func _legend(touch: bool, over: bool) -> void:
	_text(Vector2(616,431),"Pedals  /  Blade  /  Door" if touch else "WASD drive  B blade  E door  C view",TYPE,12)
	_text(Vector2(616,450),"Hold CB for directions" if touch else "Hold R for directions   X work",TYPE,12)
	var tab := [Vector2(753,468),Vector2(897,466),Vector2(900,495),Vector2(891,502),Vector2(754,503)]
	_polygon(tab,Color("#713b30") if not over else Color("#a04b38"))
	_line(Vector2(759,472),Vector2(891,470),Color(.97,.85,.59,.45))
	_text(Vector2(769,490),"CLOSE BOOK",LETTER,19,Color("#fbefd2"))
	if not touch:
		_text(Vector2(872,490),"M",TYPE,15,Color("#fbefd2"))
