extends Node3D

const Roadside = preload("res://world/roadside.gd")
const WAGON = preload("res://world/props/ditch_wagon.glb")
const WALKER = preload("res://world/props/field_walker.glb")
const CELLAR = preload("res://world/props/bare_foundation.glb")
const FIGURE_SHADER = preload("res://world/figure_in_snow.gdshader")
const WAGON_AT := Vector2(8.4, -286.0)
const FIRST_PRINT := Vector2(153.0, -725.2)
const LAST_PRINT := Vector2(162.3, -736.3)
const CELLAR_AT := Vector2(20.0, 389.0)
const WALK_SPEED := 1.04
const STRIDE := .57

var investigated: Dictionary = {}
var wagon_window: Vector2
var lamp_stoop: Vector2
var tail_lights := Node3D.new()
var figure: Node3D
var limbs: Array[MeshInstance3D] = []
var prints := MultiMeshInstance3D.new()
var lamp := Node3D.new()
var walk_metres := 0.0
var walked := false
var walk_finished := false
var lamp_phase := 0.6


func _ready() -> void:
	_build_wagon()
	_build_walker()
	_build_cellar()


func _ground(at: Vector2) -> Vector3:
	return Vector3(at.x, Roadside.height_at(at.x, at.y), at.y)


func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


func _material(color: Color, energy := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if energy > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
	return mat


func _mesh(parent: Node3D, shape: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = shape
	part.position = at
	part.material_override = mat
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


func _collider(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = at
	body.add_child(shape)
	parent.add_child(body)


func _glow(parent: Node3D, at: Vector3, color: Color, reach: float, size: Vector2, energy: float) -> void:
	var spill := OmniLight3D.new()
	spill.position = at
	spill.omni_range = reach
	spill.light_color = color
	spill.light_energy = energy
	parent.add_child(spill)
	var bloom := ShaderMaterial.new()
	bloom.shader = preload("res://world/lamp_glow.gdshader")
	bloom.set_shader_parameter("lamp_color", color)
	bloom.set_shader_parameter("strength", energy)
	var quad := QuadMesh.new()
	quad.size = size
	_mesh(parent, quad, at, bloom)


func _build_wagon() -> void:
	var car := WAGON.instantiate() as Node3D
	car.position = _ground(WAGON_AT) - Vector3.UP * .10
	car.rotation_degrees = Vector3(-10, -43, -6)
	add_child(car)
	_wheel_ruts(car)
	_collider(car, Vector3(0, .87, -.02), Vector3(1.81, 1.36, 4.78))
	wagon_window = _flat(car.to_global(Vector3(-.99, .88, -.34)))
	car.add_child(tail_lights)
	var lens := BoxMesh.new()
	lens.size = Vector3(.39, .125, .014)
	var ruby := _material(Color("#fa2120"), 1.65)
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * .654, .885, 2.466)
		_mesh(tail_lights, lens, at, ruby)
		_glow(tail_lights, at + Vector3.BACK * .045, Color("#e82828"), 2.2, Vector2(2.35, 1.83), 1.16)


func _wheel_ruts(car: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var back := _flat(car.basis.z).normalized()
	var side := back.orthogonal()
	var vertex_count := 0
	for wheel: float in [-.88, .88]:
		var rear := _flat(car.to_global(Vector3(wheel, 0, 1.55)))
		# Trail out at the lip where the car first left the public road.
		var length := (4.65 - rear.x) / back.x
		for i in 16:
			var t := i / 15.0
			var center := rear + back * length * t
			var span := lerpf(.15, .07, t * t)
			for k in 3:
				var edge := float(k - 1)
				var xy := center + side * (edge * span + sin(t * 4) * .10)
				surface.set_color(Color("#c3c9ca") if k != 1 else Color("#87969c"))
				surface.add_vertex(_ground(xy) + Vector3.UP * (.025 + absf(edge) * .065 * (1.0 - t)))
				vertex_count += 1
			if i > 0:
				var first := vertex_count - 6
				for k in 2:
					for j: int in [0, 3, 1, 1, 3, 4]:
						surface.add_index(first + k + j)
	surface.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(self, surface.commit(), Vector3.ZERO, mat)


func _build_walker() -> void:
	figure = WALKER.instantiate() as Node3D
	add_child(figure)
	var towards := LAST_PRINT - FIRST_PRINT
	figure.rotation.y = atan2(-towards.x, -towards.y)
	figure.position = _ground(FIRST_PRINT)
	for part_name in ["WalkerLegLeft", "WalkerLegRight", "WalkerArmLeft", "WalkerArmRight", "WalkerTorso"]:
		var part := figure.find_child(part_name, true, false) as MeshInstance3D
		part.visibility_range_end = 150
		limbs.append(part)
		for i in part.mesh.get_surface_count():
			var wool := ShaderMaterial.new()
			wool.shader = FIGURE_SHADER
			var original := part.mesh.surface_get_material(i) as BaseMaterial3D
			wool.set_shader_parameter("wool", original.albedo_color)
			part.set_surface_override_material(i, wool)
	# A shallow, blue-grey heel and toe in the snow for each step across the grade.
	add_child(prints)
	var trail := MultiMesh.new()
	trail.transform_format = MultiMesh.TRANSFORM_3D
	trail.mesh = _bootprint()
	trail.instance_count = floori(FIRST_PRINT.distance_to(LAST_PRINT) / STRIDE)
	var forward := towards.normalized()
	for i in trail.instance_count:
		var direction := forward.rotated(.081 if i % 2 else -.095)
		var xy := FIRST_PRINT + forward * (i * STRIDE) + forward.orthogonal() * (.105 if i % 2 else -.105)
		var at := _ground(xy)
		# Conform each shallow print to the transverse ditch slope.
		var dx := _ground(xy + Vector2(.2,0)).y - _ground(xy - Vector2(.2,0)).y
		var dz := _ground(xy + Vector2(0,.2)).y - _ground(xy - Vector2(0,.2)).y
		var up := Vector3(-dx, .4, -dz).normalized()
		var axes := Basis.looking_at(Vector3(direction.x, 0, direction.y).slide(up).normalized(), up)
		trail.set_instance_transform(i, Transform3D(axes, at + up * .035))
	trail.visible_instance_count = 0
	prints.multimesh = trail


func _bootprint() -> Mesh:
	var sole := SurfaceTool.new()
	sole.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := _material(Color("#83919a"))
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sole.set_material(mat)
	# Packed snow shows the worn toe, then two halves of the cracked heel.
	for outline: PackedVector2Array in [
		PackedVector2Array([Vector2(-.051,-.085), Vector2(-.052,-.139), Vector2(-.033,-.168), Vector2(.032,-.170), Vector2(.061,-.132), Vector2(.067,-.047), Vector2(.039,.022), Vector2(-.055,.010)]),
		PackedVector2Array([Vector2(-.046,.040), Vector2(-.007,.041), Vector2(-.015,.143), Vector2(-.044,.133), Vector2(-.053,.082)]),
		PackedVector2Array([Vector2(.007,.042), Vector2(.048,.05), Vector2(.050,.116), Vector2(.034,.145), Vector2(-.003,.147)])]:
		for idx in Geometry2D.triangulate_polygon(outline):
			sole.set_normal(Vector3.UP)
			sole.add_vertex(Vector3(outline[idx].x, 0, outline[idx].y))
	return sole.commit()


func _build_cellar() -> void:
	var cellar := CELLAR.instantiate() as Node3D
	cellar.position = _ground(CELLAR_AT)
	cellar.rotation.y = -PI / 2
	add_child(cellar)
	for side: float in [-1.0, 1.0]:
		_collider(cellar, Vector3(side * 3.5, .23, 0), Vector3(.50, .55, 5.22))
		_collider(cellar, Vector3(side * 2.15, .23, 2.6), Vector3(2.69, .55, .47))
		_collider(cellar, Vector3(side * .765, 1.5, 2.4), Vector3(.13, 2.30, .17))
	_collider(cellar, Vector3(0, .23, -2.55), Vector3(6.95, .55, .47))
	lamp.position = Vector3(-.586, 2.96, 3.11)
	cellar.add_child(lamp)
	lamp_stoop = _flat(lamp.global_position)
	var cable := CylinderMesh.new()
	cable.height = .59
	cable.top_radius = .011
	cable.bottom_radius = .011
	_mesh(lamp, cable, Vector3.DOWN * .295, _material(Color("#403f3d")))
	var shade := CylinderMesh.new()
	shade.height = .135
	shade.top_radius = .075
	shade.bottom_radius = .235
	_mesh(lamp, shade, Vector3.DOWN * .63, _material(Color("#716959")))
	var bulb := SphereMesh.new()
	bulb.radius = .059
	bulb.height = .139
	_mesh(lamp, bulb, Vector3.DOWN * .726, _material(Color("#ffd398"), 3.5))
	_glow(lamp, Vector3.DOWN * .76, Color("#ffac66"), 6.3, Vector2(2.9, 3.3), 1.6)


func update_sightings(delta: float, position_xz: Vector2) -> void:
	if position_xz.distance_squared_to(CELLAR_AT) < 130.0 * 130.0:
		if investigated.has("lamp"):
			lamp.rotation.x = lerp_angle(lamp.rotation.x, .44, minf(delta * 5.0, 1.0))
		else:
			lamp_phase = fmod(lamp_phase + delta * 2.12, TAU * 4)
			lamp.rotation.x = sin(lamp_phase) * .34 + sin(lamp_phase * .75) * .085
	var distance := position_xz.distance_squared_to(FIRST_PRINT)
	if distance > 150.0 * 150.0 and not investigated.has("prints") and walked:
		walked = false
		walk_finished = false
		walk_metres = 0
		figure.position = _ground(FIRST_PRINT)
		for part in limbs:
			part.rotation.x = 0
			part.set_instance_shader_parameter("obscured", 0.0)
		figure.visible = true
		prints.multimesh.visible_instance_count = 0
	if walk_finished or (not walked and distance > 42.0 * 42.0):
		return
	walked = true
	figure.visible = true
	var length := FIRST_PRINT.distance_to(LAST_PRINT)
	walk_metres = minf(walk_metres + delta * WALK_SPEED, length)
	figure.position = _ground(FIRST_PRINT.lerp(LAST_PRINT, walk_metres / length))
	var phase := walk_metres * PI / STRIDE
	figure.position.y += .021 * absf(cos(phase))
	for i in 4:
		var swing := sin(phase) * (.30 if i < 2 else -.19)
		limbs[i].rotation.x = swing if i % 2 else -swing
	for part in limbs:
		part.set_instance_shader_parameter("obscured", smoothstep(length - 3.8, length, walk_metres))
	prints.multimesh.visible_instance_count = mini(prints.multimesh.instance_count, 1 + floori(walk_metres / STRIDE))
	if walk_metres >= length:
		figure.visible = false
		walk_finished = true


func _by_prints(point: Vector2) -> bool:
	if not walked:
		return false
	var last := FIRST_PRINT.move_toward(LAST_PRINT, maxf(.1, walk_metres))
	return Geometry2D.get_closest_point_to_segment(point, FIRST_PRINT, last).distance_squared_to(point) <= 2.7 * 2.7


func action_at(point: Vector2) -> String:
	if not investigated.has("wagon") and point.distance_squared_to(wagon_window) <= 3.1 * 3.1:
		return "Tap the glass"
	if not investigated.has("prints") and _by_prints(point):
		return "Study tracks"
	if not investigated.has("lamp") and point.distance_squared_to(lamp_stoop) <= 3.1 * 3.1:
		return "Still the lamp"
	return ""


func investigate_at(point: Vector2) -> String:
	match action_at(point):
		"Tap the glass":
			investigated.wagon = true
			tail_lights.visible = false
			return "Nobody in either seat. You tap once on the cold glass. Both tail lights go out."
		"Study tracks":
			investigated.prints = true
			return "A work boot with a split heel. Each print points across the field. There isn't a single step coming back."
		"Still the lamp":
			investigated.lamp = true
			return "You catch the shade and let go. It stays tipped on its cord. Snow keeps blowing through the doorway."
	return ""
