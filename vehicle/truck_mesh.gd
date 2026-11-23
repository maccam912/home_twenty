extends Node3D

# All dimensions are metres. The driver sits on the left and the grille faces -Z.
const Roadside = preload("res://world/roadside.gd")
const FRONT_AXLE_Z := -1.70
const REAR_AXLE_Z := 1.54
const HALF_TRACK := 0.91
const CUTTING_EDGE := Vector3(0, .047, -.270)
const BLADE_WIDTH := 2.54

var _colors: Dictionary = {}
var _wheels: Array[Node3D] = []
var _knuckles: Array[Node3D] = []
var _plow: Node3D
var _wheel: Node3D
var _cargo: Node3D
var _shovel: Node3D
var _shovel_rest: Transform3D
var _shovel_load: MeshInstance3D
var _needle: Node3D
var _beacon_rotor: Node3D
var _scatter := ShaderMaterial.new()
var _headlights: Array[SpotLight3D] = []
var _beacon_light: OmniLight3D
var _lamp_time := 0.0
var _tire_rotation := 0.0


func _ready() -> void:
	_paint("oxblood", Color("#773e35"), 0.28)
	_paint("cap", Color("#98554a"), 0.3)
	_paint("cream", Color("#d0bba0"), 0.12)
	_paint("rust", Color("#785044"))
	_paint("orange", Color("#cd622c"), 0.18)
	_paint("cut", Color("#9d9f96"), 0.65)
	_paint("steel", Color("#626a69"), 0.45)
	_paint("rim", Color("#aba99c"), 0.52)
	_paint("black", Color("#202422"))
	_paint("rubber", Color("#282b2b"))
	_paint("dash", Color("#474840"))
	_paint("cloth", Color("#786d5c"))
	_paint("sack", Color("#b4a285"))
	_paint("paper", Color("#d9c8a1"))
	_paint("mapink", Color("#697865"))
	_paint("mirror", Color("#94a7a9"), 0.58)
	_paint("headlamp", Color("#fff0bc"), 0.05, 2.5)
	_paint("amber", Color("#ffb34b"), 0.05, 1.0)
	_paint("beacon", Color("#ff992f"), 0.05, 4.0)
	_paint("red", Color("#d44f39"), 0.0, 0.7)
	_paint("dial", Color("#b7c99c"), 0.0, 0.5)
	_paint("glass", Color(0.39, 0.52, 0.54, 0.09))
	for entry in [["oxblood", 0.32], ["cap", 0.28], ["cream", 0.18], ["orange", 0.49], ["cut", 0.35]]:
		var old: StandardMaterial3D = _colors[entry[0]]
		var worn := ShaderMaterial.new()
		worn.shader = preload("res://vehicle/weathered_metal.gdshader")
		worn.set_shader_parameter("finish", old.albedo_color)
		worn.set_shader_parameter("metalness", old.metallic)
		worn.set_shader_parameter("wear", entry[1])
		_colors[entry[0]] = worn
	var glazing := ShaderMaterial.new()
	glazing.shader = preload("res://vehicle/windshield.gdshader")
	_colors["windshield"] = glazing
	_chassis()
	_cab()
	_door_signs()
	_bed()
	_front_end()
	_make_plow()
	_lighting()


func _paint(key: String, color: Color, metallic := 0.0, emission := 0.0) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.77 - metallic * 0.42
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	_colors[key] = material


func _piece(p: Node3D, mesh: Mesh, pos: Vector3, key: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _colors[key]
	node.position = pos
	p.add_child(node)
	return node


func _box(p: Node3D, pos: Vector3, size: Vector3, mat: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _piece(p, mesh, pos, mat)


func _cyl(p: Node3D, pos: Vector3, radius: float, height: float, mat: String, sides := 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 0
	return _piece(p, mesh, pos, mat)


func _bar(p: Node3D, a: Vector3, b: Vector3, width: float, depth: float, mat: String) -> MeshInstance3D:
	var bar := _box(p, (a + b) * 0.5, Vector3(width, a.distance_to(b), depth), mat)
	bar.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return bar


func _joint(p: Node3D, pos: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.position = pos
	p.add_child(joint)
	return joint


func _chassis() -> void:
	_box(self, Vector3(0, 0.56, 0.04), Vector3(1.35, 0.28, 4.86), "black")
	# Axles and rocker boxes span the open space beneath the body.
	for z: float in [FRONT_AXLE_Z, REAR_AXLE_Z]:
		_box(self, Vector3(0, 0.47, z), Vector3(1.84, 0.16, 0.18), "steel")
		for s: float in [-1.0, 1.0]:
			var steer := _joint(self, Vector3(s * HALF_TRACK, 0.47, z))
			if z < 0:
				_knuckles.append(steer)
			var tire := _joint(steer, Vector3.ZERO)
			_wheels.append(tire)
			# A stepped tread and inset steel wheel keep the profile readable in fog.
			var sidewall := _cyl(tire, Vector3.ZERO, 0.441, 0.32, "rubber", 24)
			sidewall.rotation.z = PI / 2
			var tread := _cyl(tire, Vector3.ZERO, 0.462, 0.24, "black", 24)
			tread.rotation.z = PI / 2
			for i in range(12):
				var a := TAU * i / 12.0
				var lug := _box(tire, Vector3(0, sin(a) * 0.453, cos(a) * 0.453), Vector3(0.277, 0.105, 0.032), "rubber")
				lug.rotation.x = -a
			var rim := _cyl(tire, Vector3(s * 0.162, 0, 0), 0.272, 0.025, "rim", 16)
			rim.rotation.z = PI / 2
			var hub := _cyl(tire, Vector3(s * 0.19, 0, 0), 0.105, 0.075, "steel")
			hub.rotation.z = PI / 2
			for i in range(6):
				var a := TAU * i / 6.0
				var hole := _cyl(tire, Vector3(s * 0.177, 0.181 * sin(a), 0.181 * cos(a)), 0.043, 0.007, "black", 6)
				hole.rotation.z = PI / 2
	for s: float in [-1.0, 1.0]:
		_box(self, Vector3(s * 0.98, 0.60, -0.09), Vector3(0.22, 0.085, 1.37), "steel")
		_box(self, Vector3(s * 0.93, 0.61, 2.06), Vector3(0.305, 0.44, 0.042), "black")


func _cab() -> void:
	_box(self, Vector3(0, 1.03, -0.32), Vector3(1.96, 0.60, 1.97), "oxblood")
	_box(self, Vector3(0, 1.19, -1.82), Vector3(1.91, 0.39, 1.30), "oxblood")
	var hood := _box(self, Vector3(0, 1.403, -1.87), Vector3(1.91, 0.093, 1.30), "cap")
	hood.rotation.x = -0.032
	_box(self, Vector3(0, 2.055, -0.17), Vector3(1.88, 0.11, 1.39), "cap")
	_box(self, Vector3(0, 1.37, 0.53), Vector3(1.92, 0.31, 0.12), "oxblood")
	_box(self, Vector3(0, 1.76, 0.555), Vector3(1.67, 0.45, 0.028), "glass")
	_box(self, Vector3(0, 1.525, 0.55), Vector3(1.86, 0.045, 0.065), "black")
	for s: float in [-1.0, 1.0]:
		var x := 0.909 * s
		_bar(self, Vector3(x, 1.39, -1.285), Vector3(x, 2.03, -0.82), 0.080, 0.079, "oxblood")
		_bar(self, Vector3(x, 1.33, 0.47), Vector3(x, 2.04, 0.47), 0.097, 0.105, "oxblood")
		_box(self, Vector3(s * 0.947, 1.363, -0.33), Vector3(0.060, 0.053, 1.74), "black")
		_box(self, Vector3(s * 0.985, 0.96, -0.325), Vector3(0.019, 0.185, 1.95), "cream")
		_box(self, Vector3(s * 0.988, 1.286, 0.245), Vector3(0.031, 0.044, 0.209), "black")
		_box(self, Vector3(s * 0.985, 1.04, 0.44), Vector3(0.013, 0.55, 0.018), "rust")
		_bar(self, Vector3(x, 1.44, -0.96), Vector3(s * 1.14, 1.57, -0.91), 0.032, 0.033, "steel")
		_box(self, Vector3(s * 1.17, 1.59, -0.91), Vector3(0.16, 0.16, 0.095), "black")
		_box(self, Vector3(s * 1.17, 1.59, -0.858), Vector3(0.132, 0.125, 0.008), "mirror")
		_bar(self, Vector3(x * 0.98, 1.47, -1.20), Vector3(x * 0.98, 1.99, -0.82), 0.018, 0.019, "black")
		_side_window(s)
	# A lightly tinted windscreen leaves landmarks and cleared tracks visible.
	var windshield := QuadMesh.new()
	windshield.size = Vector2(1.76, 0.749)
	var pane := _piece(self, windshield, Vector3(0, 1.717, -1.046), "windshield")
	pane.rotation.x = 0.629
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x: float in [-0.44, 0.40]:
		_bar(self, Vector3(x - 0.20, 1.45, -1.26), Vector3(x + 0.28, 1.48, -1.238), 0.020, 0.017, "rubber")
	_cab_interior()


func _door_signs() -> void:
	var texture: Texture2D = load("res://ui/art/door_livery.webp")
	var sign := StandardMaterial3D.new()
	sign.albedo_texture = texture
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sign.roughness = .86
	for side:float in [-1.0,1.0]:
		var mesh := QuadMesh.new()
		mesh.size = Vector2(.99, .43)
		var plate := MeshInstance3D.new()
		plate.mesh = mesh
		plate.material_override = sign
		plate.position = Vector3(side*1.002,1.008,-.34)
		plate.rotation.y = side*PI*.5
		add_child(plate)


func _side_window(side: float) -> void:
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := side * 0.91
	var points := [Vector3(x, 1.391, -1.243), Vector3(x, 2.012, -0.801), Vector3(x, 2.012, 0.425), Vector3(x, 1.391, 0.425)]
	var uvs := [Vector2(0, 1), Vector2(0.24, 0), Vector2(1, 0), Vector2(1, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		glass.set_uv(uvs[i])
		glass.set_normal(Vector3.RIGHT * side)
		glass.add_vertex(points[i])
	var side_pane := _piece(self, glass.commit(), Vector3.ZERO, "windshield")
	side_pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _dial_text(text: String, pos: Vector3, size: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 36
	label.pixel_size = size / 36.0
	label.outline_size = 0
	label.modulate = Color("#c2c7a7")
	label.position = pos
	add_child(label)


func _cab_interior() -> void:
	_box(self, Vector3(0, 1.33, -0.19), Vector3(1.78, 0.135, 0.62), "cloth")
	var back := _box(self, Vector3(0, 1.31, 0.18), Vector3(1.78, 0.61, 0.17), "cloth")
	back.rotation.x = 0.10
	for x: float in [-0.51, 0.51]:
		_box(self, Vector3(x, 1.62, 0.198), Vector3(0.32, 0.18, 0.13), "cloth")
	_box(self, Vector3(0, 1.325, -0.986), Vector3(1.81, 0.18, 0.43), "dash")
	_box(self, Vector3(-0.47, 1.441, -0.902), Vector3(0.55, 0.135, 0.245), "black")
	for i in range(3):
		var x := -0.642 + 0.166 * i
		var gauge := _cyl(self, Vector3(x, 1.448, -0.774), 0.055, 0.009, "dial", 16)
		gauge.rotation.x = PI / 2
		var face := _cyl(self, Vector3(x, 1.448, -0.764), 0.047, 0.008, "black", 16)
		face.rotation.x = PI / 2
		for tick in range(11):
			var a := lerpf(deg_to_rad(-123), deg_to_rad(123), tick / 10.0)
			var axis := Vector3(sin(a), cos(a), 0)
			var length := 0.008 if tick % 2 == 0 else 0.004
			var center := Vector3(x, 1.448, -0.758)
			_bar(self, center + axis * (0.043 - length), center + axis * 0.043, 0.0028, 0.0018, "dial")
		_dial_text(["FUEL", "MPH", "TEMP"][i], Vector3(x, 1.428, -0.756), 0.010)
		_dial_text(["E", "0", "C"][i], Vector3(x - 0.030, 1.424, -0.756), 0.008)
		_dial_text(["F", "80", "H"][i], Vector3(x + 0.030, 1.424, -0.756), 0.008)
		var pivot := _joint(self, Vector3(x, 1.448, -0.756))
		_bar(pivot, Vector3.ZERO, Vector3(-0.027, 0.025, 0), 0.005, 0.005, "amber")
		if i == 1:
			_needle = pivot
		else:
			pivot.rotation.z = -1.47 if i == 0 else -0.43
	_wheel = _joint(self, Vector3(-0.475, 1.378, -0.652))
	_wheel.rotation.x = -0.20
	var wheel_mesh := TorusMesh.new()
	wheel_mesh.inner_radius = 0.151
	wheel_mesh.outer_radius = 0.178
	wheel_mesh.rings = 20
	wheel_mesh.ring_segments = 6
	_piece(_wheel, wheel_mesh, Vector3.ZERO, "black").rotation.x = PI / 2
	_box(_wheel, Vector3(0, -0.015, 0), Vector3(0.33, 0.045, 0.033), "black")
	_box(_wheel, Vector3(0, -0.015, 0), Vector3(0.141, 0.079, 0.058), "dash")
	_box(self, Vector3(0.13, 1.286, -0.748), Vector3(0.289, 0.105, 0.108), "black")
	_box(self, Vector3(0.12, 1.30, -0.690), Vector3(0.093, 0.031, 0.009), "dial")
	_cyl(self, Vector3(0.229, 1.29, -0.685), 0.018, 0.022, "steel").rotation.x = PI / 2
	var chart := _joint(self, Vector3(0.54, 1.427, -0.98))
	chart.rotation.y = -0.11
	_box(chart, Vector3.ZERO, Vector3(0.397, 0.017, 0.264), "paper")
	for x: float in [-0.132, -0.043, 0.045, 0.135]:
		_box(chart, Vector3(x, 0.010, 0), Vector3(0.003, 0.002, 0.244), "mapink")
	for z: float in [-0.072, 0.019, 0.092]:
		_box(chart, Vector3(0, 0.011, z), Vector3(0.371, 0.002, 0.004), "mapink")
	_box(self, Vector3(0.12, 1.895, -0.89), Vector3(0.28, 0.087, 0.042), "black")
	_box(self, Vector3(0.12, 1.895, -0.866), Vector3(0.249, 0.062, 0.008), "mirror")


func _bed() -> void:
	_box(self, Vector3(0, 0.94, 1.67), Vector3(1.91, 0.16, 2.13), "oxblood")
	for x: float in [-0.69, -0.46, -0.23, 0.0, 0.23, 0.46, 0.69]:
		_box(self, Vector3(x, 1.036, 1.67), Vector3(0.038, 0.035, 2.02), "rust")
	for s: float in [-1.0, 1.0]:
		_box(self, Vector3(s * 0.922, 1.18, 1.68), Vector3(0.131, 0.526, 2.18), "oxblood")
		_box(self, Vector3(s * 0.916, 1.449, 1.68), Vector3(0.155, 0.041, 2.19), "cap")
		_box(self, Vector3(s * 0.991, 0.96, 1.68), Vector3(0.017, 0.184, 2.17), "cream")
		_box(self, Vector3(s * 0.79, 1.095, 1.54), Vector3(0.29, 0.275, 0.80), "oxblood")
		_box(self, Vector3(s * 0.86, 1.229, 2.784), Vector3(0.162, 0.322, 0.045), "red")
		_box(self, Vector3(s * 0.86, 1.198, 2.812), Vector3(0.149, 0.054, 0.009), "cream")
	_box(self, Vector3(0, 1.21, 0.66), Vector3(1.83, 0.449, 0.105), "oxblood")
	_box(self, Vector3(0, 1.203, 2.725), Vector3(1.83, 0.477, 0.118), "cap")
	_box(self, Vector3(0, 1.12, 2.789), Vector3(1.47, 0.125, 0.012), "cream")
	_box(self, Vector3(0, 1.337, 2.795), Vector3(0.26, 0.058, 0.025), "black")
	_box(self, Vector3(0, 0.844, 2.785), Vector3(2.02, 0.145, 0.19), "rim")
	_box(self, Vector3(0, 0.930, 2.790), Vector3(1.78, 0.027, 0.18), "rubber")
	_box(self, Vector3(0, 0.836, 2.889), Vector3(0.32, 0.102, 0.011), "paper")
	var plate := Label3D.new()
	plate.text = "HV • 204"
	plate.pixel_size = 0.00098
	plate.font_size = 40
	plate.outline_size = 0
	plate.modulate = Color("#283c35")
	plate.position = Vector3(0, 0.837, 2.898)
	add_child(plate)
	# Three sandbags weight the rear axle. The tied seams make them read as sacks.
	for i in range(3):
		var sack := _joint(self, Vector3(-0.41 + i * 0.39, 1.104, 1.41 + (i % 2) * 0.21))
		sack.rotation.y = -0.20 + 0.22 * i
		var shape := SphereMesh.new()
		shape.radius = 0.5
		shape.height = 1
		shape.radial_segments = 10
		shape.rings = 4
		_piece(sack, shape, Vector3.ZERO, "sack").scale = Vector3(0.44, 0.19, 0.70)
		_box(sack, Vector3(0, 0.032, 0.29), Vector3(0.21, 0.070, 0.061), "cloth")
	var toolbox := _box(self, Vector3(-0.40, 1.14, 0.94), Vector3(0.73, 0.22, 0.29), "steel")
	_box(toolbox, Vector3(0, 0.113, 0), Vector3(0.76, 0.038, 0.318), "rim")
	_box(toolbox, Vector3(0, 0.03, 0.148), Vector3(0.12, 0.049, 0.022), "black")
	_shovel = _joint(self, Vector3(0.60, 1.16, 0.81))
	_shovel.rotation = Vector3(-0.06, PI + 0.04, 0)
	_shovel_rest = _shovel.transform
	_bar(_shovel, Vector3.ZERO, Vector3(0, 0, -1.51), 0.041, 0.041, "sack")
	_box(_shovel, Vector3(0, 0, -1.56), Vector3(0.28, 0.025, 0.35), "steel")
	for side in [-1.0, 1.0]:
		_box(_shovel, Vector3(side * 0.132, 0.027, -1.54), Vector3(0.019, 0.065, 0.29), "steel").rotation.z = -side * 0.26
	_box(_shovel, Vector3(0, 0.003, -1.72), Vector3(0.28, 0.02, 0.035), "cut")
	_paint("snow", Color("#ccd3d4"))
	var scoop := SphereMesh.new()
	scoop.radial_segments = 8
	scoop.rings = 3
	_shovel_load = _piece(_shovel, scoop, Vector3(0, 0.035, -1.56), "snow")
	_shovel_load.hide()


# Stow handheld items within reach and heavier loads behind the ballast, clear of the shovel.
func set_cargo(item: String) -> void:
	if is_instance_valid(_cargo):
		_cargo.free()
		_cargo = null
	if item.is_empty():
		return
	_cargo = _joint(self, Vector3(-.23, 1.045, 2.19))
	_cargo.name = "Cargo_" + item
	match item:
		"ticket":
			# A yellow carbon copy, a narrow weight slip and a galvanized spring clip.
			_cargo.position = Vector3(.18, 1.423, -.97)
			_cargo.rotation.y = .18
			_box(_cargo, Vector3.ZERO, Vector3(.221, .012, .31), "cloth")
			_box(_cargo, Vector3(.013, .009, .006), Vector3(.203, .005, .288), "sack")
			_box(_cargo, Vector3(-.014, .015, .018), Vector3(.14, .005, .247), "paper")
			for z: float in [-.05, -.015, .02, .055, .09]:
				_box(_cargo, Vector3(-.014, .019, z), Vector3(.11, .002, .003), "mapink")
			_box(_cargo, Vector3(0, .024, -.108), Vector3(.106, .015, .029), "rim")
		"grit":
			# An upright canvas sack with a gathered neck, cinch and hanging weigh tag.
			var sack := SphereMesh.new()
			sack.radial_segments = 10
			sack.rings = 5
			_piece(_cargo, sack, Vector3(0, .23, 0), "mapink").scale = Vector3(.49, .55, .41)
			_cyl(_cargo, Vector3(0, .46, 0), .074, .12, "cloth", 8)
			_cyl(_cargo, Vector3(0, .467, 0), .079, .023, "paper", 8)
			_bar(_cargo, Vector3(0, .466, .074), Vector3(.045, .392, .164), .01, .01, "cloth")
			_box(_cargo, Vector3(.045, .37, .181), Vector3(.074, .054, .009), "paper").rotation.x = -.58
		"coffee":
			_cargo.position = Vector3(.46, 1.398, -.36)
			_cargo.rotation.y = 1.07
			_cyl(_cargo, Vector3(0, .202, 0), .116, .397, "mapink", 12)
			for band: float in [.097, .291]:
				_cyl(_cargo, Vector3(0, band, 0), .117, .021, "oxblood")
			_cyl(_cargo, Vector3(0, .025, 0), .12, .043, "rim")
			_cyl(_cargo, Vector3(0, .386, 0), .112, .044, "rim")
			_cyl(_cargo, Vector3(0, .44, 0), .08, .072, "steel")
			_box(_cargo, Vector3(-.162, .222, 0), Vector3(.032, .19, .043), "black")
			for level: float in [.132, .312]:
				_box(_cargo, Vector3(-.128, level, 0), Vector3(.08, .031, .047), "black")
		"flares":
			_cargo.rotation.y = -.16
			_box(_cargo, Vector3(0, .12, 0), Vector3(.43, .24, .23), "orange")
			_box(_cargo, Vector3(0, .249, 0), Vector3(.45, .025, .249), "oxblood")
			_box(_cargo, Vector3(0, .318, 0), Vector3(.147, .018, .021), "black")
			for x: float in [-.065, .065]:
				_box(_cargo, Vector3(x, .286, 0), Vector3(.014, .054, .019), "steel")
				_box(_cargo, Vector3(x * 2, .209, .119), Vector3(.022, .071, .012), "rim")
			_cargo_label("FLARES", Vector3(0, .12, .117), .05)
		"mitts":
			_cargo.position = Vector3(.52, 1.398, -.27)
			_cargo.rotation.y = -.19
			_box(_cargo, Vector3(0, .093, 0), Vector3(.278, .185, .155), "sack")
			_box(_cargo, Vector3(0, .164, 0), Vector3(.29, .061, .17), "paper")
			var wool := SphereMesh.new()
			wool.radial_segments = 8
			wool.rings = 4
			for x: float in [-.061, .056]:
				var glove := _joint(_cargo, Vector3(x, .221, 0))
				glove.rotation.z = x * 2.4
				_piece(glove, wool, Vector3.ZERO, "cloth").scale = Vector3(.092, .119, .061)
				_piece(glove, wool, Vector3(x * .6, -.023, .012), "cloth").scale = Vector3(.048, .066, .036)
			_box(_cargo, Vector3(0, .194, 0), Vector3(.286, .011, .018), "mapink")
			_cargo_label("DRY MITTS", Vector3(0, .099, .079), .022)
		_:
			push_error("Unknown truck cargo: " + item)
			_cargo.free()
			_cargo = null


func _cargo_label(words: String, at: Vector3, height: float) -> void:
	var label := Label3D.new()
	label.text = words
	label.font = preload("res://ui/fonts/BarlowCondensed-Bold.ttf")
	label.font_size = 32
	label.pixel_size = height / label.font_size
	label.outline_size = 0
	label.modulate = Color("#312e24")
	label.position = at
	_cargo.add_child(label)


func set_shovel_stroke(camera: Camera3D, phase: float) -> void:
	if phase < 0:
		if _shovel.get_parent() != self:
			_shovel.reparent(self, false)
			_shovel.transform = _shovel_rest
			_shovel_load.hide()
		return
	if _shovel.get_parent() != camera:
		_shovel.reparent(camera, false)
	var scoop := sin(PI * clampf(phase, 0.0, 1.0))
	var toss := sin(PI * smoothstep(0.45, 1.0, phase))
	# Keep the handle on the open side of the driver at either cab door.
	var outside := -1.0 if camera.to_local(global_position).x >= 0.0 else 1.0
	_shovel.position = Vector3(outside * 0.40, -0.32 - 0.18 * scoop, 0.06 - 0.18 * scoop)
	_shovel.rotation = Vector3(-0.07 - 0.34 * scoop + 0.48 * toss, outside * (0.21 - 0.41 * toss), outside * 0.8 * toss)
	var load_fraction := smoothstep(0.26, 0.47, phase) * (1.0 - smoothstep(0.65, 0.83, phase))
	_shovel_load.visible = load_fraction > 0.01
	_shovel_load.scale = Vector3(0.25, 0.095, 0.28) * maxf(load_fraction, 0.01)


func _front_end() -> void:
	_box(self, Vector3(0, 1.18, -2.491), Vector3(1.94, 0.375, 0.091), "rim")
	_box(self, Vector3(0, 1.196, -2.548), Vector3(1.061, 0.256, 0.033), "black")
	for y: float in [1.111, 1.181, 1.251, 1.300]:
		_box(self, Vector3(0, y, -2.573), Vector3(1.023, 0.025, 0.027), "rim")
	_box(self, Vector3(0, 0.891, -2.496), Vector3(1.99, 0.15, 0.201), "rim")
	for s: float in [-1.0, 1.0]:
		_box(self, Vector3(s * 0.740, 1.246, -2.55), Vector3(0.329, 0.175, 0.035), "headlamp")
		_box(self, Vector3(s * 0.74, 1.101, -2.55), Vector3(0.330, 0.063, 0.036), "amber")
		for i in range(3):
			_box(self, Vector3(s * 0.74 - 0.092 + i * 0.09, 1.246, -2.57), Vector3(0.013, 0.165, 0.006), "cream")
		# Contoured fender lip above each tire, leaving the rubber visible below it.
		for axle: float in [FRONT_AXLE_Z, REAR_AXLE_Z]:
			for i in range(6):
				var a := PI * i / 6.0
				var b := PI * (i + 1) / 6.0
				_bar(self, Vector3(s * 0.99, 0.49 + sin(a) * 0.547, axle + cos(a) * 0.547), Vector3(s * 0.99, 0.49 + sin(b) * 0.547, axle + cos(b) * 0.547), 0.086, 0.064, "black")
	_bar(self, Vector3(0.80, 1.44, -1.29), Vector3(0.84, 2.43, -1.26), 0.014, 0.012, "steel")


func _make_plow() -> void:
	_box(self, Vector3(0, 0.77, -2.63), Vector3(1.03, 0.12, 0.49), "black")
	_bar(self, Vector3(0, 0.78, -2.67), Vector3(0, 1.49, -2.77), 0.13, 0.10, "steel")
	_bar(self, Vector3(0, 1.48, -2.77), Vector3(0, 1.49, -3.05), 0.12, 0.09, "black")
	_plow = _joint(self, Vector3(0, 0.40, -3.07))
	_plow.rotation.y = deg_to_rad(-10)
	# The blade is a series of curved moldboard strips with a worn cutting edge.
	var profile: Array[Vector2] = [Vector2(CUTTING_EDGE.y, CUTTING_EDGE.z), Vector2(0.19, -0.091), Vector2(0.42, -0.015), Vector2(0.64, -0.035), Vector2(0.77, -0.128)]
	for i in range(profile.size() - 1):
		var a := Vector3(0, profile[i].x, profile[i].y)
		var b := Vector3(0, profile[i + 1].x, profile[i + 1].y)
		_bar(_plow, a, b, BLADE_WIDTH, 0.06, "orange" if i > 0 else "cut")
	_box(_plow, Vector3(0, 0.773, -0.127), Vector3(2.57, 0.057, 0.078), "rubber")
	for x: float in [-1.17, -0.68, 0.0, 0.68, 1.17]:
		_bar(_plow, Vector3(x, 0.13, -0.08), Vector3(x, 0.66, 0.036), 0.072, 0.077, "rust")
	for s: float in [-1.0, 1.0]:
		_bar(_plow, Vector3(s * 0.54, 0.29, 0.045), Vector3(s * 0.21, 0.36, 0.54), 0.099, 0.114, "steel")
		_bar(_plow, Vector3(s * 1.22, 0.56, -0.004), Vector3(s * 1.28, 1.25, 0.005), 0.023, 0.027, "amber")
		_bar(_plow, Vector3(s * 1.28, 1.245, 0.005), Vector3(s * 1.29, 1.365, 0.007), 0.025, 0.029, "orange")
		_bar(self, Vector3(s * 0.66, 1.04, -2.57), Vector3(s * 0.66, 1.55, -2.74), 0.064, 0.064, "black")
		_box(self, Vector3(s * 0.66, 1.54, -2.76), Vector3(0.277, 0.167, 0.13), "black")
		_box(self, Vector3(s * 0.66, 1.54, -2.833), Vector3(0.241, 0.134, 0.019), "headlamp")


func _lighting() -> void:
	_cyl(self, Vector3(0, 2.153, 0.052), 0.160, 0.085, "black", 16)
	_cyl(self, Vector3(0, 2.243, 0.052), 0.131, 0.139, "amber", 16)
	_cyl(self, Vector3(0, 2.32, 0.052), 0.117, 0.026, "beacon", 16)
	_beacon_rotor = _joint(self, Vector3(0, 2.25, 0.052))
	_box(_beacon_rotor, Vector3(0, 0, 0.126), Vector3(0.096, 0.091, 0.016), "beacon")
	_beacon_light = OmniLight3D.new()
	_beacon_light.position = Vector3(0, 2.42, 0.052)
	_beacon_light.light_color = Color("#ff963b")
	_beacon_light.omni_range = 3.6
	_beacon_light.light_energy = 0.52
	add_child(_beacon_light)
	for x: float in [-0.66, 0.66]:
		var light := SpotLight3D.new()
		light.position = Vector3(x, 1.53, -2.86)
		light.rotation_degrees = Vector3(-7.0, -signf(x)*3.0, 0.0)
		light.light_color = Color("#ffe5bb")
		light.light_energy = 2.65
		light.spot_angle = 29.0
		light.spot_range = 30.0
		light.spot_attenuation = 0.77
		add_child(light)
		_headlights.append(light)
	var volume := MeshInstance3D.new()
	var bounds := BoxMesh.new()
	bounds.size = Vector3(13.6,3.8,20)
	volume.mesh = bounds
	volume.name = "LightInBlowingSnow"
	volume.position = Vector3(0,1.34,-12.86)
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scatter.shader = preload("res://vehicle/headlight_snow.gdshader")
	_scatter.render_priority = -10
	volume.material_override = _scatter
	add_child(volume)


func set_storm_strength(strength:float) -> void:
	_scatter.set_shader_parameter("gust",strength)
	for lamp in _headlights:
		lamp.spot_range = lerpf(31.0,24.0,strength)


func blade_position(across := 0.0) -> Vector3:
	return _plow.to_global(CUTTING_EDGE + Vector3.RIGHT * across)


func _float_plow(lowered: bool, delta: float) -> void:
	# The angled cutting edge can meet the far bank while the front axle is
	# still in the hollow. Its skids ride up immediately and settle on the lift.
	var lift_to_ground := -INF
	for across: float in [-BLADE_WIDTH / 2, 0.0, BLADE_WIDTH / 2]:
		var edge := blade_position(across)
		var height := Roadside.height_at(edge.x, edge.z)
		lift_to_ground = maxf(lift_to_ground, height + CUTTING_EDGE.y - edge.y)
	var ground_stop := _plow.position.y + lift_to_ground / global_basis.y.y
	var target := maxf(ground_stop, -.18) if lowered else .40
	_plow.position.y = maxf(ground_stop, move_toward(_plow.position.y, target, .8 * delta))


func animate(delta: float, speed: float, steering: float, lowered: bool) -> void:
	_lamp_time = fmod(_lamp_time + delta * 5.0, TAU)
	_tire_rotation = fmod(_tire_rotation - speed * delta / 0.46, TAU)
	_beacon_rotor.rotation.y = _lamp_time
	_beacon_light.light_energy = 0.16 + 0.76 * pow(0.5 + 0.5 * cos(_lamp_time), 4)
	_float_plow(lowered, delta)
	for wheel in _wheels:
		wheel.rotation.x = _tire_rotation
	for knuckle in _knuckles:
		knuckle.rotation.y = -steering * 0.49
	_wheel.rotation.z = -steering * 1.55
	_needle.rotation.z = 1.32 - clampf(absf(speed) * 2.237 / 80.0, 0, 1) * 4.29
