extends Node3D

# R stores blade clearance. G stores the bank deposited at the right of each pass.
const ORIGIN := Vector2(-8, -135)
const EXTENT := Vector2(65, 212)
const CELL := 0.25
const WIDTH := 260
const HEIGHT := 848
const LANE_Z := -38.0
const FIRST_SLICE := 4
const LAST_SLICE := 39
# Both the mesh and per-pixel stamping use the same inclusive float32 corners.
const SURFACES := [
	[Vector2(-4.3,-129), Vector2(4.3,72)],
	[Vector2(4.3,-40.7), Vector2(41,-35.3)],
	[Vector2(41,-41.5), Vector2(51,-34.6)],
	[Vector2(-7.5,37), Vector2(-4.3,42)]
]
var field: Image
var texture: ImageTexture
var cover_material: ShaderMaterial
var dirty := false
var last_stamp := Vector2(INF, INF)
var last_heading := Vector2.ZERO
var revision := 0
var previous_axle := Vector2(INF, INF)

func _ready() -> void:
	field = Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RG8)
	field.fill(Color(0, 0, 0))
	texture = ImageTexture.create_from_image(field)
	cover_material = ShaderMaterial.new()
	cover_material.shader = preload("res://world/plowed_snow.gdshader")
	cover_material.set_shader_parameter("snow_map", texture)
	cover_material.set_shader_parameter("origin", ORIGIN)
	cover_material.set_shader_parameter("extent", EXTENT)
	for bounds: Array in SURFACES:
		_strip(bounds[0],bounds[1])

func _strip(low: Vector2, high: Vector2) -> void:
	var surface := PlaneMesh.new()
	surface.size = high-low
	surface.subdivide_width = ceili(surface.size.x / 0.45)
	surface.subdivide_depth = ceili(surface.size.y / 0.45)
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface
	mesh.position = Vector3((low.x+high.x)*.5,0,(low.y+high.y)*.5)
	mesh.material_override = cover_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _pixel(point: Vector2) -> Vector2i:
	return Vector2i(floori((point.x-ORIGIN.x)/CELL), floori((point.y-ORIGIN.y)/CELL))

func on_surface(point: Vector2) -> bool:
	for bounds: Array in SURFACES:
		var low: Vector2 = bounds[0]
		var high: Vector2 = bounds[1]
		if point.x>=low.x and point.x<=high.x and point.y>=low.y and point.y<=high.y:
			return true
	return false

func clearance(point: Vector2) -> float:
	var pixel := _pixel(point)
	if not on_surface(point):
		return 0.0
	return field.get_pixelv(pixel).r

func stop_pass() -> void:
	last_stamp = Vector2(INF,INF)

func cut(blade: Vector3, forward: Vector3) -> bool:
	var point := Vector2(blade.x, blade.z)
	var heading := Vector2(forward.x,forward.z).normalized()
	if not last_stamp.is_finite() or last_stamp.distance_to(point) > 5:
		last_stamp = point - heading*.18
		last_heading = heading
	var distance := last_stamp.distance_to(point)
	if distance < .12 and heading.dot(last_heading)>.999:
		return false
	var steps := maxi(1,ceili(distance/.18))
	var touched := false
	for i in range(1, steps+1):
		var center := last_stamp.lerp(point,float(i)/steps)
		var right := Vector2(-heading.y,heading.x)
		for stripe in range(-12,16):
			var p := center + right * (float(stripe)*.1)
			if not on_surface(p):
				continue
			var pixel := _pixel(p)
			var previous := field.get_pixelv(pixel)
			if stripe<=12:
				if previous.r < .99 or previous.g>.01:
					field.set_pixelv(pixel,Color(1,0,0))
					touched = true
			elif previous.r < .1 and previous.g < .93:
				field.set_pixelv(pixel,Color(previous.r,.95,0))
				touched = true
	last_stamp = point
	last_heading = heading
	if touched:
		dirty = true
		revision += 1
	return touched

func _process(_delta:float) -> void:
	if dirty:
		texture.update(field)
		dirty = false

# Each meter needs a truck-width opening connected to the opening before it.
func open_length() -> int:
	var possible: Array[int] = []
	for x in range(FIRST_SLICE,LAST_SLICE+1):
		var next: Array[int] = []
		for lateral in range(-7,8):
			var z := LANE_Z + lateral * CELL
			if x != FIRST_SLICE and not (possible.has(lateral) or possible.has(lateral-1) or possible.has(lateral+1) or possible.has(lateral-2) or possible.has(lateral+2)):
				continue
			var clear_section := true
			for sample_x in [x-.25, float(x), x+.25]:
				for offset in [-.625, -.375, -.125, .125, .375, .625]:
					if clearance(Vector2(sample_x,z+offset))<.8:
						clear_section = false
						break
				if not clear_section:
					break
			if clear_section:
				next.append(lateral)
		if next.is_empty():
			return x-FIRST_SLICE
		possible = next
	return LAST_SLICE-FIRST_SLICE+1

func press_tires(axle: Vector3, forward: Vector3) -> void:
	var center := Vector2(axle.x,axle.z)
	if previous_axle.is_finite() and previous_axle.distance_to(center)<.13:
		return
	var heading := Vector2(forward.x,forward.z).normalized()
	var right := Vector2(-heading.y,heading.x)
	var from := previous_axle if previous_axle.is_finite() and previous_axle.distance_to(center)<4.0 else center
	var steps := maxi(1,ceili(from.distance_to(center)/.18))
	for n in range(1,steps+1):
		var position_2d := from.lerp(center,float(n)/steps)
		for offset in [-1.00,-.82,-.72,.72,.82,1.00]:
			var point: Vector2 = position_2d + right*float(offset)
			if not on_surface(point):
				continue
			var pixel := _pixel(point)
			var packed := field.get_pixelv(pixel)
			if packed.r<.3:
				field.set_pixelv(pixel,Color(.3,packed.g*.72,0))
				dirty = true
	previous_axle = center

func create_spray() -> CPUParticles3D:
	var spray := CPUParticles3D.new()
	spray.name = "BladeSpindrift"
	spray.emitting = false
	spray.amount = 45
	spray.lifetime = .5
	spray.local_coords = false
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spray.emission_sphere_radius = .14
	spray.direction = Vector3(.88,.52,.06)
	spray.spread = 33
	spray.gravity = Vector3(0,-4.9,0)
	spray.initial_velocity_min = 1.4
	spray.initial_velocity_max = 3.5
	spray.scale_amount_min = .4
	spray.scale_amount_max = 1.5
	spray.color_ramp = Gradient.new()
	spray.color_ramp.colors = PackedColorArray([Color(.82,.86,.88,.84),Color(.9,.93,.94,.0)])
	var flake := QuadMesh.new()
	flake.size = Vector2(.18,.11)
	var opacity := Gradient.new()
	opacity.offsets = PackedFloat32Array([0,.38,1])
	opacity.colors = PackedColorArray([Color.WHITE,Color(1,1,1,.64),Color(1,1,1,0)])
	var powder := GradientTexture2D.new()
	powder.width = 32
	powder.height = 32
	powder.fill = GradientTexture2D.FILL_RADIAL
	powder.fill_from = Vector2(.5,.5)
	powder.fill_to = Vector2(1,.5)
	powder.gradient = opacity
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = powder
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.material = mat
	spray.mesh = flake
	add_child(spray)
	return spray
