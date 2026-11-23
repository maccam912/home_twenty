extends RefCounted

## Draws inside the caller's 960 × 540 HUD coordinate system.
const LETTER := preload("res://ui/fonts/BarlowCondensed-Bold.ttf")
const TYPE := preload("res://ui/fonts/CourierPrime-Regular.ttf")
const HAND := preload("res://ui/fonts/Kalam-Regular.ttf")
const CHARCOAL := Color("#3c392f")
const FADED := Color("#655f4c")
const RED := Color("#8e362c")
const PENCIL := Color("#354953")
const PAPER := Color("#d7cba9")
const CLOSE := Rect2(752, 463, 148, 44)

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


func hit(point: Vector2) -> String:
	return "close" if CLOSE.has_point(point) else ""


func draw(target: Control, stage: int, opened: int, touch: bool, hover: Vector2) -> void:
	canvas = target
	canvas.draw_rect(Rect2(-3000, -2000, 7000, 5000), Color(.04,.045,.04,.68))
	_paper()
	_plat()
	_dispatch(stage, opened)
	_legend(touch, CLOSE.has_point(hover))
	canvas = null


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


func _plat() -> void:
	_text(Vector2(59,55),"MARATHON COUNTY, WISCONSIN", TYPE, 13)
	_text(Vector2(57,92),"TOWNSHIP PLAT", LETTER, 44)
	_text(Vector2(429,64),"FIELD COPY", TYPE, 13, RED)
	_text(Vector2(462,85),"1998", TYPE, 18, RED)
	_line(Vector2(59,100),Vector2(535,100),CHARCOAL,1.6)
	var frame := Rect2(58,110,477,302)
	canvas.draw_rect(frame,Color(.91,.87,.70,.33))
	# Parcel names lie inside their boundaries. The building symbols follow the same
	# north-up orientation and relative positions as the road and farm models.
	_polygon([Vector2(59,111),Vector2(244,111),Vector2(244,191),Vector2(156,191),Vector2(156,210),Vector2(59,210)],Color(.54,.55,.37,.13))
	_polygon([Vector2(384,111),Vector2(534,111),Vector2(534,203),Vector2(453,203),Vector2(453,163),Vector2(384,163)],Color(.56,.55,.36,.17))
	_polygon([Vector2(59,311),Vector2(155,311),Vector2(155,411),Vector2(59,411)],Color(.62,.52,.32,.14))
	_polygon([Vector2(375,301),Vector2(534,301),Vector2(534,411),Vector2(400,411),Vector2(400,350),Vector2(375,350)],Color(.56,.56,.36,.14))
	for i in range(15):
		var x := 72.0+i*5.5
		_line(Vector2(x,115),Vector2(x+18,136),Color(.33,.39,.27,.20))
	for i in range(14):
		var x := 437.0+i*5
		_line(Vector2(x,355),Vector2(x+22,378),Color(.33,.39,.27,.19))
	# Small coppice symbols mark the distant tree lines at the edges of the playable farms.
	for cluster: Vector2 in [Vector2(82,285),Vector2(103,289),Vector2(489,178),Vector2(505,184),Vector2(91,385)]:
		for i in range(4):
			var tip := cluster + Vector2(i*3.3,sin(float(i)*3.7)*3.1)
			_path([tip+Vector2(-2.4,4.2),tip,tip+Vector2(2.4,4.2)],Color(.25,.32,.22,.49))
	var lot := Color("#827d63")
	_path([Vector2(59,210),Vector2(156,210),Vector2(156,191),Vector2(245,191)],lot)
	_path([Vector2(59,266),Vector2(141,266),Vector2(141,311),Vector2(245,311)],lot)
	_path([Vector2(59,311),Vector2(155,311),Vector2(155,411)],lot)
	_path([Vector2(250,163),Vector2(453,163),Vector2(453,203),Vector2(534,203)],lot)
	_line(Vector2(384,111),Vector2(384,163),lot)
	_path([Vector2(250,277),Vector2(375,277),Vector2(375,301),Vector2(534,301)],lot)
	_path([Vector2(250,350),Vector2(400,350),Vector2(400,411)],lot)
	_line(Vector2(375,301),Vector2(375,350),lot)
	_text(Vector2(74,157),"E. Halvorsen",TYPE,12,FADED)
	_text(Vector2(71,247),"J. Mertens",TYPE,12,FADED)
	_text(Vector2(70,344),"L. Zajac",TYPE,12,FADED)
	_text(Vector2(389,141),"A. Nowak",TYPE,12,FADED)
	_text(Vector2(421,260),"Beck family",TYPE,12,FADED)
	_text(Vector2(316,330),"H. Lindquist",TYPE,12,FADED)
	# The county right of way is double-ruled. Private spurs use a single line.
	canvas.draw_rect(Rect2(244,111,7,300),Color("#b5a989"))
	_line(Vector2(244,111),Vector2(244,411),CHARCOAL,1.4)
	_line(Vector2(251,111),Vector2(251,411),CHARCOAL,1.4)
	_line(Vector2(252,205),Vector2(356,205),CHARCOAL,1.8)
	_line(Vector2(246,373),Vector2(207,373),CHARCOAL,1.6)
	# Silo, barn, house and propane tank are recognizable in a small cartographic key.
	canvas.draw_rect(Rect2(292,150,10,6),CHARCOAL)
	canvas.draw_circle(Vector2(327,146),3.1,CHARCOAL)
	_text(Vector2(271,137),"barn & silo",HAND,14,PENCIL)
	canvas.draw_rect(Rect2(343,233,11,6),CHARCOAL)
	canvas.draw_rect(Rect2(200,369,10,8),CHARCOAL)
	_capsule(Vector2(351,189),8)
	canvas.draw_rect(Rect2(263,282,8,4),CHARCOAL)
	_line(Vector2(267,285),Vector2(267,290),CHARCOAL)
	_text(Vector2(278,290),"co-op sign",HAND,16,PENCIL)
	canvas.draw_rect(Rect2(263,213,3.5,3.5),RED)
	_text(Vector2(265,195),"Beck lane",HAND,18,RED)
	_text(Vector2(370,191),"propane tank",HAND,16,PENCIL)
	_line(Vector2(358,190),Vector2(368,187),PENCIL)
	_text(Vector2(369,233),"porch",HAND,17,PENCIL)
	_line(Vector2(355,235),Vector2(367,230),PENCIL)
	_text(Vector2(167,356),"our place",HAND,17,RED)
	canvas.draw_arc(Vector2(206,372),11.5,-.25,5.92,23,Color(RED,.85),1.35,true)
	_text(Vector2(266,227),"mailbox",HAND,14,RED)
	# The red pencil hooks around the mailbox in the direction Deb gives over the CB.
	_path([Vector2(239,291),Vector2(238,268),Vector2(239,234),Vector2(239,216),Vector2(243,210),Vector2(256,207),Vector2(287,207)],Color(RED,.80),1.55)
	_path([Vector2(281,204),Vector2(288,207),Vector2(281,210)],RED,1.35)
	_road_badge(Vector2(248,326))
	_text(Vector2(478,367),"N",LETTER,15)
	_path([Vector2(482,373),Vector2(476,393),Vector2(482,388),Vector2(487,393),Vector2(482,373)],CHARCOAL)
	_line(Vector2(482,375),Vector2(482,403),CHARCOAL)
	canvas.draw_rect(frame,Color("#78705a"),false,1.2)
	for x in [105,169,233,297,361,425,489]:
		_line(Vector2(x,110),Vector2(x,114),FADED)
		_line(Vector2(x,408),Vector2(x,412),FADED)
	for y in [146,194,242,290,338,386]:
		_line(Vector2(58,y),Vector2(62,y),FADED)
		_line(Vector2(531,y),Vector2(535,y),FADED)
	_text(Vector2(59,435),"COUNTY Q",LETTER,17)
	_text(Vector2(133,435),"1838  Beck property",TYPE,13)
	_text(Vector2(59,463),"North on Q, then east at their box.", HAND,23,RED)
	_line(Vector2(60,470),Vector2(362,468),Color(RED,.48))
	_text(Vector2(60,490),"PRIVATE LANES SHOWN BY SINGLE RULE",TYPE,10,FADED)


func _capsule(pos: Vector2, width: float) -> void:
	canvas.draw_rect(Rect2(pos.x-width*.5,pos.y-2,width,4),CHARCOAL)
	canvas.draw_circle(pos-Vector2(width*.5,0),2,CHARCOAL)
	canvas.draw_circle(pos+Vector2(width*.5,0),2,CHARCOAL)


func _road_badge(at: Vector2) -> void:
	var hull := [at+Vector2(-11,-10),at+Vector2(11,-10),at+Vector2(10,3),at+Vector2(0,10),at+Vector2(-10,3)]
	_polygon(hull,CHARCOAL)
	_text(at+Vector2(-4,4),"Q",LETTER,17,Color("#f0e4c7"))


func _dispatch(stage: int, opened: int) -> void:
	_text(Vector2(616,87),"Deb’s list", HAND, 39, PENCIL)
	_text(Vector2(620,119),"BECK PROPERTY  /  #1838", TYPE,15)
	_text(Vector2(620,139),"WINTER ’98       CB CH. 19",TYPE,12,FADED)
	var jobs := ["Clear the tank lane.", "Knock at the porch.", "Home for coffee."]
	var directions := ["Open a truck-width from Q.", "Across the lane from the tank.", "Kitchen door, west side of Q."]
	for i in range(3):
		var y := 184.0 + 69.0*i
		var done := stage > i
		var active := stage == i
		var ink := FADED if done else PENCIL
		_path([Vector2(584,y-14),Vector2(594,y-15),Vector2(594,y-4),Vector2(583,y-3),Vector2(584,y-14)],FADED,1.1)
		if done:
			_path([Vector2(583,y-10),Vector2(587,y-5),Vector2(599,y-20)],RED,2.15)
		_text(Vector2(613,y),jobs[i],HAND,25,ink)
		_text(Vector2(615,y+19),directions[i],TYPE,12,ink)
		if active:
			_line(Vector2(613,y+4),Vector2(613+HAND.get_string_size(jobs[i],HORIZONTAL_ALIGNMENT_LEFT,-1,25).x,y+2),Color(RED,.61),1.3)
	if stage >= 3:
		_text(Vector2(615,400),"All home.  — Deb", HAND,25,RED)
	elif opened > 0 and stage == 0:
		_text(Vector2(615,400),"%d of 36 m open" % opened, HAND,22,RED)
	else:
		_text(Vector2(615,400),"Call me on nineteen.", HAND,22,RED)
	# An actual bent-wire paper clip catches both sheets at the upper right.
	var clip := [Vector2(855,59),Vector2(854,37),Vector2(856,30),Vector2(861,28),Vector2(865,31),Vector2(866,63),Vector2(864,70),Vector2(859,72),Vector2(855,68),Vector2(855,48)]
	_path(clip,Color(.15,.13,.10,.63),3.0)
	_path(clip,Color("#b3a98e"),1.45)


func _legend(touch: bool, over: bool) -> void:
	_text(Vector2(616,431),"Pedals  /  Blade  /  Door" if touch else "WASD drive  B blade  E door  C view",TYPE,12)
	_text(Vector2(616,450),"Hold Mic     Tap Knock at a porch" if touch else "Hold R radio    X knock    H horn",TYPE,12)
	var tab := [Vector2(753,468),Vector2(897,466),Vector2(900,495),Vector2(891,502),Vector2(754,503)]
	_polygon(tab,Color("#713b30") if not over else Color("#a04b38"))
	_line(Vector2(759,472),Vector2(891,470),Color(.97,.85,.59,.45))
	_text(Vector2(769,490),"CLOSE BOOK",LETTER,19,Color("#fbefd2"))
	if not touch:
		_text(Vector2(872,490),"M",TYPE,15,Color("#fbefd2"))
