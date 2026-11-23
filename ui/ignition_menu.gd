extends RefCounted

const START := Rect2(49, 324, 346, 62)
const PLAT := Rect2(49, 391, 346, 51)
const PAPER := Color("#e9e9ce")
const SECONDARY := Color("#c2cdb7")
const INK := Color("#283c30")
const LIVERY := preload("res://ui/art/door_livery.webp")
const STEEL := preload("res://ui/art/menu_steel.svg")
const KEY := preload("res://ui/art/menu_ignition.svg")
const STAMP := preload("res://ui/fonts/BarlowCondensed-Bold.ttf")
const TYPE := preload("res://ui/fonts/CourierPrime-Regular.ttf")
const HAND := preload("res://ui/fonts/Kalam-Regular.ttf")

func hit_test(point: Vector2) -> String:
	if START.has_point(point):
		return "begin"
	if PLAT.has_point(point):
		return "book"
	return ""

func draw(hud: Control, mode: String, hover: Vector2, touch_enabled: bool) -> void:
	var panel := Rect2(22, 29, 414, 467)
	hud.draw_texture_rect(STEEL, panel, false)
	var artwork := Rect2(42, 53, 374, 209)
	var fitted := LIVERY.get_size() * minf(artwork.size.x / LIVERY.get_width(), artwork.size.y / LIVERY.get_height())
	hud.draw_texture_rect(LIVERY, Rect2(artwork.get_center() - fitted*0.5, fitted), false)
	var paused := mode == "pause"
	_word(hud, Vector2(51, 289), "Route paused." if paused else "“What’s your twenty, hon?”", HAND, 24, PAPER)
	_word(hud, Vector2(51, 310), "MARATHON COUNTY, WIS.", TYPE, 13, SECONDARY)
	var year := "WINTER 1998"
	var year_width := TYPE.get_string_size(year, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_word(hud, Vector2(401-year_width, 310), year, TYPE, 13, SECONDARY)
	_ignition(hud, paused, START.has_point(hover), touch_enabled)
	_plat_book(hud, PLAT.has_point(hover), touch_enabled)

func _ignition(h: Control, paused: bool, hovered: bool, touch: bool) -> void:
	# A recessed steel key escutcheon mounted below the painted part of the door.
	var rim := PackedVector2Array([Vector2(55,327),Vector2(381,327),Vector2(390,334),Vector2(390,378),Vector2(384,384),Vector2(55,384),Vector2(48,378),Vector2(48,334)])
	h.draw_colored_polygon(rim, Color("#81917e") if hovered else Color("#677b69"))
	var inset := PackedVector2Array([Vector2(57,328),Vector2(379,328),Vector2(388,335),Vector2(388,377),Vector2(382,382),Vector2(56,382),Vector2(50,377),Vector2(50,335)])
	h.draw_colored_polygon(inset, Color("#334b3d") if hovered else Color("#24382e"))
	h.draw_line(Vector2(57,382), Vector2(381,382), Color("#15261d"), 1.8)
	h.draw_line(Vector2(58,329), Vector2(378,329), Color("#9da892",0.64), 0.8)
	h.draw_line(Vector2(117,335), Vector2(117,375), Color("#6d7f69",0.62), 0.9)
	h.draw_texture_rect(KEY, Rect2(48,325,70,63), false)
	_word(h, Vector2(130,366), "RESUME ROUTE" if paused else "START THE TRUCK", STAMP, 27, PAPER)
	if touch:
		_arrow(h, Vector2(365,356), PAPER)
	else:
		_keycap(h, Vector2(338,345), "ENTER", SECONDARY)
	_screw(h, Vector2(382,333), 2.0)
	_screw(h, Vector2(382,377), 2.0)

func _plat_book(h: Control, hovered: bool, touch: bool) -> void:
	# The angled fore edge and three folded panels identify a paper map even at phone size.
	var shadow := PackedVector2Array([Vector2(54,400),Vector2(381,397),Vector2(390,404),Vector2(387,436),Vector2(51,440)])
	h.draw_colored_polygon(shadow, Color("#13261b",0.72))
	var backing := PackedVector2Array([Vector2(54,397),Vector2(379,394),Vector2(389,401),Vector2(385,434),Vector2(51,437)])
	h.draw_colored_polygon(backing, Color("#8e9982"))
	var paper := PackedVector2Array([Vector2(55,395),Vector2(378,392),Vector2(387,400),Vector2(383,432),Vector2(52,436)])
	h.draw_colored_polygon(paper, Color("#e9e5ca") if hovered else Color("#cfceaf"))
	h.draw_line(Vector2(57,397),Vector2(375,394),Color("#f0e8cc"),1)
	h.draw_line(Vector2(56,432),Vector2(381,429),Color("#969d82"),0.9)
	h.draw_line(Vector2(110,398), Vector2(109,430), Color("#929b80"),1)
	var a := PackedVector2Array([Vector2(65,406),Vector2(75,402),Vector2(85,405),Vector2(97,401),Vector2(96,421),Vector2(85,425),Vector2(75,422),Vector2(64,427)])
	h.draw_colored_polygon(a, Color("#819279"))
	h.draw_polyline(PackedVector2Array([Vector2(65,406),Vector2(75,402),Vector2(85,405),Vector2(97,401),Vector2(96,421),Vector2(85,425),Vector2(75,422),Vector2(64,427),Vector2(65,406)]), INK, 1.2, true)
	h.draw_polyline(PackedVector2Array([Vector2(67,420),Vector2(75,416),Vector2(83,416),Vector2(88,410),Vector2(94,408)]), Color("#f2d3a2"), 1.5, true)
	h.draw_line(Vector2(75,403),Vector2(75,421),Color("#536d56"),1.0)
	h.draw_line(Vector2(85,405),Vector2(85,424),Color("#536d56"),1.0)
	_word(h, Vector2(129,423), "OPEN PLAT BOOK", STAMP, 24, INK)
	if touch:
		_arrow(h, Vector2(366,412), INK)
	else:
		_keycap(h, Vector2(355,402), "M", INK)

func _arrow(h: Control, center: Vector2, color: Color) -> void:
	h.draw_polyline(PackedVector2Array([center+Vector2(-3,-6), center+Vector2(3,0), center+Vector2(-3,6)]), color, 1.7, true)

func _keycap(h: Control, pos: Vector2, label: String, color: Color) -> void:
	var w := maxf(21,TYPE.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x + 8)
	var r := Rect2(pos,Vector2(w,18))
	h.draw_rect(r,Color(color,0.46),false,0.9)
	h.draw_string(TYPE, pos+Vector2(0,12.5), label,HORIZONTAL_ALIGNMENT_CENTER,w,10,color)

func _screw(h: Control, p: Vector2, r: float) -> void:
	h.draw_circle(p, r, Color("#83917e"), true, -1, true)
	h.draw_line(p+Vector2(-r*0.68,r*0.38),p+Vector2(r*0.68,-r*0.38),Color("#354c3d"),0.8,true)

func _word(h: Control, pos: Vector2, text: String, font: Font, point: int, color: Color) -> void:
	h.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, point, color)
