extends Node3D

const Route = preload("res://world/route.gd")
const Roadside = preload("res://world/roadside.gd")
const BECK_TANK = preload("res://world/props/beck_tank.tscn")
const BECK_MAILBOX = preload("res://world/props/beck_mailbox.tscn")
const DRIFT_TILE := 96.0
const SNOW_SHADER = preload("res://world/storm_snow.gdshader")
const FLAKE_SHADER = preload("res://world/wind_flake.gdshader")
const CLOUD_SHADER = preload("res://world/overcast.gdshader")
const WOOD_SHADER = preload("res://world/weathered_wood.gdshader")

var rng := RandomNumberGenerator.new()
var cube := BoxMesh.new()
var drum := CylinderMesh.new()
var mound := SphereMesh.new()
var gable: ArrayMesh
var drift_forms: Array[ArrayMesh] = []
var tree_meshes: Dictionary[StringName, Mesh] = {}
var mats := {}
var batches := {}
var snowfall: CPUParticles3D
var weather_camera: Camera3D
var gust_strength := 0.0
var storm_seconds := 0.0
var ground_snow: Node3D
var storm_env: Environment
var flake_material := ShaderMaterial.new()
var drift_material := ShaderMaterial.new()
var lamp_centers := PackedVector3Array()
var truck_position := Vector3(Route.HOME_PARK.x,0,Route.HOME_PARK.y)
var truck_forward := Vector3.RIGHT

func _ready() -> void:
	rng.seed = 7581958
	drum.top_radius = 0.5
	drum.bottom_radius = 0.5
	drum.height = 1.0
	drum.radial_segments = 10
	drum.rings = 0
	mound.radius = 0.5
	mound.height = 1.0
	mound.radial_segments = 12
	mound.rings = 5
	_materials()
	gable = _gable_mesh()
	for variant in range(5):
		drift_forms.append(_drift_mesh(variant))
	_load_woodlot()
	_light_and_weather()
	_snowfield()
	_buildings()
	_road_furniture()
	_feed_sign()
	for medium: ShaderMaterial in [flake_material, drift_material]:
		medium.set_shader_parameter("yard_lamps", lamp_centers)
	_tree_lines()
	_ditch_grass()
	_flush_meshes()

func _materials() -> void:
	var shades := {
		"wood": "#7c6855", "stake": "#b27848", "pole": "#705f51", "creosote": "#47403e",
		"metal": "#686d6b", "galv": "#929899", "wire": "#363e42", "tar": "#484b4a",
		"trim": "#c3beb0", "frame": "#494847", "glass": "#586970", "green": "#45635a",
		"red": "#964835", "dark_red": "#652e2b", "stone": "#858783", "brick": "#896451",
		"tank": "#d0cbc1", "grass": "#8d7863", "ice": "#b9c9c9", "roadside": "#778992",
		"orange": "#d18b4a", "black": "#383b3a", "silo": "#999b94", "gutter": "#939894"
	}
	for key in shades:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(shades[key])
		mat.roughness = 0.97
		mats[key] = mat
	for key in ["window", "lamp", "reflector"]:
		var mat := StandardMaterial3D.new()
		var tint: Color = {"window": Color("#eda361"), "lamp": Color("#ffe2ae"), "reflector": Color("#e99660")}[key]
		mat.albedo_color = tint
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = {"window": 0.96, "lamp": 1.5, "reflector": .045}[key]
		mats[key] = mat
	var snow := ShaderMaterial.new()
	snow.shader = SNOW_SHADER
	snow.set_shader_parameter("ground_contacts",Route.SNOW_CONTACTS)
	mats["snow"] = snow
	for key in ["cream_siding", "green_siding", "barn_siding", "shed_siding", "cream_board"]:
		var mat := ShaderMaterial.new()
		mat.shader = WOOD_SHADER
		var colors := {"cream_siding": "#b9b9a7", "green_siding": "#99a7a0", "barn_siding": "#994e42", "shed_siding": "#8a796c", "cream_board": "#b9b2a1"}
		mat.set_shader_parameter("paint_color", Color(colors[key]))
		mat.set_shader_parameter("vertical_boards", key in ["barn_siding", "shed_siding", "cream_board"])
		mats[key] = mat
	var needles := ShaderMaterial.new()
	needles.shader = preload("res://world/trees/spruce_bough.gdshader")
	needles.set_shader_parameter("needles",preload("res://world/trees/snow_bough.webp"))
	mats["spruce_needles"] = needles
	var wood := ShaderMaterial.new()
	wood.shader = preload("res://world/trees/winter_bark.gdshader")
	mats["tree_bark"] = wood

func _light_and_weather() -> void:
	var world := WorldEnvironment.new()
	world.name = "StormSky"
	storm_env = Environment.new()
	storm_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var dome := ShaderMaterial.new()
	dome.shader = CLOUD_SHADER
	sky.sky_material = dome
	storm_env.sky = sky
	storm_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	storm_env.ambient_light_color = Color("#8895a2")
	storm_env.ambient_light_energy = .43
	storm_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	storm_env.fog_enabled = true
	storm_env.fog_light_color = Color("#54636c")
	storm_env.fog_light_energy = .90
	storm_env.fog_density = .0032
	storm_env.fog_sky_affect = .13
	storm_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = storm_env
	add_child(world)
	var sky_light := DirectionalLight3D.new()
	sky_light.name = "SnowCloudBounce"
	sky_light.rotation_degrees = Vector3(-61, -38, 0)
	sky_light.light_color = Color("#a3adb5")
	sky_light.light_energy = .22
	sky_light.shadow_enabled = false
	add_child(sky_light)

	var quad := QuadMesh.new()
	quad.size = Vector2(.035, .14)
	flake_material.shader = FLAKE_SHADER
	quad.material = flake_material
	snowfall = CPUParticles3D.new()
	snowfall.name = "CrosswindSnow"
	snowfall.mesh = quad
	snowfall.amount = 1550 if OS.has_feature("mobile") else 2250
	snowfall.lifetime = 2.8
	snowfall.preprocess = snowfall.lifetime
	snowfall.local_coords = false
	snowfall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snowfall.emission_box_extents = Vector3(14,5.2,17)
	snowfall.direction = Vector3(1.,-.39,.26).normalized()
	snowfall.spread = 12.
	snowfall.gravity = Vector3(.90,-.14,.18)
	snowfall.initial_velocity_min = 6.5
	snowfall.initial_velocity_max = 10.
	snowfall.scale_amount_min = .43
	snowfall.scale_amount_max = 1.30
	snowfall.position = Vector3(-9.0, 5.2, 37)
	snowfall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(snowfall)
	_ground_snow()

# The powder stays anchored to the fields. Shifting the patch by a whole tile
# preserves the ribbons around the cab and recycles the ones beyond visibility.
func _ground_snow() -> void:
	var ribbons := SurfaceTool.new()
	ribbons.begin(Mesh.PRIMITIVE_TRIANGLES)
	var source := RandomNumberGenerator.new()
	source.seed = 1998127
	for i in range(44):
		var center := Vector2(source.randf_range(-.5,.5), source.randf_range(-.5,.5)) * DRIFT_TILE
		var across := Vector2(source.randf_range(16,39),source.randf_range(-4,10))
		var h := source.randf_range(.48,1.4)
		if i % 9 == 0:
			h *= 1.6
		var top_offset := Vector2(source.randf_range(-.3,1.0), source.randf_range(.25,1.25))
		var surface_normal := Vector3(across.y,0,-across.x).normalized()
		for uvs:Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
			var point := center+(uvs.x-.5)*across+top_offset*uvs.y
			ribbons.set_uv(uvs)
			ribbons.set_normal(surface_normal)
			ribbons.add_vertex(Vector3(point.x,.24+uvs.y*h,point.y))
	drift_material.shader = preload("res://world/spindrift.gdshader")
	var sheet := ribbons.commit()
	ground_snow = Node3D.new()
	ground_snow.name = "RunningGroundSnow"
	add_child(ground_snow)
	for x in range(-1,2):
		for z in range(-1,2):
			var tile := MeshInstance3D.new()
			tile.mesh = sheet
			tile.position = Vector3(x * DRIFT_TILE, 0, z * DRIFT_TILE)
			tile.material_override = drift_material
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ground_snow.add_child(tile)

func set_truck_pose(at: Vector3, forward: Vector3, up := Vector3.UP) -> void:
	var right := forward.cross(up)
	if not at.is_finite() or not right.is_finite() or right.is_zero_approx():
		return
	truck_position = at
	truck_forward = forward.normalized()
	var lamp_up := right.normalized().cross(truck_forward)
	for medium: ShaderMaterial in [flake_material,drift_material]:
		medium.set_shader_parameter("truck_position", truck_position)
		medium.set_shader_parameter("truck_forward", truck_forward)
		medium.set_shader_parameter("truck_up", lamp_up)

func _process(delta: float) -> void:
	storm_seconds += delta
	var pulse := .43 + .35*sin(storm_seconds*.103-1.43) + .12*sin(storm_seconds*.237+.35) + .09*sin(storm_seconds*.053-.20)
	gust_strength = smoothstep(.36,.88,pulse)
	storm_env.fog_density = lerpf(.0032,.029,gust_strength)
	storm_env.fog_sky_affect = lerpf(.13,.81,gust_strength)
	snowfall.gravity = Vector3(1.4+gust_strength*3.5,-.14,.31+gust_strength*.45)
	flake_material.set_shader_parameter("gust",gust_strength)
	drift_material.set_shader_parameter("gust",gust_strength)
	drift_material.set_shader_parameter("storm_seconds",storm_seconds)
	var camera := get_viewport().get_camera_3d()
	if camera:
		var eye := camera.global_position
		ground_snow.position = Vector3(snappedf(eye.x,DRIFT_TILE), 0, snappedf(eye.z,DRIFT_TILE))
		snowfall.global_position = camera.global_position + Vector3(-10, 4.2, -2.6) - camera.global_basis.z*6.
		if weather_camera != camera:
			snowfall.restart()
			weather_camera = camera

func _snowfield() -> void:
	var middle_z := (Route.ROAD_NORTH_Z + Route.ROAD_SOUTH_Z) * .5
	var length := Route.ROAD_SOUTH_Z - Route.ROAD_NORTH_Z
	var ground := Roadside.new()
	ground.build(mats.snow)
	add_child(ground)
	for x in [-695.0,695.0]:
		_block("Field edge", Vector3(x,1.6,middle_z), Vector3(2,5,length+170))
	for z in [Route.ROAD_NORTH_Z-80.0, Route.ROAD_SOUTH_Z+80.0]:
		_block("Far field edge", Vector3(0,1.6,z), Vector3(1400,5,2))

	# Shallow sheets across the flats catch the ambient light. The horizon stays level.
	for i in range(175):
		var x := rng.randf_range(42,590) * (-1 if i%2 else 1)
		var z := rng.randf_range(Route.ROAD_NORTH_Z-100,Route.ROAD_SOUTH_Z+100)
		if (x > 0 and absf(z-Route.BECK_Z)<34) or (x < 0 and absf(z-Route.HOME_Z)<32):
			continue
		_drift(Vector3(x,-.07,z),Vector3(rng.randf_range(8,23),rng.randf_range(.18,.65),rng.randf_range(22,60)),rng.randf_range(1.06,1.39))
	# The cleared county route runs out in old plow banks at the playable limits.
	for z in [Route.ROAD_NORTH_Z-3.0, Route.ROAD_SOUTH_Z+3.0]:
		_drift(Vector3(0,0,z),Vector3(7.4,1.55,26),PI*.46)

func _drift(at: Vector3, dims: Vector3, yaw: float) -> void:
	_shape(drift_forms[rng.randi_range(0,drift_forms.size()-1)],at,dims,"snow",Vector3(0,yaw,0))

func _buildings() -> void:
	_house(Route.HOME_HOUSE, PI / 2.0, "cream_siding", true)
	_barn(Route.HOME_HOUSE+Vector3(-23,0,-31), PI / 2.0, Vector3(14,3.7,8), false)
	_house(Route.BECK_HOUSE, PI, "green_siding", false)
	_tank(Route.TANK)
	_barn(Vector3(164.5,0,Route.BECK_Z-32), -.10, Vector3(13,5.5,15), true)
	_silo(Vector3(180.5,0,Route.BECK_Z-36), 2.65, 13.5)
	_corn_crib(Vector3(68,0,Route.COOP_Z-38), -.12)
	# A second farm sits well back across the western section.
	_barn(Vector3(-244,0,-1143), .04, Vector3(15,5.2,10), false)
	_silo(Vector3(-253,0,-1154), 2.8, 16.4)
	_silo(Vector3(-260,0,-1156), 2.55, 15.8)

func _house(at: Vector3, yaw: float, siding: String, home: bool) -> void:
	var axes := Basis(Vector3.UP, yaw)
	var t := Transform3D(axes, at)
	var w := 10.0
	var d := 7.2
	var h := 4.9
	_local(t, Vector3(0,0.30,0), Vector3(w+0.15,0.60,d+0.15), "stone")
	_local(t, Vector3(0,h/2+0.42,0), Vector3(w,h,d), siding)
	_structure_roof(t, w, d, h+0.42, 2.55, siding)
	_block("Farmhouse", at + Vector3.UP * 2.75, Vector3(w,5.5,d), yaw)
	for sx: int in [-1,1]:
		for sz: int in [-1,1]:
			_local(t, Vector3(sx*(w*0.5-0.07),2.8,sz*(d*0.5-0.04)), Vector3(0.17,4.98,0.16), "trim")
	for x in [-3.25,-0.55,3.05]:
		_window(t, Vector3(x,3.90,3.63), 1.10, 1.28, 0.0, home and x == -3.25)
	_window(t, Vector3(-2.35,1.95,3.64), 2.36, 1.45, 0.0, true)
	_window(t, Vector3(-5.025,2.19,-0.8), 1.48, 1.47, -PI / 2, false)
	_window(t, Vector3(5.025,2.05,0.5), 1.36, 1.47, PI / 2, true)
	_window(t, Vector3(5.025,4.1,-0.93), 1.12, 1.2, PI / 2, false)
	_window(t, Vector3(-5.025,5.87,0), 0.78, 0.92, -PI / 2, false)
	_local(t, Vector3(2.40,1.27,3.65), Vector3(1.18,2.35,0.13), "trim")
	_local(t, Vector3(2.40,1.22,3.73), Vector3(0.97,2.17,0.09), "green" if home else "wood")
	_local(t, Vector3(2.40,1.63,3.80), Vector3(0.55,0.76,0.04), "window")
	_local(t, Vector3(2.75,1.11,3.82), Vector3(0.07,0.09,0.08), "metal")
	# The low porch can be traversed at both story interaction points.
	_local(t, Vector3(1.28,0.10,4.71), Vector3(6.85,0.20,2.5), "snow")
	_local(t, Vector3(1.28,2.71,4.73), Vector3(7.05,0.21,2.75), "trim", Vector3(0.15,0,0))
	_local(t, Vector3(1.28,2.83,4.73), Vector3(7.14,0.13,2.85), "snow", Vector3(0.15,0,0))
	for x in [-1.82,4.32]:
		_local(t, Vector3(x,1.28,5.74), Vector3(0.17,2.56,0.18), "trim")
	for y in [0.38,0.85]:
		_local(t, Vector3(-1.8,y,4.78), Vector3(0.11,0.10,1.95), "trim")
		_local(t, Vector3(-0.58,y,5.74), Vector3(2.45,0.11,0.11), "trim")
	_local(t, Vector3(3.28,2.08,3.9), Vector3(0.24,0.36,0.24), "lamp")
	_local(t, Vector3(3.28,2.31,3.9), Vector3(0.34,0.09,0.32), "black")
	_lamp(t * Vector3(3.28,2.13,4.22), 5.8)
	_local(t, Vector3(-2.15,7.15,-0.55), Vector3(0.73,2.2,0.92), "brick")
	for y in [7.87,8.24]:
		_local(t, Vector3(-2.15,y,-0.55), Vector3(0.88,0.14,1.04), "stone")
	_local(t, Vector3(-2.15,8.33,-0.55), Vector3(0.9,0.07,1.03), "snow")
	if home:
		_cb_mast(t * Vector3(-3.4,0,-4.35))
		# A single slanted timber brace, a useful visual tell for home.
		_local(t, Vector3(3.94,2.32,5.74), Vector3(0.10,0.90,0.12), "trim", Vector3(0,0,-0.72))

func _window(t: Transform3D, pos: Vector3, w: float, h: float, yaw: float, lit: bool) -> void:
	var s := t * Transform3D(Basis(Vector3.UP,yaw), pos)
	_local(s, Vector3.ZERO, Vector3(w+0.20,h+0.17,0.10), "trim")
	_local(s, Vector3(0,0,0.065), Vector3(w,h,0.07), "window" if lit else "glass")
	_local(s, Vector3(0,0,0.115), Vector3(0.055,h,0.032), "frame")
	_local(s, Vector3(0,0.03,0.115), Vector3(w,0.055,0.032), "frame")
	_local(s, Vector3(0,-h*0.5-0.10,0.10), Vector3(w+0.27,0.095,0.23), "snow")
	if lit:
		_local(s, Vector3(w*0.34,0,0.108), Vector3(w*0.15,h,0.013), "trim")

func _structure_roof(t: Transform3D, w: float, d: float, eave: float, rise: float, gable_color: String) -> void:
	_shape_at(gable,t * Transform3D(Basis.from_scale(Vector3(w,rise,d)),Vector3(0,eave,0)),gable_color)
	var half := d/2.0 + 0.40
	var slope := atan2(rise,d/2.0)
	var length := half/cos(slope)
	for sign_z: int in [-1,1]:
		var z := sign_z * half/2.0
		var y := eave + rise - tan(slope)*absf(z)
		_local(t, Vector3(0,y,z), Vector3(w+0.75,0.22,length+0.06), "tar", Vector3(sign_z*slope,0,0))
		_local(t, Vector3(0,y+0.14,z), Vector3(w+0.83,0.13,length+0.15), "snow", Vector3(sign_z*slope,0,0))
		_local(t, Vector3(0,eave-0.20,sign_z*half), Vector3(w+0.77,0.14,0.14), "gutter")

func _barn(at: Vector3, yaw: float, size: Vector3, red_barn: bool) -> void:
	var t := Transform3D(Basis(Vector3.UP,yaw),at)
	var w := size.x
	var h := size.y
	var d := size.z
	var siding := "barn_siding" if red_barn else "shed_siding"
	_local(t, Vector3(0,h/2,0), size, siding)
	_block("Barn", at + Vector3.UP * h*0.5, size, yaw)
	_structure_roof(t,w,d,h,d*0.31,siding)
	for sign_x: int in [-1,1]:
		_local(t, Vector3(sign_x*(w/2-0.08),h/2,d/2), Vector3(0.22,h,0.18), "trim" if red_barn else "wood")
	var opening := 4.9 if red_barn else 6.4
	var height := 3.5 if red_barn else 2.75
	var front_z := d/2+0.06
	_local(t, Vector3(0,height/2+0.02,front_z), Vector3(opening,height,0.16), "dark_red" if red_barn else "metal")
	for sx: int in [-1,1]:
		_local(t, Vector3(sx*opening/2,height/2,front_z+0.11), Vector3(0.14,height+0.18,0.13), "trim")
		var x := sx * opening/4
		_local(t, Vector3(x,height/2,front_z+0.14), Vector3(0.13,sqrt(pow(opening*0.48,2)+pow(height,2)),0.09), "trim" if red_barn else "gutter", Vector3(0,0,-sx * atan2(opening*0.48,height)))
	_local(t, Vector3(0,height+0.07,front_z+0.12), Vector3(opening+0.29,0.17,0.17), "trim")
	if red_barn:
		_local(t, Vector3(0,h-0.60,front_z+0.02), Vector3(1.25,0.78,0.18), "frame")
		for sx: int in [-1,1]:
			_window(t, Vector3(sx*4.77,2.45,front_z), 0.95,0.85,0,false)
		_local(t, Vector3(-3.30,h+4.9,0), Vector3(1.55,1.55,1.6), "cream_board")
		_local(t, Vector3(-3.30,h+5.75,0), Vector3(1.89,0.26,1.97), "snow")
		_local(t, Vector3(-3.30,h+6.28,0), Vector3(0.060,0.90,0.06), "wire")
		_local(t, Vector3(-3.30,h+6.52,0), Vector3(1.12,0.09,0.11), "wire")
	else:
		_local(t, Vector3(opening/2+0.6,2.98,front_z+0.11), Vector3(0.21,0.25,0.19), "lamp")

func _silo(at: Vector3, r: float, h: float) -> void:
	_shape(drum, at+Vector3.UP*(h/2),Vector3(2*r,h,2*r),"silo")
	_block("Silo",at+Vector3.UP*(h/2),Vector3(r*1.55,h,r*1.55))
	_shape(mound,at+Vector3.UP*h,Vector3(r*2.03,r*1.37,r*2.03),"snow")
	for i in range(1, int(h)):
		_shape(drum,at+Vector3.UP*i,Vector3(r*2.023,0.042,r*2.023),"metal")
	for x in [-0.29,0.29]:
		_box(at+Vector3(x,h/2,r+0.06),Vector3(0.065,h,0.07),"metal")
	for i in range(1,int(h/0.48)):
		_box(at+Vector3(0,i*0.48,r+0.07),Vector3(0.64,0.045,0.065),"metal")

func _corn_crib(at: Vector3, yaw: float) -> void:
	var t := Transform3D(Basis(Vector3.UP,yaw),at)
	_local(t,Vector3(0,1.61,0),Vector3(5.6,2.7,3.1),"shed_siding")
	_structure_roof(t,5.9,3.6,3.0,1.1,"shed_siding")
	_block("Corn crib",at + Vector3.UP*1.6,Vector3(5.6,3.2,3.1),yaw)
	for z in [-1.65,1.65]:
		for i in range(8):
			_local(t,Vector3(0,0.58+i*0.31,z),Vector3(5.8,0.14,0.12),"wood")
		for x in [-2.8,0.0,2.8]:
			_local(t,Vector3(x,1.6,z),Vector3(0.13,3.1,0.16),"creosote")
		_local(t,Vector3(0,1.60,z+signf(z)*0.13),Vector3(0.14,6.22,0.11),"wood",Vector3(0,0,1.10))

func _tank(at: Vector3) -> void:
	var tank := BECK_TANK.instantiate() as Node3D
	tank.position = at
	add_child(tank)
	_block("Propane tank",at+Vector3.UP*.9,Vector3(4.28,1.8,1.43))

func _road_furniture() -> void:
	# Thirty-five 46 m spans separate the two farm services along the section line.
	var previous := Vector3.ZERO
	var first_z := Route.HOME_Z + 13.0
	var first_span := floori((first_z-Route.ROAD_SOUTH_Z)/46.0)
	var last_span := ceili((first_z-Route.ROAD_NORTH_Z)/46.0)
	for span in range(first_span,last_span+1):
		var p := Vector3(-8.8 - sin(span*.57)*.24,0,first_z-span*46.0)
		p.y = Roadside.height_at(p.x, p.z)
		var near_home := is_equal_approx(p.z,Route.HOME_Z+13)
		var near_beck := is_equal_approx(p.z,Route.BECK_Z+13)
		_utility_pole(p, near_home or near_beck)
		if span > first_span:
			for off in [-1.2,0.0,1.2]:
				_wire(p+Vector3(off,8.85,0),previous+Vector3(off,8.85,0),1.20)
			_wire(p+Vector3(.14,7.05,0),previous+Vector3(.14,7.05,0),1.45)
		if near_home or near_beck:
			_road_lamp(p)
			var house := Route.HOME_HOUSE if near_home else Route.BECK_HOUSE
			var service := Vector3(-53 if near_home else 63,0,p.z+4)
			_utility_pole(service,false)
			_wire(p+Vector3(.14,7.05,0),service+Vector3(.14,7.05,0),1.04)
			_wire(service+Vector3(.14,7.05,0),house+Vector3(1.5,5.0,1.5),.95)
		previous = p
	for crossing: float in [Route.HOME_Z-285.0, Route.COOP_Z-320.0]:
		for side in [-1,1]:
			for offset in [-5.0,5.0]:
				_snow_stake(Vector3(side*5.4,0,crossing+offset))
	for x in [8.6,27.5,52.0,82.8,108.2]:
		_snow_stake(Vector3(x,0,Route.BECK_Z-3.4))
		_snow_stake(Vector3(x+1.5,0,Route.BECK_Z+3.4))
	for x in [-8.8,-32.0,-61.5]:
		_snow_stake(Vector3(x,0,Route.HOME_Z-3.5))
		_snow_stake(Vector3(x-1.2,0,Route.HOME_Z+3.5))
	_mailbox(Vector3(-5.4,0,Route.HOME_Z+4.7), 2.42, "1816")
	var beck_box := BECK_MAILBOX.instantiate() as Node3D
	beck_box.position = Route.BECK_MAILBOX
	beck_box.rotation.y = -.24
	add_child(beck_box)
	_road_sign(Vector3(5.7,0,Route.HOME_Z-45.0))
	var s := Vector3(6.15,0,Route.BECK_Z-5.3)
	s.y = Roadside.height_at(s.x, s.z)
	_box(s+Vector3(0,1.17,0),Vector3(.12,2.34,.12),"galv")
	_box(s+Vector3(0,2.30,0),Vector3(2.22,.40,.07),"green")
	_box(s+Vector3(0,2.52,0),Vector3(2.25,.05,.13),"snow")
	_letter("BECK LANE",s+Vector3(0,2.30,.055),0,.0059)
	_fence(Vector3(-71,0,Route.HOME_Z+10),Vector3(-122,0,Route.HOME_Z+10),4.6)
	_fence(Vector3(129,0,Route.BECK_Z-18),Vector3(171,0,Route.BECK_Z-18),4.6)
	_fence(Vector3(171,0,Route.BECK_Z-18),Vector3(171,0,Route.BECK_Z-28),4.6)
	_fence(Vector3(39,0,Route.COOP_Z-55),Vector3(109,0,Route.COOP_Z-55),4.7)

func _feed_sign() -> void:
	var mount := Transform3D(Basis(Vector3.UP,-.32),Vector3(9.3,0,Route.COOP_Z))
	for x:float in [-1.4,1.4]:
		var foot := mount * Vector3(x, 0, 0)
		var grade := Roadside.height_at(foot.x, foot.z)
		_local(mount,Vector3(x,(2.74+grade)*.5,0),Vector3(.19,2.74-grade,.19),"creosote")
		_block("Co-op signpost",mount*Vector3(x,(1.8+grade)*.5,0),Vector3(.2,1.8-grade,.2))
	_local(mount,Vector3(0,2.36,.04),Vector3(3.95,1.83,.15),"wood")
	_local(mount,Vector3(0,3.30,.05),Vector3(4.03,.12,.24),"snow")
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://world/art/feed_coop.webp")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 1.0
	var face := MeshInstance3D.new()
	var panel := QuadMesh.new()
	panel.size = Vector2(3.91,1.8)
	face.mesh = panel
	face.material_override = mat
	face.transform = mount.translated_local(Vector3(0,2.37,.119))
	add_child(face)


func _utility_pole(p: Vector3, transformer: bool) -> void:
	_beam(p,p+Vector3(0.11,9.15,0),0.23,"pole")
	_shape(drum,p+Vector3(0.008,0.62,0),Vector3(0.255,1.24,0.255),"creosote")
	_box(p+Vector3(0.11,8.58,0),Vector3(3.22,0.18,0.22),"wood")
	_beam(p+Vector3(0,7.65,0.11),p+Vector3(-1.06,8.5,0.11),0.068,"galv")
	_beam(p+Vector3(0,7.65,0.11),p+Vector3(1.06,8.5,0.11),0.068,"galv")
	for x in [-1.2,0.0,1.2]:
		_shape(drum,p+Vector3(x,8.79,0),Vector3(0.15,0.30,0.15),"glass")
		_shape(drum,p+Vector3(x,8.91,0),Vector3(0.19,0.065,0.19),"ice")
	if transformer:
		_shape(drum,p+Vector3(0.41,7.34,0),Vector3(0.58,1.01,0.58),"galv")
		_shape(drum,p+Vector3(0.41,7.87,0),Vector3(0.64,0.08,0.64),"snow")
		_beam(p+Vector3(0.4,7.8,0),p+Vector3(0.55,8.43,0),0.039,"wire")
	_block("Utility pole",p+Vector3.UP*3.4,Vector3(0.27,6.8,0.27))

func _cb_mast(base: Vector3) -> void:
	_beam(base,base+Vector3.UP*10.6,0.12,"galv")
	_beam(base+Vector3.UP*10.6,base+Vector3.UP*13.2,0.048,"galv")
	for i in range(3):
		var angle := TAU*i/3.0
		var dx := Vector3(cos(angle),0,sin(angle))
		_beam(base+Vector3.UP*10.6,base+Vector3.UP*9.7+dx*1.5,0.043,"galv")

func _snow_stake(at: Vector3) -> void:
	at.y = Roadside.height_at(at.x, at.z)
	var tilt := rng.randf_range(-0.12,0.12)
	_box(at+Vector3(0,0.68,0),Vector3(0.055,1.38,0.06),"stake",Vector3(0,0,tilt))
	_box(at+Vector3(-tilt*0.52,1.22,0),Vector3(0.067,0.21,0.073),"reflector",Vector3(0,0,tilt))

func _road_sign(at: Vector3) -> void:
	at.y = Roadside.height_at(at.x, at.z)
	_box(at+Vector3(0,1.01,0),Vector3(0.11,2.02,0.11),"metal")
	_box(at+Vector3(0,1.97,0),Vector3(0.76,0.86,0.072),"trim")
	_box(at+Vector3(0,1.97,0.045),Vector3(0.68,0.78,0.025),"black")
	_letter("COUNTY",at+Vector3(0,2.18,0.064),0,0.00245)
	_letter("Q",at+Vector3(0,1.88,0.067),0,0.013)
	_box(at+Vector3(0,2.42,0),Vector3(0.78,0.045,0.11),"snow")

func _mailbox(at: Vector3, yaw: float, number: String) -> void:
	var t := Transform3D(Basis(Vector3.UP,yaw),at)
	_local(t,Vector3(0,0.63,0),Vector3(0.17,1.26,0.17),"wood")
	_local(t,Vector3(0,1.08,0.16),Vector3(0.18,0.13,0.72),"wood")
	_local(t,Vector3(0,1.31,0.12),Vector3(0.37,0.37,0.65),"metal")
	_shape_at(mound,t*Transform3D(Basis.from_scale(Vector3(0.41,0.20,0.69)),Vector3(0,1.48,0.12)),"snow")
	_local(t,Vector3(0.21,1.53,0.09),Vector3(0.05,0.30,0.05),"red")
	_local(t,Vector3(0.21,1.64,0.16),Vector3(0.05,0.10,0.16),"red")
	_local(t,Vector3(0,0.83,0.14),Vector3(0.45,0.20,0.043),"red")
	_letter(number,t*Vector3(0,0.83,0.174),yaw,0.0025)

func _fence(start: Vector3, finish: Vector3, spacing: float) -> void:
	var count := maxi(1,roundi(start.distance_to(finish)/spacing))
	var previous := Vector3.ZERO
	for i in range(count+1):
		var p := start.lerp(finish,float(i)/count)
		var top := p + Vector3(rng.randf_range(-0.07,0.07),rng.randf_range(1.12,1.33),0.035)
		_beam(p, top, 0.145, "wood")
		if i:
			for y in [0.49,0.94]:
				_wire(previous+Vector3.UP*y, p+Vector3.UP*y, 0.065,0.030)
		previous = p

func _wire(a: Vector3, b: Vector3, sag: float, thickness := 0.045) -> void:
	var last := a
	for idx in range(1,5):
		var f := idx/4.0
		var point := a.lerp(b,f)-Vector3.UP*sag*(4*f*(1-f))
		_beam(last,point,thickness,"wire")
		last = point

func _tree_lines() -> void:
	for pos: Vector3 in [Vector3(-82,0,Route.HOME_Z+13), Vector3(-104,0,Route.HOME_Z+20),
		Vector3(-117,0,Route.HOME_Z+9), Vector3(140,0,Route.BECK_Z+30),
		Vector3(153,0,Route.BECK_Z+24), Vector3(161,0,Route.BECK_Z+38)]:
		_pine(pos,rng.randf_range(8.2,13.1))
	for pos: Vector3 in [Vector3(-106,0,Route.HOME_Z-17),Vector3(-72,0,Route.HOME_Z-9),
		Vector3(99,0,Route.BECK_Z+12),Vector3(145,0,Route.BECK_Z-23),
		Vector3(36,0,Route.COOP_Z-33),Vector3(42,0,Route.COOP_Z-35)]:
		_bare_tree(pos,rng.randf_range(6.8,10.3),true)

	# Discrete windbreaks mark distant property lines, leaving the central fields open.
	for stand: Vector2 in [Vector2(301,92),Vector2(-314,-362),Vector2(408,-718),
		Vector2(-264,-1142),Vector2(358,-1440),Vector2(-316,-1669)]:
		for i in range(13):
			var x := stand.x + rng.randf_range(-14,14)
			var z := stand.y + i*4.3 + rng.randf_range(-4.3,4.3)
			if i%4 == 0:
				_bare_tree(Vector3(x,0,z),rng.randf_range(7,13),false)
			else:
				_pine(Vector3(x,0,z),rng.randf_range(7,15),true)
	# Isolated stalks and broken fencelines surface where the fields meet the ditch.
	for i in range(140):
		var x := rng.randf_range(8.5,48.0) * (-1 if i%2 else 1)
		var z := rng.randf_range(Route.ROAD_NORTH_Z,Route.ROAD_SOUTH_Z)
		if (x < 0 and absf(z-Route.HOME_Z)<8) or (x > 0 and absf(z-Route.BECK_Z)<8):
			continue
		for j in range(rng.randi_range(3,8)):
			var base := Vector3(x+rng.randf_range(-1.2,1.2),.08,z+rng.randf_range(-.9,.9))
			base.y = Roadside.height_at(base.x, base.z) - .02
			var stem := base+Vector3(rng.randf_range(-.15,.26),rng.randf_range(.25,.65),rng.randf_range(-.14,.03))
			_beam(base,stem,.031,"grass")
			_beam(base.lerp(stem,.62),stem+Vector3(.15,-.13,.06),.025,"grass")

# Lodged sedge marks the drainage line in broken stands. Individual springy
# leaves lie across one another, with just their tips showing in the deeper fills.
func _ditch_grass() -> void:
	var straw := StandardMaterial3D.new()
	straw.cull_mode = BaseMaterial3D.CULL_DISABLED
	straw.vertex_color_use_as_albedo = true
	straw.roughness = 1.0
	mats["sedge"] = straw
	var clumps := [_sedge_clump(), _sedge_clump(), _sedge_clump()]
	for side: int in [-1, 1]:
		var z := Route.ROAD_NORTH_Z + rng.randf_range(4, 22)
		while z < Route.ROAD_SOUTH_Z:
			var patch_length := rng.randf_range(4, 19)
			var distance := rng.randf_range(8.2, 11.8)
			for i in range(ceili(patch_length * .93)):
				var along := z + rng.randf_range(0, patch_length)
				var x := side * (distance + rng.randf_range(-.8, .8))
				var grade := Roadside.height_at(x, along)
				if grade > -.22:
					continue
				var tussock := Vector3(x, grade - .03, along)
				var height := rng.randf_range(.68, 1.24)
				_shape(clumps[rng.randi_range(0, 2)], tussock, Vector3(1,height,1), "sedge", Vector3(0,rng.randf_range(-.65,.65),0))
			z += patch_length + rng.randf_range(9, 57)


func _sedge_clump() -> ArrayMesh:
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	for leaf in 15:
		var yaw := rng.randf() * TAU
		var direction := Vector3(sin(yaw), 0, cos(yaw))
		var root := direction * rng.randf_range(.02, .22)
		var rise := rng.randf_range(.18, .59)
		var lean := direction * rng.randf_range(.13, .42) + Vector3.RIGHT * .19
		var half_width := direction.cross(Vector3.UP) * rng.randf_range(.015, .031)
		var knee := root + lean * .5 + Vector3.UP * rise
		var tip := root + lean + Vector3.UP * rise * rng.randf_range(.47, 1.2)
		var color := Color("#87755b").lerp(Color("#c5ab79"), rng.randf())
		for v: Vector3 in [root-half_width, root+half_width, knee-half_width*.54,
				root+half_width, knee+half_width*.54, knee-half_width*.54,
				knee-half_width*.54, knee+half_width*.54, tip]:
			stems.set_color(color)
			stems.set_normal((Vector3.UP + direction * .45).normalized())
			stems.add_vertex(v)
	stems.index()
	return stems.commit()


func _load_woodlot() -> void:
	# The Blender layout holds each sculpt at its own workbench position.
	# Instance the local meshes so tree origins follow the playable township.
	var library := preload("res://world/trees/winter_stand.glb").instantiate()
	for node in library.find_children("*","MeshInstance3D",true,false):
		var part := node as MeshInstance3D
		tree_meshes[part.name] = part.mesh
	library.free()

func _pine(at: Vector3, height: float, distant: bool = false) -> void:
	var variant := rng.randi_range(0,2)
	var suffix := "Far" if distant else ""
	var width := height * rng.randf_range(0.81,1.06)
	var rot := Vector3(0,rng.randf()*TAU,0)
	var scale_to_height := Vector3(width,height,width)*0.1
	_shape(tree_meshes["Spruce%dBoughs%s" % [variant,suffix]],at,scale_to_height,"spruce_needles",rot)
	_shape(tree_meshes["Spruce%dWood%s" % [variant,suffix]],at,scale_to_height,"tree_bark",rot)
	if not distant:
		_block("Spruce trunk",at+Vector3.UP*2.0,Vector3(height*0.039,4.0,height*0.039))

func _bare_tree(at: Vector3, height: float, near: bool) -> void:
	var variant := rng.randi_range(0,2)
	var suffix := "" if near else "Far"
	var scale_to_height := Vector3.ONE*height*0.1
	var rot := Vector3(0,rng.randf()*TAU,0)
	_shape(tree_meshes["Birch%dWood%s" % [variant,suffix]],at,scale_to_height,"tree_bark",rot)
	if near:
		_block("Birch trunk",at+Vector3.UP*2.0,Vector3(height*0.029,4.0,height*0.029))

func _drift_mesh(variant: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs := [-0.50,-0.33,-0.13,0.09,0.30,0.50]
	var profile := [0.0,0.69,1.0,0.65,0.23,0.0]
	var shape: Array = []
	for j in range(9):
		var f := j/8.0
		var silhouette := pow(sin(f*PI),0.72)
		var course: Array[Vector3] = []
		for k in range(xs.size()):
			var wiggle := sin(f*2.0*PI+variant*0.84)*0.07
			var x: float = xs[k]*(0.56+silhouette*0.44)+wiggle
			var y: float = profile[k]*silhouette*(0.83+0.12*sin(f*9.0+variant))
			course.append(Vector3(x,y,f-0.5))
		shape.append(course)
	for j in range(8):
		for k in range(xs.size()-1):
			for pt in [shape[j][k],shape[j][k+1],shape[j+1][k],shape[j][k+1],shape[j+1][k+1],shape[j+1][k]]:
				st.add_vertex(pt)
	st.index()
	st.generate_normals()
	return st.commit()

func _gable_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: int in [-1,1]:
		var a := Vector3(s*0.5,0,-0.5)
		var b := Vector3(s*0.5,1,0)
		var c := Vector3(s*0.5,0,0.5)
		var verts := [a,b,c] if s == -1 else [a,c,b]
		for v in verts:
			st.set_normal(Vector3(s,0,0))
			st.add_vertex(v)
	return st.commit()

func _letter(value: String, at: Vector3, angle: float, pixel: float) -> void:
	var label := Label3D.new()
	label.text = value
	label.font_size = 32
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = Color("#ebe5d3")
	label.position = at
	label.rotation.y = angle
	label.double_sided = false
	add_child(label)

func _lamp(at: Vector3, reach: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.omni_range = reach
	lamp.light_color = Color("#ffb57c")
	lamp.light_energy = 1.15
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	add_child(lamp)
	lamp_centers.append(at)
	_scattered_light(at, Vector2(2.6,2.9), Color("#ffa35a"), .63)

func _road_lamp(pole: Vector3) -> void:
	# A short sodium-vapor cobrahead on an existing avenue pole.
	var head := pole + Vector3(2.46,5.62,.10)
	_beam(pole+Vector3(.12,5.06,0),pole+Vector3(1.24,5.72,.04),.09,"galv")
	_beam(pole+Vector3(1.24,5.72,.04),head+Vector3(0,.14,0),.09,"galv")
	_shape(mound,head+Vector3(0,.12,0),Vector3(.83,.29,.46),"metal")
	_shape(mound,head,Vector3(.62,.19,.36),"lamp")
	_shape(mound,head+Vector3(-.03,.23,-.02),Vector3(.75,.12,.39),"snow")
	var spot := SpotLight3D.new()
	spot.name = "RoadLamp"
	spot.position = head-Vector3.UP*.12
	spot.rotation_degrees = Vector3(-79,-72,0)
	spot.light_color = Color("#f3ae70")
	spot.light_energy = 3.4
	spot.spot_range = 8.8
	spot.spot_attenuation = .77
	spot.spot_angle = 46.0
	spot.spot_angle_attenuation = 1.7
	spot.shadow_enabled = false
	add_child(spot)
	lamp_centers.append(head)
	_scattered_light(head-Vector3.UP*.028,Vector2(4.1,4.9),Color("#ffb778"),1.15)

func _scattered_light(at: Vector3, size: Vector2, tint: Color, energy: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://world/lamp_glow.gdshader")
	mat.set_shader_parameter("lamp_color",tint)
	mat.set_shader_parameter("strength",energy)
	mat.set_shader_parameter("downward",.6)
	var card := QuadMesh.new()
	card.size = size
	var halo := MeshInstance3D.new()
	halo.mesh = card
	halo.position = at
	halo.material_override = mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

func _block(title: String, at: Vector3, dims: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = title
	var volume := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = dims
	volume.shape = bounds
	body.add_child(volume)
	body.position = at
	body.rotation.y = yaw
	add_child(body)

func _beam(a: Vector3, b: Vector3, width: float, material: String) -> void:
	var axis := b-a
	if axis.length_squared()<0.000001:
		return
	var orientation := Quaternion(Vector3.UP,axis.normalized())
	_shape_at(drum,Transform3D(Basis(orientation)*Basis.from_scale(Vector3(width,axis.length(),width)),(a+b)*0.5),material)

func _box(at: Vector3, dims: Vector3, material: String, rot := Vector3.ZERO) -> void:
	_shape(cube,at,dims,material,rot)

func _local(t: Transform3D, pos: Vector3, dims: Vector3, material: String, rot := Vector3.ZERO) -> void:
	_shape_at(cube,t*Transform3D(Basis.from_euler(rot)*Basis.from_scale(dims),pos),material)

func _shape(mesh: Mesh, at: Vector3, dims: Vector3, material: String, rot := Vector3.ZERO) -> void:
	_shape_at(mesh,Transform3D(Basis.from_euler(rot)*Basis.from_scale(dims),at),material)

func _shape_at(mesh: Mesh, t: Transform3D, material: String) -> void:
	if not batches.has(material):
		batches[material] = {}
	var group: Dictionary = batches[material]
	if not group.has(mesh):
		group[mesh] = []
	group[mesh].append(t)

func _flush_meshes() -> void:
	for key in batches:
		var group: Dictionary = batches[key]
		for mesh in group:
			var transforms: Array = group[mesh]
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.mesh = mesh
			instances.instance_count = transforms.size()
			for i in range(transforms.size()):
				instances.set_instance_transform(i,transforms[i])
			var renderer := MultiMeshInstance3D.new()
			renderer.name = "Scenery_" + str(key)
			renderer.multimesh = instances
			renderer.material_override = mats[key]
			renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(renderer)
	batches.clear()
