extends Node3D

const Route = preload("res://world/route.gd")
const CELL := 0.25
const TILE_METRES := 32.0
const TILE_PIXELS := int(TILE_METRES / CELL)
# Offset the grid so the county road fits within one column of tiles.
const GRID_ORIGIN := Vector2(-16.0, 0.0)
const SNOW_SHADER = preload("res://world/plowed_snow.gdshader")

class Tile:
	var field := Image.create_empty(TILE_PIXELS, TILE_PIXELS, false, Image.FORMAT_RG8)
	var texture := ImageTexture.create_from_image(field)
	var material := ShaderMaterial.new()
	var origin: Vector2

	func _init(at: Vector2, footprints: PackedVector4Array) -> void:
		origin = at
		material.shader = SNOW_SHADER
		material.set_shader_parameter("snow_map", texture)
		material.set_shader_parameter("origin", at)
		material.set_shader_parameter("extent", Vector2.ONE * TILE_METRES)
		material.set_shader_parameter("footprints", footprints)
		material.set_shader_parameter("ground_contacts", Route.SNOW_CONTACTS)

	func pixel(point: Vector2) -> Vector2i:
		return Vector2i(((point - origin) / CELL).floor())

var tiles: Dictionary[Vector2i, Tile] = {}
var dirty_tiles: Dictionary[Vector2i, Tile] = {}
var last_stamp := Vector2(INF, INF)
var last_heading := Vector2.ZERO
var revision := 0
var previous_axle := Vector2(INF, INF)
# Reachable lateral offsets at each consecutive cleared metre of the Beck lane.
var connected_slices: Array[Array] = []

func _ready() -> void:
	var footprints := PackedVector4Array()
	for bounds: Array in Route.SURFACES:
		footprints.append(Vector4(bounds[0].x,bounds[0].y,bounds[1].x,bounds[1].y))
	# Each texture covers a small piece of the route. Only driven tiles upload.
	for bounds: Array in Route.SURFACES:
		var low: Vector2 = bounds[0]
		var high: Vector2 = bounds[1]
		var first := _tile_key(low)
		var last := _tile_key(high)
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var key := Vector2i(x, z)
				var origin := GRID_ORIGIN + Vector2(key) * TILE_METRES
				if not tiles.has(key):
					tiles[key] = Tile.new(origin, footprints)
				var start := low.max(origin)
				var end := high.min(origin + Vector2.ONE * TILE_METRES)
				if start.x < end.x and start.y < end.y:
					_strip(start, end, tiles[key].material)

func _tile_key(point: Vector2) -> Vector2i:
	return Vector2i(((point - GRID_ORIGIN) / TILE_METRES).floor())

func _strip(low: Vector2, high: Vector2, material: ShaderMaterial) -> void:
	var surface := PlaneMesh.new()
	surface.size = high-low
	surface.subdivide_width = ceili(surface.size.x / 0.45)
	surface.subdivide_depth = ceili(surface.size.y / 0.45)
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface
	mesh.position = Vector3((low.x+high.x)*.5,0,(low.y+high.y)*.5)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func on_surface(point: Vector2) -> bool:
	for bounds: Array in Route.SURFACES:
		var low: Vector2 = bounds[0]
		var high: Vector2 = bounds[1]
		if point.x>=low.x and point.x<=high.x and point.y>=low.y and point.y<=high.y:
			return true
	return false

func clearance(point: Vector2) -> float:
	if not on_surface(point):
		return 0.0
	var tile := tiles[_tile_key(point)]
	return tile.field.get_pixelv(tile.pixel(point)).r

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
			var key := _tile_key(p)
			var tile := tiles[key]
			var pixel := tile.pixel(p)
			var previous := tile.field.get_pixelv(pixel)
			if stripe<=12:
				if previous.r < .99 or previous.g>.01:
					tile.field.set_pixelv(pixel,Color(1,0,0))
					dirty_tiles[key] = tile
					touched = true
			elif previous.r < .1 and previous.g < .93:
				tile.field.set_pixelv(pixel,Color(previous.r,.95,0))
				dirty_tiles[key] = tile
				touched = true
	if touched:
		revision += 1
		# Include blade width, the sampled quarter-metre and the texel footprint.
		var stamped := Rect2(last_stamp, Vector2.ZERO).expand(point).grow(2.0)
		var lane := Rect2(Route.FIRST_SLICE, Route.BECK_Z - 2.5, Route.FULL_LANE, 5.0)
		if stamped.intersects(lane):
			var first_changed := floori(stamped.position.x) - Route.FIRST_SLICE
			connected_slices.resize(clampi(first_changed, 0, connected_slices.size()))
	last_stamp = point
	last_heading = heading
	return touched

func _process(_delta:float) -> void:
	if dirty_tiles.is_empty():
		return
	for tile: Tile in dirty_tiles.values():
		tile.texture.update(tile.field)
	dirty_tiles.clear()

# Each meter needs a truck-width opening connected to the opening before it.
func open_length() -> int:
	var possible: Array = [] if connected_slices.is_empty() else connected_slices.back()
	for x in range(Route.FIRST_SLICE + connected_slices.size(), Route.LAST_SLICE + 1):
		var next: Array[int] = []
		for lateral in range(-7,8):
			var z := Route.BECK_Z + lateral * CELL
			if x != Route.FIRST_SLICE and not (possible.has(lateral) or possible.has(lateral-1) or possible.has(lateral+1) or possible.has(lateral-2) or possible.has(lateral+2)):
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
			break
		connected_slices.append(next)
		possible = next
	return connected_slices.size()

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
			var key := _tile_key(point)
			var tile := tiles[key]
			var pixel := tile.pixel(point)
			var packed := tile.field.get_pixelv(pixel)
			if packed.r<.3:
				tile.field.set_pixelv(pixel,Color(.3,packed.g*.72,0))
				dirty_tiles[key] = tile
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
