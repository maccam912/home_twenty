extends Node3D

const Route = preload("res://world/route.gd")
const Roadside = preload("res://world/roadside.gd")
const FieldRelief = preload("res://world/field_relief.gd")
const Backroads = preload("res://world/backroads.gd")
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
var bus_route_clip := Node3D.new()
var trunk_cells: Dictionary[Vector2i, StaticBody3D] = {}
var trunk_shape := BoxShape3D.new()
var mats := {}
var batches := {}
var snowfall: CPUParticles3D
var weather_camera: Camera3D
var last_weather_eye := Vector3.ZERO
var weather_velocity := Vector3.ZERO
var gust_strength := 0.0
var storm_seconds := 0.0
var ground_snow: Node3D
var ribbon_arrays: Array
var drift_center := Vector2i.MAX
var storm_env: Environment
var flake_material := ShaderMaterial.new()
var drift_material := ShaderMaterial.new()
var lamp_centers := PackedVector3Array()
var truck_position := Vector3(Route.HOME_PARK.x,0,Route.HOME_PARK.y)
var truck_forward := Vector3.RIGHT
var road_bounds: Array[Rect2] = []
var surface_cells: Dictionary = {}
const SCENERY_CELL := 384.0

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
	for surface: Array in Route.surfaces():
		var rect := Rect2(surface[0], surface[1] - surface[0])
		road_bounds.append(rect)
		var start := Vector2i((rect.position / SCENERY_CELL).floor())
		var end := Vector2i((rect.end / SCENERY_CELL).floor())
		for z in range(start.y, end.y + 1):
			for x in range(start.x, end.x + 1):
				var cell := Vector2i(x, z)
				if not surface_cells.has(cell):
					surface_cells[cell] = []
				surface_cells[cell].append(rect)
	_snowfield()
	_buildings()
	_road_furniture()
	_business_signs()
	_outer_roads()
	_contract_yards()
	Backroads.new(self).build()
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
		"school_bus": "#c0a047", "gravel": "#756d62", "orange": "#d18b4a", "black": "#383b3a", "silo": "#999b94", "gutter": "#939894"
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
	snowfall.emission_box_extents = Vector3(14,3.4,17)
	snowfall.direction = Vector3(1.,-.25,.28).normalized()
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
	ribbon_arrays = ribbons.commit_to_arrays()
	ground_snow = Node3D.new()
	ground_snow.name = "RunningGroundSnow"
	add_child(ground_snow)
	for i in 9:
		var tile := MeshInstance3D.new()
		tile.material_override = drift_material
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ground_snow.add_child(tile)
	_follow_ground_snow(Route.HOME_PARK)

func _follow_ground_snow(eye: Vector2) -> void:
	var center := Vector2i((eye / DRIFT_TILE).round())
	if drift_center == center:
		return
	drift_center = center
	for x in range(center.x - 1, center.x + 2):
		for z in range(center.y - 1, center.y + 2):
			var origin := Vector3(x * DRIFT_TILE, 0, z * DRIFT_TILE)
			var tile := ground_snow.get_child(posmod(x, 3) * 3 + posmod(z, 3)) as MeshInstance3D
			if tile.mesh and tile.position == origin:
				continue
			# Refit only tiles entering view, keeping each ribbon just above its field.
			var arrays := ribbon_arrays.duplicate()
			var vertices: PackedVector3Array = ribbon_arrays[Mesh.ARRAY_VERTEX].duplicate()
			for i in vertices.size():
				var p := vertices[i] + origin
				vertices[i].y += Roadside.height_at(p.x, p.z)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			var sheet := ArrayMesh.new()
			sheet.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			tile.mesh = sheet
			tile.position = origin

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
		_follow_ground_snow(Vector2(eye.x, eye.z))
		var travel := eye - last_weather_eye
		if weather_camera != camera or travel.length_squared() > 25.:
			weather_velocity = Vector3.ZERO
			snowfall.restart()
			weather_camera = camera
		elif delta > 0.:
			# Snow stays in world space after emission. Seed it ahead so the
			# driver still passes through flakes at highway speed.
			var velocity := Vector3(travel.x, 0., travel.z) / delta
			weather_velocity = weather_velocity.lerp(velocity, 1. - exp(-delta * 3.))
		last_weather_eye = eye
		snowfall.global_position = eye + Vector3(-11, 2.1, -3.1) - camera.global_basis.z * 8.5 + weather_velocity

func _snowfield() -> void:
	var ground := Roadside.new()
	ground.build(mats.snow)
	add_child(ground)
	var fence := Route.COUNTY_BOUNDS.grow(70.0)
	for x: float in [fence.position.x, fence.end.x]:
		_block("Township edge", Vector3(x, 8, fence.get_center().y), Vector3(2, 62, fence.size.y + 2))
	for z: float in [fence.position.y, fence.end.y]:
		_block("Township edge", Vector3(fence.get_center().x, 8, z), Vector3(fence.size.x + 2, 62, 2))

	# Wind packs shallow sheets against the slopes of the fields.
	for i in range(175):
		var x := rng.randf_range(42,590) * (-1 if i%2 else 1)
		var z := rng.randf_range(Roadside.CORE_NORTH-100,Roadside.CORE_SOUTH+100)
		if _near_surface(Vector2(x, z), 32):
			continue
		_drift(Vector3(x,-.07,z),Vector3(rng.randf_range(8,23),rng.randf_range(.18,.65),rng.randf_range(22,60)),rng.randf_range(1.06,1.39))

func _near_surface(point: Vector2, margin: float) -> bool:
	var start := Vector2i(((point - Vector2.ONE * margin) / SCENERY_CELL).floor())
	var end := Vector2i(((point + Vector2.ONE * margin) / SCENERY_CELL).floor())
	for z in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			for rect: Rect2 in surface_cells.get(Vector2i(x,z), []):
				if rect.grow(margin).has_point(point):
					return true
	return false

func _intersects_surface(footprint: Rect2) -> bool:
	for surface in road_bounds:
		if surface.intersects(footprint):
			return true
	return false


func _drift(at: Vector3, dims: Vector3, yaw: float) -> void:
	at.y += Roadside.height_at(at.x, at.z)
	var rise_x := FieldRelief.height_at(at.x + 1, at.z) - FieldRelief.height_at(at.x - 1, at.z)
	var rise_z := FieldRelief.height_at(at.x, at.z + 1) - FieldRelief.height_at(at.x, at.z - 1)
	var slope := Basis(Quaternion(Vector3.UP, Vector3(-rise_x, 2, -rise_z).normalized()))
	var axes := slope * Basis(Vector3.UP, yaw) * Basis.from_scale(dims)
	_shape_at(drift_forms[rng.randi_range(0,drift_forms.size()-1)], Transform3D(axes, at), "snow")

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
	var first_span := floori((first_z-Roadside.CORE_SOUTH)/46.0)
	var last_span := ceili((first_z-Roadside.CORE_NORTH)/46.0)
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

func _business_signs() -> void:
	var coop := Transform3D(Basis(Vector3.UP,-.32),Vector3(9.3,0,Route.COOP_Z))
	_painted_board("Feed co-op", coop, Vector2(3.95,1.83), 2.36, preload("res://world/art/feed_coop.webp"), false)
	for id: String in Route.Survey.BUSINESS_SIGNS:
		var site: Dictionary = Route.SITES[id]
		var board: Dictionary = Route.Survey.BUSINESS_SIGNS[id]
		var inward: Vector2 = site.mouth.direction_to(site.yard)
		var along := inward.orthogonal()
		# Set the large board back from the ditch and clear of the private lane.
		var point: Vector2 = site.mouth + inward * 9.4 - along * 13.0
		var yaw := atan2(along.x, along.y) + .08
		var mount := Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x,0,point.y))
		var steel := id in ["station", "reese", "dahl"]
		_painted_board(site.name, mount, Vector2(board.width,board.width * .5), 2.82 if steel else 2.24, board.art, steel)

func _painted_board(title: String, mount: Transform3D, size: Vector2, center: float, art: Texture2D, steel: bool) -> void:
	var material := "galv" if steel else "creosote"
	var offsets := [0.0] if steel else [-size.x * .35, size.x * .35]
	var top := center - size.y * .5
	for x: float in offsets:
		var foot := mount * Vector3(x, 0, 0)
		var grade := Roadside.height_at(foot.x, foot.z)
		var post := Vector3(x,(top+grade)*.5,0)
		var thickness := .27 if steel else .19
		var dims := Vector3(thickness,top-grade,thickness)
		_local(mount,post,dims,material)
		_block(title + " signpost", mount * post, dims, mount.basis.get_euler().y)
	var board := mount.translated_local(Vector3.UP * center)
	_local(board, Vector3.ZERO, Vector3(size.x,size.y,.17), "metal" if steel else "wood")
	_block(title + " board", board.origin, Vector3(size.x,size.y,.17), board.basis.get_euler().y)
	_local(board, Vector3(0,size.y*.5+.035,0), Vector3(size.x+.06,.075,.25), "snow")
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = art
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness = 1.0
	var panel := QuadMesh.new()
	panel.size = size - Vector2(.04,.04)
	panel.material = mat
	# Each approach gets right-reading letters on its own side of the board.
	for side: float in [0.0, PI]:
		var face := MeshInstance3D.new()
		face.name = title + " painted face"
		face.mesh = panel
		face.transform = board.rotated_local(Vector3.UP,side).translated_local(Vector3(0,0,.092))
		face.visibility_range_end = 240
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(face)


# Sparse marker pairs and dated green blades make the new roads readable
# from both directions, including when a squall hides the next building.
func _outer_roads() -> void:
	for road: Dictionary in Route.ROADS.slice(1,4):
		var a: Vector2 = road.a
		var b: Vector2 = road.b
		var along := a.direction_to(b)
		var across := along.orthogonal()
		for distance in range(18, int(a.distance_to(b))-9, 32):
			for side: int in [-1, 1]:
				var at := a + along * (distance + side * 2) + across * side * 4.7
				if not _near_surface(at, .6):
					_snow_stake(Vector3(at.x, 0, at.y))
	for id: String in Route.SITES:
		if id == "beck":
			continue # The mailbox, road blade and snow poles mark this lane already.
		var site: Dictionary = Route.SITES[id]
		var mouth: Vector2 = site.mouth
		var toward: Vector2 = mouth.direction_to(site.yard)
		var across := toward.orthogonal()
		var pt := mouth + toward * 7.3 + across * 4.9
		var base := Vector3(pt.x, Roadside.height_at(pt.x, pt.y), pt.y)
		_box(base + Vector3.UP * 1.02, Vector3(.13, 2.04, .13), "creosote")
		_name_board(base + Vector3.UP * 1.93, site.name.to_upper(), atan2(across.x, across.y), maxf(2.9, site.name.length() * .135))
		for i in range(12, int(mouth.distance_to(site.yard)) - Route.YARD_MARGIN, 15):
			for side: int in [-1, 1]:
				pt = mouth + toward * i + across * 3.65 * side
				_snow_stake(Vector3(pt.x, 0, pt.y))
	_fence(Vector3(627,0,-1150), Vector3(627,0,-1242), 5.3)
	_fence(Vector3(270,0,-706), Vector3(323,0,-706), 4.9)
	for i in 18:
		_pine(Vector3(660 + rng.randf_range(0,9), 0, -1105 + i*4.8), rng.randf_range(7,13), true)

	# Bader's old two-wire feed is an unbroken sight line along the south
	# shoulder of Mill. The poles sit beyond the plow wings at the crossings.
	var previous := Vector3.ZERO
	for i in range(11):
		var pole := Vector3(24+i*59,0,-1770)
		pole.y = Roadside.height_at(pole.x, pole.z)
		_beam(pole,pole+Vector3(.13,7.7,.09),.23,"pole")
		_box(pole+Vector3(.13,7.24,.09),Vector3(.17,.18,1.85),"wood")
		for side: float in [-.68,.68]:
			var top := Vector3(.13,7.43,side+.09)
			_shape(drum,pole+top,Vector3(.14,.23,.14),"glass")
			if i:
				_wire(previous+top,pole+top,1.07,.043)
		_block("Mill line pole",pole+Vector3.UP*3,Vector3(.26,6,.26))
		previous = pole
	_water_tower(Vector3(664,0,-1798))
	# At the two right-angle corners the paired arrows face oncoming traffic.
	for z: float in [-1780,-720]:
		_bend_marker(Vector3(646,0,z),-PI/2, 1 if z < -1000 else -1)
		var north := z < -1000
		_bend_marker(Vector3(640,0,z+(-6 if north else 6)),0 if north else PI,-1 if north else 1)

	# Snow-capped banks catch the low beams on either side of the road even
	# in a whiteout. Keep the entrances open for every county contract.
	for road: Dictionary in Route.ROADS.slice(1,4):
		var a: Vector2 = road.a
		var b: Vector2 = road.b
		var dir := a.direction_to(b)
		for i in range(28, int(a.distance_to(b)) - 25, 23):
			var side := 1 if i % 2 else -1
			var center := a + dir * (i + rng.randf_range(-3,3))
			var at := center + dir.orthogonal() * side * (Route.road_half_width(road.name) + rng.randf_range(1.3,1.8))
			var length := rng.randf_range(13,24)
			var half_span := dir.abs() * (length*.5) + dir.orthogonal().abs()*.72
			var footprint := Rect2(at-half_span, half_span*2).grow(.7)
			if not _intersects_surface(footprint):
				_drift(Vector3(at.x,-.035,at.y),Vector3(1.4,rng.randf_range(.29,.58),length),atan2(dir.x,dir.y))
	# Line follows the woodlot edges. Short gaps leave the section corners and
	# farm entrances visible from the cab.
	for stand: Vector2 in [Vector2(625,-1760), Vector2(665,-1625), Vector2(611,-1398),
			Vector2(664,-1294), Vector2(619,-1210), Vector2(660,-997), Vector2(622,-836)]:
		for i in 7:
			var at := Vector3(stand.x+rng.randf_range(-4,4),0,stand.y+i*5.5)
			if i%3 == 0:
				_pine(at,rng.randf_range(7.3,11.4),true)
			else:
				_bare_tree(at,rng.randf_range(7.8,12.5),false)
	_fence(Vector3(650,0,-1615),Vector3(650,0,-1535),5.7)
	_fence(Vector3(629,0,-1355),Vector3(629,0,-1290),4.9)
	_fence(Vector3(651,0,-923),Vector3(651,0,-854),5.2)
	_field_frames(Vector3(290,0,-692))
	for at: Vector3 in [Vector3(63,0,-734), Vector3(130,0,-699), Vector3(374,0,-737),
			Vector3(520,0,-696), Vector3(585,0,-734)]:
		_bare_tree(at,rng.randf_range(8,11),true)

func _bend_marker(at: Vector3, yaw: float, arrow: int) -> void:
	at.y = Roadside.height_at(at.x, at.z)
	var t := Transform3D(Basis(Vector3.UP,yaw),at)
	_local(t,Vector3(0,.93,0),Vector3(.12,1.86,.14),"creosote")
	_local(t,Vector3(0,1.75,0),Vector3(1.60,.62,.10),"school_bus")
	for x: float in [-.38,.38]:
		for half: float in [-1,1]:
			_local(t,Vector3(x,1.75+half*.12,.068),Vector3(.34,.12,.025),"black",
					Vector3(0,0,-arrow*half*.65))
	_local(t,Vector3(0,2.09,0),Vector3(1.65,.065,.15),"snow")

func _water_tower(at: Vector3) -> void:
	for sx: float in [-1,1]:
		for sz: float in [-1,1]:
			var foot := at+Vector3(3.4*sx,0,3.4*sz)
			var top := at+Vector3(2.0*sx,12,2.0*sz)
			_beam(foot,top,.29,"galv")
			_beam(foot.lerp(top,.19),at+Vector3(-2.15*sx,10.7,2.15*sz),.09,"metal")
			_beam(foot.lerp(top,.28),at+Vector3(2.15*sx,10.7,-2.15*sz),.09,"metal")
	_shape(drum,at+Vector3.UP*13.9,Vector3(7.35,4.2,7.35),"galv")
	_shape(mound,at+Vector3.UP*11.95,Vector3(7.33,2.8,7.33),"metal")
	_shape(mound,at+Vector3.UP*16.03,Vector3(7.58,2.3,7.58),"snow")
	_shape(drum,at+Vector3.UP*5.7,Vector3(.72,11.4,.72),"metal")
	_box(at+Vector3.UP*17.15,Vector3(.14,.25,.14),"red")
	_block("Water tower",at+Vector3.UP*5.7,Vector3(.75,11.4,.75))

func _field_frames(base: Vector3) -> void:
	# Rolled-up lath on the bare ginseng shade frames, stacked downwind.
	for row in 3:
		var front := base + Vector3(0,0,row*8.0)
		for i in 6:
			var post := front + Vector3(i*7.2,0,0)
			_box(post+Vector3(0,1.22,0),Vector3(.17,2.44,.17),"wood")
			if i:
				_beam(post+Vector3(-7.2,2.32,0),post+Vector3(0,2.32,0),.085,"galv")
			if row:
				_wire(post+Vector3.UP*2.32,post+Vector3(0,2.32,-8),.21,.04)
		_box(front+Vector3(38,.42,-1),Vector3(1.55,.72,6.1),"wood")
		_box(front+Vector3(38,.81,-1),Vector3(1.61,.11,6.2),"snow")

func _name_board(at: Vector3, title: String, yaw: float, width := 1.65) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), at)
	_local(t, Vector3.ZERO, Vector3(width,.31,.09), "green")
	_local(t, Vector3(0,.17,0), Vector3(width+.04,.045,.12), "snow")
	for side: int in [-1, 1]:
		_letter(title, t * Vector3(0,0,side*.051), yaw + (PI if side < 0 else 0.0), .0048)

func _contract_yards() -> void:
	# Grain bins, elevator head, receiving scale and a row of loading doors.
	_silo(Vector3(195,0,-1860), 3.5, 14.6)
	_silo(Vector3(185,0,-1860), 3.5, 12.8)
	_barn(Vector3(213,0,-1870), 0, Vector3(17,5.1,9), false)
	_box(Vector3(203,8.3,-1866), Vector3(2.4,16.6,3.1), "shed_siding")
	_box(Vector3(195,12.9,-1866), Vector3(17,.8,.95), "galv")
	var sign := Vector3(213,4.22,-1865.35)
	_box(sign, Vector3(9.3,.94,.16), "green")
	_letter("BADER FEED & GRAIN", sign+Vector3(0,0,.09), 0, .0132)
	_lamp(Vector3(216.7,3.56,-1864.9), 6.8)
	_drop_box(Route.SITES.mill.stop, "SCALE TICKETS")
	_service_station()
	_churchyard()
	_school_turn()
	_barn(Vector3(182,0,-808), 0, Vector3(17,5.6,12), true)
	_silo(Vector3(160,0,-810), 3.2, 15.2)
	_corn_crib(Vector3(204,0,-811), -.11)
	for i in 6:
		_pine(Vector3(159+i*8.1,0,-824+rng.randf_range(-1,1)),rng.randf_range(6.9,11.5),true)
	var rack := Vector3(Route.SITES.kroll.stop.x, 0, Route.SITES.kroll.stop.y)
	_box(rack+Vector3.UP*.62,Vector3(2.4,.14,.82),"wood")
	_block("Milk can stand",rack+Vector3.UP*.58,Vector3(2.4,1.1,.82))
	for x: float in [-.94, .94]:
		_box(rack+Vector3(x,.31,0),Vector3(.15,.62,.65),"creosote")
	for x: float in [-.62,.03,.65]:
		var can := rack + Vector3(x,1.04,0)
		_shape(drum,can,Vector3(.45,.72,.45),"galv")
		_shape(drum,can+Vector3.UP*.39,Vector3(.33,.13,.33),"metal")
		_box(can+Vector3(0,.48,0),Vector3(.19,.05,.08),"black")
	_gravel_pit()

func _drop_box(point: Vector2, title: String) -> void:
	var t := Transform3D(Basis.IDENTITY, Vector3(point.x,0,point.y))
	_local(t, Vector3(0,.62,0),Vector3(.17,1.24,.16),"creosote")
	_block("Yard box", t * Vector3(0,.78,0), Vector3(.65,1.5,.4))
	_local(t, Vector3(0,1.22,0),Vector3(.79,.62,.42),"galv")
	_local(t, Vector3(0,1.41,.22),Vector3(.52,.045,.027),"black")
	_local(t, Vector3(0,1.56,0),Vector3(.86,.08,.51),"snow")
	_local(t, Vector3(0,1.17,.225),Vector3(.75,.18,.028),"green")
	_letter(title,t*Vector3(0,1.17,.245),0,.0022)

func _service_station() -> void:
	var t := Transform3D(Basis.IDENTITY, Vector3(470,0,-1714))
	_local(t, Vector3(0,2.05,0), Vector3(12,4.1,6), "cream_board")
	_block("Closed service station",t*Vector3(0,2.05,0),Vector3(12,4.1,6))
	_local(t, Vector3(0,4.18,0),Vector3(12.6,.30,6.6),"snow")
	_local(t, Vector3(-2.5,2,-3.07),Vector3(5,3.55,.13),"galv")
	for i in 9:
		_local(t, Vector3(-2.5,.45+i*.38,-3.16),Vector3(4.9,.04,.04),"metal")
	_local(t, Vector3(3.0,2,-3.07),Vector3(3.3,1.38,.14),"glass")
	_local(t, Vector3(0,3.68,-3.13),Vector3(11.5,.78,.14),"dark_red")
	_letter("PIKE   •   SERVICE",t*Vector3(0,3.68,-3.21),PI,.016)
	_lamp(t*Vector3(3.64,2.93,-3.18), 5.6)
	_bare_tree(Vector3(487,0,-1707), 7.2, true)
	var canopy := Vector3(474,3.65,-1730)
	_box(canopy,Vector3(8,.47,5),"dark_red")
	_box(canopy+Vector3.UP*.27,Vector3(8.15,.11,5.15),"snow")
	_box(canopy+Vector3(0,.04,-2.51),Vector3(8,.14,.045),"trim")
	for z: float in [-1731.5,-1728.5]:
		_box(Vector3(477.4,1.74,z),Vector3(.16,3.48,.16),"red")
		_box(Vector3(476.3,.76,z),Vector3(.71,1.52,.64),"trim")
		_box(Vector3(475.93,1.14,z),Vector3(.045,.28,.49),"black")
		_block("Pump island",Vector3(476.3,.76,z),Vector3(.75,1.52,.68))
	_drop_box(Route.SITES.station.stop, "SERVICE BELL")
	# The old receiver under its blue metal rain hood, outside the locked shop.
	var phone := Vector3(Route.PHONE.x,0,Route.PHONE.y)
	_box(phone+Vector3.UP*.81,Vector3(.14,1.62,.14),"galv")
	_block("Telephone",phone+Vector3.UP*.87,Vector3(.64,1.74,.47))
	_box(phone+Vector3.UP*1.47,Vector3(.65,.83,.32),"green")
	_box(phone+Vector3(0,1.47,-.19),Vector3(.33,.44,.08),"galv")
	_box(phone+Vector3(.026,1.623,-.236),Vector3(.195,.071,.014),"trim")
	_box(phone+Vector3(.026,1.625,-.246),Vector3(.141,.016,.006),"black")
	_box(phone+Vector3(.031,1.456,-.239),Vector3(.172,.192,.02),"wire")
	for row in 4:
		for col in 3:
			var key := phone + Vector3(-.025+col*.055,1.522-row*.045,-.254)
			_box(key,Vector3(.037,.029,.012),"trim")
	_box(phone+Vector3(.031,1.288,-.235),Vector3(.136,.047,.023),"black")
	_box(phone+Vector3(-.19,1.46,-.25),Vector3(.09,.33,.09),"black")
	for y: float in [1.30,1.61]:
		_box(phone+Vector3(-.18,y,-.25),Vector3(.16,.11,.17),"black")
	var cord := PackedVector3Array([Vector3(-.19,1.26,-.27),Vector3(-.204,1.03,-.289),
			Vector3(-.174,.901,-.274),Vector3(-.128,.881,-.25),Vector3(-.087,.926,-.227),
			Vector3(-.076,1.209,-.186)])
	for i in range(1, cord.size()):
		_beam(phone+cord[i-1],phone+cord[i],.017,"wire")
	_box(phone+Vector3(0,1.93,-.15),Vector3(.82,.16,.77),"green")
	for side: int in [-1,1]:
		_box(phone+Vector3(side*.36,1.70,-.13),Vector3(.08,.42,.70),"green")
	_letter("PHONE",phone+Vector3(0,1.94,-.545),PI,.0043)

func _churchyard() -> void:
	var t := Transform3D(Basis(Vector3.UP, PI/2),Vector3(551,0,-1461))
	_local(t,Vector3(0,2.15,0),Vector3(8.4,4.3,13),"cream_board")
	_structure_roof(t,8.4,13,4.3,3.8,"cream_board")
	_block("Lutheran church",t*Vector3(0,2.15,0),Vector3(8.4,4.3,13),PI/2)
	_local(t,Vector3(0,3.15,6.95),Vector3(3,6.3,2.7),"cream_board")
	_local(t,Vector3(0,1.22,8.33),Vector3(1.62,2.44,.11),"trim")
	_local(t,Vector3(0,1.18,8.40),Vector3(1.38,2.32,.10),"dark_red")
	_local(t,Vector3(0,1.19,8.46),Vector3(.035,2.32,.02),"black")
	_window(t,Vector3(0,3.25,8.32),.74,1.19,0,true)
	_local(t,Vector3(0,.15,8.87),Vector3(2.08,.30,1.4),"stone")
	_bare_tree(Vector3(552,0,-1480), 8.7, true)
	_pine(Vector3(547,0,-1448), 7.4)
	_local(t,Vector3(0,7,6.95),Vector3(2.25,1.7,2.25),"green")
	_local(t,Vector3(0,7.08,8.10),Vector3(1.0,.91,.07),"black")
	# Four-sided belfry spire.
	var spire := CylinderMesh.new()
	spire.top_radius = 0
	spire.bottom_radius = 1.84
	spire.height = 4.3
	spire.radial_segments = 4
	spire.rings = 0
	_shape_at(spire,t*Transform3D(Basis(Vector3.UP,PI/4),Vector3(0,9.84,6.95)),"green")
	_local(t,Vector3(0,12.28,6.95),Vector3(.085,1.46,.085),"metal")
	_local(t,Vector3(0,12.6,6.95),Vector3(.7,.08,.08),"metal")
	for x: float in [-4.23,4.23]:
		for z: float in [-3.6,0,3.6]:
			_window(t,Vector3(x,2.53,z),.78,2.0,PI/2*signf(x),false)
	_drop_box(Route.SITES.lutheran.stop, "ST. LUKE’S")
	var plot := Vector3(563,0,-1476)
	for dx: float in [-2.4, 0, 2.4]:
		_box(plot+Vector3(dx,.11,-.38),Vector3(1.14,.22,.64),"stone")
		_box(plot+Vector3(dx,.50,-.38),Vector3(.8,.72,.25),"stone")
		_shape(mound,plot+Vector3(dx,.86,-.38),Vector3(.81,.17,.29),"snow")
	_fence(plot+Vector3(-3.7,0,-2),plot+Vector3(3.7,0,-2),3.7)

func _school_turn() -> void:
	var t := Transform3D(Basis.IDENTITY,Vector3(448,0,-638))
	_local(t,Vector3(0,1.16,0),Vector3(5.2,2.32,.20),"school_bus")
	_local(t,Vector3(0,2.49,-1),Vector3(5.52,.26,2.54),"snow",Vector3(-.09,0,0))
	for x: float in [-2.48,2.48]:
		_local(t,Vector3(x,1.16,-1),Vector3(.21,2.32,2.11),"school_bus")
	_local(t,Vector3(0,.58,-.6),Vector3(4.42,.12,.61),"wood")
	_block("Bus shelter",t*Vector3(0,1.15,.05),Vector3(5.2,2.3,.25))
	_letter("BELL SCHOOL",t*Vector3(0,2.4,-2.31),PI,.008)
	# Old brick schoolhouse, with its sash windows and a bell in the roof frame.
	var school := Transform3D(Basis(Vector3.UP,-.07),Vector3(435,0,-625))
	_local(school,Vector3(0,2.02,0),Vector3(16,4.04,9),"brick")
	_structure_roof(school,16,9,4.04,2.32,"cream_board")
	_block("Schoolhouse",school*Vector3(0,2.02,0),Vector3(16,4.04,9),-.07)
	for x: float in [-5.9,-3.85,-1.8,3.65,5.7]:
		_window(school,Vector3(x,2.22,-4.56),1.24,1.83,PI,x == 3.65)
	_local(school,Vector3(.72,1.26,-4.61),Vector3(1.44,2.5,.19),"green")
	for x: float in [-.85,.85]:
		for z: float in [-.78,.78]:
			_local(school,Vector3(x,6.93,z),Vector3(.16,2.36,.16),"trim")
	_shape_at(mound,school*Transform3D(Basis.from_scale(Vector3(.72,.97,.72)),Vector3(0,7.24,0)),"black")
	_local(school,Vector3(0,8.15,0),Vector3(2.06,.22,1.95),"snow")
	_bare_tree(Vector3(458,0,-632),8.7,true)
	var gate := Vector3(Route.SITES.bell.stop.x,0,Route.SITES.bell.stop.y)
	_block("Road barricade",gate+Vector3.UP*.55,Vector3(2.6,1.08,.28))
	for x: float in [-1.12,1.12]:
		_box(gate+Vector3(x,.49,0),Vector3(.11,1.0,.17),"wood")
		_box(gate+Vector3(x,.08,0),Vector3(.29,.16,.68),"wood")
	_box(gate+Vector3.UP*.89,Vector3(2.65,.31,.11),"orange")
	for x: float in [-.88,0,.88]:
		_box(gate+Vector3(x,.89,-.065),Vector3(.23,.31,.035),"trim",Vector3(0,0,-.30))
	var board := Vector3(Route.NOTICE.x,0,Route.NOTICE.y)
	_block("District noticeboard",board+Vector3.UP*1.07,Vector3(1.6,2.14,.22))
	for x: float in [-.68,.68]:
		_box(board+Vector3(x,.99,0),Vector3(.12,1.98,.14),"wood")
	_box(board+Vector3.UP*1.65,Vector3(1.56,1.0,.20),"green")
	_box(board+Vector3(0,1.65,-.116),Vector3(1.38,.81,.04),"glass")
	for x: float in [.15,.46]:
		_box(board+Vector3(x,1.68,-.15),Vector3(.28,.39,.025),"trim",Vector3(0,0,x*.11))
	var route_paper := StandardMaterial3D.new()
	route_paper.albedo_color = Color("#d9c8a1")
	route_paper.emission_enabled = true
	route_paper.emission = Color("#a99872")
	route_paper.emission_energy_multiplier = .23
	mats["route_paper"] = route_paper
	_box(board+Vector3(-.36,1.67,-.15),Vector3(.45,.41,.018),"route_paper")
	var old_route := _letter("PINERY RD.\nONE CHILD\nDEC. 1958",board+Vector3(-.36,1.67,-.162),PI,.00175)
	old_route.modulate = Color("#2e2721")
	# The ordinary bus sheet is held by one thumbtack. It stays pinned aside
	# after the driver finds the earlier route underneath.
	add_child(bus_route_clip)
	bus_route_clip.position = board+Vector3(-.15,1.86,-.184)
	var sheet := MeshInstance3D.new()
	sheet.mesh = cube
	sheet.scale = Vector3(.46,.42,.01)
	sheet.position = Vector3(-.21,-.19,0)
	sheet.material_override = route_paper
	bus_route_clip.add_child(sheet)
	var current_route := _letter("ROUTE 4\nMILL RD.\nLINE RD.",board+Vector3(-.36,1.67,-.198),PI,.00175)
	current_route.modulate = Color("#38423c")
	current_route.reparent(bus_route_clip)
	_box(bus_route_clip.position-Vector3(0,0,.014),Vector3(.034,.034,.013),"dark_red")
	_box(board+Vector3.UP*2.21,Vector3(1.73,.12,.42),"snow")
	_letter("DISTRICT 4",board+Vector3(0,2.02,-.16),PI,.0036)

func uncover_bus_route() -> void:
	create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP).tween_property(
			bus_route_clip, "rotation:z", 1.72, .45).set_trans(Tween.TRANS_SINE)

func _gravel_pit() -> void:
	var hopper := Vector3(96,0,-2121)
	for x: float in [-2.4,2.4]:
		for z: float in [-2.1,2.1]:
			_box(hopper+Vector3(x,2.0,z),Vector3(.24,4.0,.24),"metal")
	var funnel := CylinderMesh.new()
	funnel.top_radius = 3.4
	funnel.bottom_radius = .71
	funnel.height = 2.7
	funnel.radial_segments = 4
	funnel.rings = 0
	_shape(funnel,hopper+Vector3.UP*3.28,Vector3.ONE,"galv",Vector3(0,PI/4,0))
	_box(hopper+Vector3.UP*5.31,Vector3(4.84,1.42,4.84),"metal")
	_box(hopper+Vector3.UP*6.08,Vector3(4.98,.14,4.98),"snow")
	_block("Gravel hopper", hopper+Vector3.UP*2.9,Vector3(4.9,5.8,4.9))
	var belt_start := hopper + Vector3(-.3,1.15,-.8)
	var belt_end := hopper + Vector3(12.4,5.34,-7.8)
	var forward := belt_start.direction_to(belt_end)
	var belt := Transform3D(Basis.looking_at(forward),belt_start.lerp(belt_end,.5))
	var length := belt_start.distance_to(belt_end)
	_local(belt,Vector3.ZERO,Vector3(1.45,.20,length),"black")
	for side: float in [-.78,.78]:
		_local(belt,Vector3(side,0,0),Vector3(.13,.58,length),"green")
		_local(belt,Vector3(side,.32,0),Vector3(.14,.075,length),"snow")
		_beam(belt * Vector3(side,0,-length*.4), belt_end+Vector3(side,-5.27,-1.4), .17,"galv")
	var bay := hopper + Vector3(10,0,-10)
	for i in 3:
		var center := bay + Vector3(i*6.2,0,i*.9)
		var scale := Vector3(11+i,.9+i*.42,10+i)
		_shape(mound,center,scale*Vector3(1,4.6,1),"gravel")
		_shape(mound,center+Vector3(.22,.25,.04),scale*Vector3(.96,4.42,.96),"snow")
	for i in 7:
		_pine(hopper+Vector3(17+i*4.1,0,-27+rng.randf_range(-2,2)),rng.randf_range(6,11),true)
	_drop_box(Route.SITES.quarry.stop,"WEIGH SLIPS")

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
		p.y = Roadside.height_at(p.x, p.z)
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
	for pos: Vector3 in [Vector3(-82,0,Route.HOME_Z+16), Vector3(-104,0,Route.HOME_Z+20),
		Vector3(-117,0,Route.HOME_Z+9), Vector3(140,0,Route.BECK_Z+30),
		Vector3(153,0,Route.BECK_Z+24), Vector3(161,0,Route.BECK_Z+38)]:
		_pine(pos,rng.randf_range(8.2,13.1))
	for pos: Vector3 in [Vector3(-106,0,Route.HOME_Z-17),Vector3(-72,0,Route.HOME_Z-9),
		Vector3(99,0,Route.BECK_Z+12),Vector3(145,0,Route.BECK_Z-23),
		Vector3(36,0,Route.COOP_Z-33),Vector3(42,0,Route.COOP_Z-35)]:
		_bare_tree(pos,rng.randf_range(6.8,10.3),true)

	# Discrete windbreaks mark distant property lines, leaving the central fields open.
	for stand: Vector2 in [Vector2(301,92),Vector2(-314,-362),Vector2(403,-697),
		Vector2(-264,-1142),Vector2(358,-1440),Vector2(-316,-1669)]:
		for i in range(13):
			var x := stand.x + rng.randf_range(-14,14)
			var z := stand.y + i*4.3 + rng.randf_range(-4.3,4.3)
			if i%4 == 0:
				_bare_tree(Vector3(x,0,z),rng.randf_range(7,13),false)
			else:
				_pine(Vector3(x,0,z),rng.randf_range(7,15),true)
	preload("res://world/trees/woodlots.gd").new().plant(self)
	# Isolated stalks and broken fencelines surface where the fields meet the ditch.
	for i in range(140):
		var x := rng.randf_range(8.5,48.0) * (-1 if i%2 else 1)
		var z := rng.randf_range(Roadside.CORE_NORTH,Roadside.CORE_SOUTH)
		if _near_surface(Vector2(x, z), 2.5):
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
	for road: Dictionary in Route.ROADS:
		var start: Vector2 = road.a
		var end: Vector2 = road.b
		var along := start.direction_to(end)
		var width := Route.road_half_width(road.name)
		for side: int in [-1, 1]:
			var across := along.orthogonal() * side
			var station := rng.randf_range(3, 40)
			while station < start.distance_to(end):
				var length := rng.randf_range(4, 15)
				var offset := width + rng.randf_range(4.0, 7.2)
				for i in ceili(length * .75):
					var p := start + along * (station + rng.randf_range(0, length)) + across * (offset + rng.randf_range(-.8, .8))
					var grade := Roadside.height_at(p.x, p.y)
					if grade > -.22:
						continue
					var tussock := Vector3(p.x, grade - .03, p.y)
					var height := rng.randf_range(.68, 1.24)
					_shape(clumps[rng.randi_range(0, 2)], tussock, Vector3(1,height,1), "sedge", Vector3(0,rng.randf_range(-.65,.65),0))
				station += length + rng.randf_range(17, 99)


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
	trunk_shape.size = Vector3(.35, 4, .35)
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
	at.y = Roadside.height_at(at.x, at.z)
	var placement := Transform3D(Basis.from_euler(rot).scaled_local(scale_to_height), at)
	var boughs := tree_meshes["Spruce%dBoughs%s" % [variant,suffix]]
	if not _crown_fits(placement * boughs.get_aabb()):
		return
	_shape_at(boughs, placement, "spruce_needles")
	_shape_at(tree_meshes["Spruce%dWood%s" % [variant,suffix]], placement, "tree_bark")
	_tree_trunk(at)

func _bare_tree(at: Vector3, height: float, near: bool) -> void:
	var variant := rng.randi_range(0,2)
	var suffix := "" if near else "Far"
	var scale_to_height := Vector3.ONE*height*0.1
	var rot := Vector3(0,rng.randf()*TAU,0)
	at.y = Roadside.height_at(at.x, at.z)
	var placement := Transform3D(Basis.from_euler(rot).scaled_local(scale_to_height), at)
	var mesh := tree_meshes["Birch%dWood%s" % [variant,suffix]]
	if not _crown_fits(placement * mesh.get_aabb()):
		return
	_shape_at(mesh, placement, "tree_bark")
	_tree_trunk(at)

func _crown_fits(bounds: AABB) -> bool:
	var center := bounds.get_center()
	# Include wind displacement of the tallest crowns at full gust.
	return not _near_surface(Vector2(center.x, center.z), maxf(bounds.size.x, bounds.size.z) * .5 + .6)

func _tree_trunk(at: Vector3) -> void:
	# Share a collision body per field cell, even for trees using the distant mesh.
	var cell := Vector2i(floori(at.x / SCENERY_CELL), floori(at.z / SCENERY_CELL))
	if not trunk_cells.has(cell):
		var body := StaticBody3D.new()
		body.position = Vector3(cell.x * SCENERY_CELL, 0, cell.y * SCENERY_CELL)
		add_child(body)
		trunk_cells[cell] = body
	var trunks := trunk_cells[cell]
	var owner_id := trunks.create_shape_owner(trunks)
	trunks.shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, at - trunks.position + Vector3.UP * 2))
	trunks.shape_owner_add_shape(owner_id, trunk_shape)

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

func _letter(value: String, at: Vector3, angle: float, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = 32
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = Color("#ebe5d3")
	label.position = at
	label.rotation.y = angle
	label.double_sided = false
	label.visibility_range_end = 125.0
	add_child(label)
	return label

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
	# A visible roadside post should draw only its own stretch of road and fields.
	var cell := Vector2i(floori(t.origin.x / SCENERY_CELL), floori(t.origin.z / SCENERY_CELL))
	if not batches.has(cell):
		batches[cell] = {}
	var materials: Dictionary = batches[cell]
	if not materials.has(material):
		materials[material] = {}
	var group: Dictionary = materials[material]
	if not group.has(mesh):
		group[mesh] = []
	group[mesh].append(t)

func _flush_meshes() -> void:
	for cell: Vector2i in batches:
		var materials: Dictionary = batches[cell]
		for key: String in materials:
			var group: Dictionary = materials[key]
			for mesh: Mesh in group:
				var transforms: Array = group[mesh]
				var instances := MultiMesh.new()
				instances.transform_format = MultiMesh.TRANSFORM_3D
				instances.mesh = mesh
				instances.instance_count = transforms.size()
				var origin := Vector3(cell.x * SCENERY_CELL, 0, cell.y * SCENERY_CELL)
				for i in range(transforms.size()):
					var local: Transform3D = transforms[i]
					local.origin -= origin
					instances.set_instance_transform(i, local)
				var renderer := MultiMeshInstance3D.new()
				renderer.name = "Scenery_" + key
				renderer.multimesh = instances
				renderer.position = origin
				renderer.material_override = mats[key]
				renderer.visibility_range_end = 760
				renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(renderer)
	batches.clear()
