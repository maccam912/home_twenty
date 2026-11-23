extends RefCounted

const Route = preload("res://world/route.gd")
const Roadside = preload("res://world/roadside.gd")
const Survey = preload("res://world/county_survey.gd")

var town
var cone := CylinderMesh.new()


func _init(township) -> void:
	town = township
	cone.top_radius = 0
	cone.bottom_radius = .5
	cone.height = 1
	cone.radial_segments = 12
	cone.rings = 0


func build() -> void:
	var pump_blue := StandardMaterial3D.new()
	pump_blue.albedo_color = Color("#53768b")
	pump_blue.roughness = .86
	town.mats["pump_blue"] = pump_blue
	for site: Dictionary in Route.SITES.values():
		if Survey.ARCHETYPES.has(site.archetype):
			_property(site)
	for marker: Dictionary in Route.LANDMARKS:
		_landmark(marker)
	for junction: Vector2 in Route.junctions():
		_crossroad(junction)
	for road: Dictionary in Route.ROADS:
		if road.name not in ["Mill Road", "School Road", "Line Road"]:
			_open_road(road)


func _property(site: Dictionary) -> void:
	var heading: Vector2 = site.mouth.direction_to(site.yard)
	var yard := Vector3(site.yard.x, 0, site.yard.y)
	var frame := Transform3D(Basis.looking_at(Vector3(heading.x, 0, heading.y)), yard)
	var variation := int(hash(site.name)) % 5
	var building := frame.translated_local(Vector3(variation - 2, 0, -20 - variation))
	var at := building.origin
	var yaw := building.basis.get_euler().y
	match site.archetype:
		"sugar":
			_shed(building, Vector3(8.2 + variation, 2.8, 6.1), "shed_siding", 1.6)
			_shed(building.translated_local(Vector3(0,3.9,0)), Vector3(4.6,.65,1.9), "creosote", .46)
			for slat in 5:
				_box(building,Vector3(-1.83+slat*.88,4.24,.99),Vector3(.55,.29,.075),"black")
			_box(building,Vector3(-.7,1.11,3.11),Vector3(2.02,2.22,.14),"green")
			town._window(building,Vector3(2.17,1.66,3.12),1.05,.97,0,true)
			_round(building,Vector3(2.6,4.9,-.9),Vector3(.42,4.6,.42),"metal")
			_round(building,Vector3(2.6,7.25,-.9),Vector3(.59,.15,.59),"black")
			_logs(building.translated_local(Vector3(-6.8,0,2)), 3, 2.5)
		"dairy":
			town._barn(at,yaw,Vector3(15 + variation,5.4,10),true)
			town._silo(building * Vector3(-12.3,0,-5), 2.2, 10.7 + variation)
			_shed(building.translated_local(Vector3(9,0,-1)),Vector3(4,2.5,5),"cream_siding",1.15)
		"grain":
			for i in 2 + (variation % 2):
				var bin := building.translated_local(Vector3((i - 1) * 7.2,0,-i * .9))
				var h := 6.8 + (variation + i) % 3
				_round(bin,Vector3.UP*h*.5,Vector3(5.7,h,5.7),"silo")
				for ring in 5:
					_round(bin,Vector3.UP * (.7 + ring * 1.26),Vector3(5.76,.085,5.76),"galv")
				town._shape_at(cone,bin * Transform3D(Basis.from_scale(Vector3(6,2.1,6)),Vector3(0,h+1.05,0)),"snow")
				town._block("Grain bin",bin.origin + Vector3.UP*h*.5,Vector3(4.3,h,4.3),yaw)
			_timber(building,Vector3(6,0,5),Vector3(-3,9,1),.32,"green")
		"garage","fire":
			var engine_house: bool = site.archetype == "fire"
			_shed(building,Vector3(12.6,4.65,8.4),"barn_siding" if engine_house else "shed_siding",1.85)
			for x: float in [-3.15,3.15]:
				_box(building,Vector3(x,1.72,4.27),Vector3(4.76,3.44,.13),"trim")
				for y in 6:
					_box(building,Vector3(x,.32+y*.57,4.35),Vector3(4.58,.039,.045),"metal")
				_box(building,Vector3(x,2.77,4.35),Vector3(3.5,.42,.05),"glass")
			var shop_sign: String = site.name.to_upper()
			_box(building,Vector3(0,4.09,4.29),Vector3(6.9,.62,.15),"green" if not engine_house else "dark_red")
			town._letter(shop_sign,building*Vector3(0,4.09,4.383),yaw,.009)
			if engine_house:
				var tower := building.translated_local(Vector3(-8.15,0,-1))
				_shed(tower,Vector3(3.5,12.15,3.6),"barn_siding",1.65)
				_box(tower,Vector3(0,10.71,1.84),Vector3(1.47,1.74,.09),"black")
				for bar in 6:
					_box(tower,Vector3(0,10.03+bar*.26,1.89),Vector3(1.51,.1,.095),"trim")
			else:
				for i in 3:
					_round(building,Vector3(7.1,.57,2.2-i),Vector3(.69,1.14,.69),"metal")
		"hall":
			_shed(building,Vector3(12,3.2,7.4),"cream_siding",2.2)
			for x: float in [-4.1,-1.7,3.8]:
				town._window(building, Vector3(x,1.88,3.74),1.1,1.46,0,x == -1.7)
			_box(building,Vector3(1.2,1.12,3.75),Vector3(1.21,2.24,.14),"green")
			_box(building,Vector3(-4.11,4.91,-1.64),Vector3(.78,2.05,.69),"brick")
			_flag(building.translated_local(Vector3(8,0,4.8)))
		"pump":
			_shed(building,Vector3(7.8,3.1,6.3),"pump_blue",1.22)
			_box(building,Vector3(.7,1.12,3.21),Vector3(1.3,2.24,.13),"tar")
			for vent in 5:
				_box(building,Vector3(-2.27,1.19+vent*.13,3.215),Vector3(1.49,.082,.075),"tar")
			_round(building,Vector3(-5.35,1.32,2.2),Vector3(1.85,2.64,1.85),"galv")
			_round(building,Vector3(-5.35,2.85,2.2),Vector3(.58,.48,.58),"pump_blue")
			_timber(building,Vector3(-5.35,.62,2.2),Vector3(-3.63,.62,2.2),.31,"green")
		"orchard":
			_shed(building,Vector3(7.5,2.65,5.1),"green_siding",1.6)
			_box(building,Vector3(.77,1.59,2.61),Vector3(3.68,1.12,.14),"creosote")
			_box(building,Vector3(.77,1.01,2.85),Vector3(4.02,.12,.69),"wood")
			_box(building,Vector3(-2.34,1.03,2.63),Vector3(.97,2.06,.13),"cream_board")
			for x: float in [-.68,.02,.72,1.42,2.12]:
				town._local(building,Vector3(x,2.45,2.93),Vector3(.71,.12,1.1),"dark_red" if x < 0 or x > 1 else "trim",Vector3(.2,0,0))
			for row in 3:
				for col in 5:
					var trunk := building.translated_local(Vector3(10+row*6.6,0,3-col*7.1))
					_apple_tree(trunk.rotated_local(Vector3.UP, (col+variation)*1.05))
		"timber":
			_logs(building, 5, 8.1)
			_logs(building.translated_local(Vector3(9.7,0,-5.8)), 4, 7)
			_shed(building.translated_local(Vector3(-9,0,-5)),Vector3(5.6,2.9,4.8),"shed_siding",1.35)
		"freight":
			_shed(building,Vector3(15.8,4.8,7.6),"green_siding",1.65)
			_box(building,Vector3(0,.91,5.12),Vector3(16.6,.4,2.63),"wood")
			town._block("Freight dock",building*Vector3(0,.58,5.1),Vector3(16.6,1.16,2.63),yaw)
			for x: float in [-7.1,-2.4,2.4,7.1]:
				_box(building,Vector3(x,.43,5.92),Vector3(.4,.86,.4),"stone")
			for i in 3:
				_box(building,Vector3(4.64+i*.72,1.39,5.05),Vector3(.67,.56,.71),"wood")
				_box(building,Vector3(4.64+i*.72,1.69,5.05),Vector3(.68,.06,.72),"snow")
			for x: float in [-4.1,3.45]:
				_box(building,Vector3(x,2.44,3.86),Vector3(3.28,2.9,.13),"dark_red")
				_box(building,Vector3(x,4.06,3.93),Vector3(5.48,.11,.14),"metal")
	_fixture(site)
	# A windbreak sits behind some yards, leaving the whole approach and bay clear.
	if variation % 2 == 0:
		for i in 6:
			town._pine(building * Vector3(-13+i*4.7,0,-19-(i%2)*2), 7.0+(i+variation)%5, true)


func _shed(t: Transform3D, dims: Vector3, siding: String, rise: float) -> void:
	_box(t,Vector3.UP*dims.y*.5,dims,siding)
	town._structure_roof(t,dims.x,dims.z,dims.y,rise,siding)
	for x: float in [-.5,.5]:
		_box(t,Vector3(x*(dims.x-.12),dims.y*.5,dims.z*.5),Vector3(.16,dims.y,.17),"trim")
	_box(t,Vector3(0,.15,dims.z*.5),Vector3(dims.x,.3,.1),"stone")
	town._block("Field building",t * Vector3(0,dims.y*.5,0),dims,t.basis.get_euler().y)


func _fixture(site: Dictionary) -> void:
	var base := Vector3(site.stop.x,0,site.stop.y)
	var yard := Vector3(site.yard.x,0,site.yard.y)
	var t := Transform3D(Basis.looking_at((base-yard).normalized()),base)
	var height := 1.21
	match site.archetype:
		"hall":
			for x: float in [-.61,.61]:
				_box(t,Vector3(x,.84,0),Vector3(.13,1.68,.14),"creosote")
			_box(t,Vector3(0,1.51,0),Vector3(1.52,1.01,.23),"green")
			_box(t,Vector3(0,1.54,.13),Vector3(1.31,.77,.025),"glass")
			for x: float in [-.38,.01,.38]:
				_box(t,Vector3(x,1.51,.154),Vector3(.29,.42,.025),"trim")
			height = 2.03
		"dairy","orchard","sugar","timber":
			for x: float in [-.75,.75]:
				_box(t,Vector3(x,.4,0),Vector3(.14,.8,.64),"creosote")
			_box(t,Vector3(0,.83,0),Vector3(1.84,.14,.78),"wood")
			if site.archetype == "dairy":
				for x: float in [-.52,.05,.62]:
					_round(t,Vector3(x,1.18,0),Vector3(.41,.56,.41),"galv")
					_round(t,Vector3(x,1.50,0),Vector3(.31,.1,.31),"metal")
			elif site.archetype == "timber":
				for x: float in [-.51,-.1,.3,.57]:
					_timber(t,Vector3(x,.93,.31),Vector3(x+.13,.35,.38),.065,"metal")
			else:
				_box(t,Vector3(0,1.05,0),Vector3(1.42,.32,.63),"wood")
				for x: float in [-.6,-.2,.2,.6]:
					_box(t,Vector3(x,1.08,.33),Vector3(.05,.33,.045),"creosote")
			height = .69
		_:
			_box(t,Vector3(0,.62,0),Vector3(.15,1.24,.14),"creosote")
			var equipment: bool = site.archetype == "fire"
			_box(t,Vector3(0,1.26,0),Vector3(1.14 if equipment else .74,.86 if equipment else .57,.43),"dark_red" if equipment else "galv")
			_box(t,Vector3(0,1.44,.23),Vector3(.38,.085,.047),"black")
			if site.archetype == "pump":
				_round(t,Vector3(0,1.39,.26),Vector3(.18,.09,.18),"glass",Vector3(PI/2,0,0))
			if site.archetype == "garage":
				_round(t,Vector3(.24,1.32,.26),Vector3(.095,.1,.095),"trim",Vector3(PI/2,0,0))
			height = 1.09
	var caption: String = site.fixture.trim_prefix("the ").to_upper()
	var width := maxf(.93,caption.length()*.071)
	_box(t,Vector3(0,height,.416),Vector3(width,.226,.054),"green")
	town._letter(caption,t*Vector3(0,height,.448),t.basis.get_euler().y,.0035)
	# The yard light is bolted to the back of the fixture. A driver can park
	# beside it from either direction without getting a wheel behind the rack.
	_box(t,Vector3(-.58,1.05,-.23),Vector3(.09,2.10,.11),"creosote")
	_box(t,Vector3(-.58,2.03,-.14),Vector3(.263,.19,.29),"metal")
	_box(t,Vector3(-.58,1.92,-.14),Vector3(.22,.062,.25),"lamp")
	town._scattered_light(t*Vector3(-.58,1.93,-.08),Vector2(.94,1.21),Color("#ffba81"),.54)
	town._block("Outdoor service fixture",base+Vector3.UP*.65,Vector3(1.12,1.3,.55),t.basis.get_euler().y)


func _logs(t: Transform3D, count: int, length: float) -> void:
	town._block("Stacked sawlogs",t*Vector3(0,.99,0),Vector3(count*.8,1.98,length),t.basis.get_euler().y)
	for tier in 3:
		for i in count-tier:
			var x := (i - (count-tier-1)*.5) * .83
			var y := .43+tier*.72
			_round(t,Vector3(x,y,0),Vector3(.84,length,.84),"creosote",Vector3(PI/2,0,0))
			_round(t,Vector3(x,y,length*.5+.02),Vector3(.73,.046,.73),"wood",Vector3(PI/2,0,0))
			if tier == 2:
				_box(t,Vector3(x,y+.376,0),Vector3(.38,.085,length-.1),"snow")


func _flag(t: Transform3D) -> void:
	_round(t,Vector3.UP*3.95,Vector3(.098,7.9,.098),"galv")
	for stripe in 7:
		_box(t,Vector3(.87,7.57-stripe*.126,.034),Vector3(1.66,.13,.033),"trim" if stripe%2 else "dark_red")
	_box(t,Vector3(.42,7.42,.034),Vector3(.77,.435,.053),"pump_blue")


func _apple_tree(t: Transform3D) -> void:
	# The farthest branch tip is just under two metres from the root.
	if town._near_surface(Vector2(t.origin.x, t.origin.z), 2.4):
		return
	t.origin.y = Roadside.height_at(t.origin.x, t.origin.z)
	town._block("Apple trunk",t*Vector3(.07,.67,.04),Vector3(.27,1.34,.27))
	_timber(t, Vector3.ZERO,Vector3(.14,1.29,.08),.29,"creosote")
	for arm in 3:
		var b := t.rotated_local(Vector3.UP, arm * TAU/3)
		_timber(b,Vector3(.10,1.12,0),Vector3(1.32,1.86,.25),.185,"creosote")
		_timber(b,Vector3(1.32,1.86,.25),Vector3(1.89,2.57,-.12),.105,"wood")
		_timber(b,Vector3(.89,1.64,.16),Vector3(.71,2.71,.4),.089,"wood")


func _box(t: Transform3D, at: Vector3, size: Vector3, material: String) -> void:
	town._local(t,at,size,material)


func _round(t: Transform3D, at: Vector3, size: Vector3, material: String, rotation := Vector3.ZERO) -> void:
	town._shape_at(town.drum,t*Transform3D(Basis.from_euler(rotation).scaled_local(size),at),material)


func _timber(t: Transform3D, a: Vector3, b: Vector3, thickness: float, material: String) -> void:
	town._beam(t*a,t*b,thickness,material)


func _landmark(marker: Dictionary) -> void:
	var pos: Vector2 = marker.position
	var t := Transform3D(Basis.IDENTITY, Vector3(pos.x,0,pos.y))
	match marker.kind:
		"water_tower":
			return # The tower at the original Mill and Line corner is already built.
		"lookout","windmill":
			var lookout: bool = marker.kind == "lookout"
			var high := 18.0 if lookout else 11.3
			var width := 2.65 if lookout else 1.72
			for x: int in [-1,1]:
				for z: int in [-1,1]:
					var foot := Vector3(x * width,0,z * width)
					var top := Vector3(x * width * .43,high,z * width * .43)
					town._block("Tower foot",t*foot.lerp(top,.06),Vector3(.29,high*.12,.29))
					_timber(t,foot,top,.22,"creosote" if lookout else "galv")
					for rung in 3:
						var a := foot.lerp(top,rung/3.0)
						var b := foot.lerp(top,(rung + 1)/3.0)
						_timber(t,a,Vector3(-b.x,b.y,b.z),.103,"metal")
			if lookout:
				var cabin := t.translated_local(Vector3.UP*high)
				_box(cabin,Vector3.ZERO,Vector3(4.9,.25,4.9),"wood")
				_shed(cabin,Vector3(3.5,2.8,3.5),"shed_siding",1.18)
				for side: float in [-1,1]:
					_box(cabin,Vector3(0,1.79,side*1.79),Vector3(3.19,1.1,.1),"glass")
					_box(cabin,Vector3(side*1.79,1.79,0),Vector3(.10,1.1,3.19),"glass")
			else:
				var rotor := t.translated_local(Vector3(0,high,.67)).rotated_local(Vector3.UP,-.64)
				for blade in 12:
					var spoke := rotor.rotated_local(Vector3.BACK,blade*TAU/12)
					_box(spoke,Vector3.UP*.98,Vector3(.058,1.96,.05),"galv")
					_box(spoke,Vector3.UP*2.19,Vector3(.44,1.05,.13),"trim")
				_timber(rotor,Vector3.ZERO,Vector3(0,.31,-3.28),.14,"galv")
				_box(rotor,Vector3(0,.54,-2.89),Vector3(.11,.98,1.14),"dark_red")
		"trestle":
			# A retired logging spur, wholly off the road. The repeating bents
			# show through the blowing powder before the old rail deck does.
			t = t.rotated_local(Vector3.UP,.11)
			for bent in 6:
				var bay := t.translated_local(Vector3(0,0,(bent-2.5)*5.4))
				for x: float in [-1.65,1.65]:
					town._block("Trestle piling",bay*Vector3(x*1.28,.78,0),Vector3(.44,1.56,.44),bay.basis.get_euler().y)
					_timber(bay,Vector3(x*1.36,0,0),Vector3(x,3.95,0),.47,"creosote")
					_timber(bay,Vector3(-x*1.25,.6,0),Vector3(x,3.72,0),.215,"wood")
				_box(bay,Vector3(0,4.02,0),Vector3(4.9,.39,.64),"creosote")
			_box(t,Vector3(0,4.39,0),Vector3(4.25,.51,29.3),"wood")
			town._block("Trestle deck",t*Vector3(0,4.45,0),Vector3(4.25,.62,29.3),t.basis.get_euler().y)
			_box(t,Vector3(0,4.72,0),Vector3(4.37,.18,29.5),"snow")
			for x: float in [-.82,.82]:
				_box(t,Vector3(x,4.83,0),Vector3(.1,.09,29.6),"metal")
		"kiln":
			_round(t,Vector3.UP*3.25,Vector3(6.7,6.5,6.7),"stone")
			_round(t,Vector3.UP*8.42,Vector3(4.82,4.74,4.82),"brick")
			_round(t,Vector3.UP*10.74,Vector3(5.0,.34,5.0),"stone")
			_round(t,Vector3.UP*10.93,Vector3(5.06,.14,5.06),"snow")
			for side: float in [-1,1]:
				_box(t,Vector3(0,1.3,side*3.29),Vector3(1.8,2.61,.15),"black")
		"elevator":
			_shed(t,Vector3(7.8,15.2,7.1),"shed_siding",2.5)
			var head := t.translated_local(Vector3(-2.0,14.4,-.15))
			_shed(head,Vector3(3.7,5.1,4.1),"green_siding",1.16)
			_timber(t,Vector3(-2,16,1),Vector3(-10,4.3,2.6),.59,"galv")
			_round(t,Vector3(-9,2.6,2.6),Vector3(4.4,5.2,4.4),"galv")
		"chapel":
			_shed(t,Vector3(4.6,3.7,6.6),"cream_board",2.43)
			_shed(t.translated_local(Vector3(0,0,3.56)),Vector3(1.94,5.56,1.47),"cream_board",1.58)
			_box(t,Vector3(0,1.09,4.35),Vector3(1.18,2.18,.12),"green")
			_box(t,Vector3(0,7.42,3.56),Vector3(.091,1.35,.091),"creosote")
			_box(t,Vector3(0,7.68,3.56),Vector3(.72,.095,.095),"creosote")
	# Static fixtures beyond the turnouts still meet the wheels if approached.
	# The walkable space beneath the trestle and towers stays open.
	if marker.kind in ["kiln","elevator"]:
		town._block("Historic landmark",t.origin+Vector3.UP*2.1,Vector3(4.3,4.2,4.3))


func _crossroad(point: Vector2) -> void:
	var roads: Array = Route.roads_at(point)
	if roads.size() < 2:
		return
	var base := Vector3(point.x+7.4,0,point.y-7.4)
	var grade: float = Roadside.height_at(base.x,base.z)
	base.y = grade
	town._box(base+Vector3.UP*1.39,Vector3(.12,2.78,.12),"galv")
	for i in roads.size():
		var road: Dictionary = roads[i]
		var street: String = road.name.to_upper().replace(" ROAD"," RD")
		var yaw := 0.0 if road.a.y == road.b.y else PI/2
		town._name_board(base+Vector3.UP*(2.65-.34*i),street,yaw,maxf(1.53,street.length()*.147))


func _open_road(road: Dictionary) -> void:
	var a: Vector2 = road.a
	var b: Vector2 = road.b
	var along := a.direction_to(b)
	var across := along.orthogonal()
	var distance := 42.0
	var i := 0
	# On the outlying roads even a lull can show nothing but the next snow pole.
	# Long irregular gaps separate fence remnants and the occasional clump of trees.
	while distance < a.distance_to(b)-18:
		var center := a + along * distance
		var side := 1 if i % 2 else -1
		var edge := center + across * side * 5.1
		distance += town.rng.randf_range(68,156)
		i += 1
		if road.name == "County Q" and edge.y > Roadside.CORE_NORTH and edge.y < Roadside.CORE_SOUTH:
			continue
		if not town._near_surface(edge,.5):
			town._snow_stake(Vector3(edge.x,0,edge.y))
		# Low remnants of the last grader pass give the white road an edge
		# without putting a building or landmark in the empty stretches.
		var ridge_center := center + across * side * (Route.road_half_width(road.name) + 1.55)
		var length: float = town.rng.randf_range(18,36)
		var half_span := along.abs() * (length * .5) + across.abs() * .9
		if not town._intersects_surface(Rect2(ridge_center - half_span, half_span * 2)):
			town._drift(Vector3(ridge_center.x,-.045,ridge_center.y),Vector3(1.42,town.rng.randf_range(.25,.52),length),atan2(along.x,along.y))
		if i % 11 != 0:
			continue
		var offset: float = town.rng.randf_range(39,90) * (-1 if i%2 else 1)
		var verge := edge + across*offset
		if town._near_surface(verge,40):
			continue
		var at := Vector3(verge.x,0,verge.y)
		match i % 3:
			0:
				for tree in 3:
					town._bare_tree(at+Vector3(along.x*tree*5,0,along.y*tree*5),6.9+tree*1.6,false)
			1:
				town._fence(at,at+Vector3(along.x*33,0,along.y*33),6.2)
			2:
				town._drift(at,Vector3(7,.38,23),.92)
	if road.kind == "county":
		for end: Vector2 in [a,b]:
			var away := (end-(a+b)*.5).normalized()
			var edge := end + away*9
			var t := Transform3D(Basis.looking_at(Vector3(away.x,0,away.y)),Vector3(edge.x,0,edge.y))
			var berm := t * Vector3(0,0,-3.4)
			t.origin.y = Roadside.height_at(edge.x, edge.y)
			for x: float in [-1.42,1.42]:
				_box(t,Vector3(x,.62,0),Vector3(.16,1.24,.24),"wood")
			_box(t,Vector3.UP*1.03,Vector3(3.35,.41,.15),"orange")
			town._letter("PLOW LIMIT",t*Vector3(0,1.03,.085),t.basis.get_euler().y,.0067)
			town._drift(berm,Vector3(5.4,1.15,14),t.basis.get_euler().y+PI*.5)
