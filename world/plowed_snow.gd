extends Node3D

const Route = preload("res://world/route.gd")
const CELL := 0.25
const TILE_METRES := 32.0
const TILE_PIXELS := int(TILE_METRES / CELL)
# Offset the grid so the county road fits within one column of tiles.
const GRID_ORIGIN := Vector2(-16.0, 0.0)
const SNOW_SHADER = preload("res://world/plowed_snow.gdshader")

# Beyond this radius the road disappears into even the lightest storm fog.
const DRAW_RADIUS := 18
const RECENTER_TILES := 2

class Tile:
	var field: Image
	var packed := PackedByteArray()
	var texture: ImageTexture
	var material: ShaderMaterial
	var geometry: Node3D
	var origin: Vector2
	var bounds: Array[Rect2] = []
	var footprints := PackedVector4Array()

	func _init(at: Vector2) -> void:
		origin = at

	func writable_field() -> Image:
		if field == null:
			if packed.is_empty():
				field = Image.create_empty(TILE_PIXELS, TILE_PIXELS, false, Image.FORMAT_RG8)
			else:
				var bytes := packed.decompress(TILE_PIXELS * TILE_PIXELS * 2, FileAccess.COMPRESSION_FASTLZ)
				field = Image.create_from_data(TILE_PIXELS, TILE_PIXELS, false, Image.FORMAT_RG8, bytes)
				packed.clear()
		return field

	func archive() -> void:
		if field != null:
			packed = field.get_data().compress(FileAccess.COMPRESSION_FASTLZ)
			field = null

	func upload() -> void:
		if texture == null:
			texture = ImageTexture.create_from_image(field)
			material.set_shader_parameter("snow_map", texture)
		else:
			texture.update(field)

	func pixel(point: Vector2) -> Vector2i:
		return Vector2i(((point - origin) / CELL).floor())

var tiles: Dictionary[Vector2i, Tile] = {}
var visible_tiles: Dictionary[Vector2i, Tile] = {}
var dirty_tiles: Dictionary[Vector2i, Tile] = {}
var strip_meshes: Dictionary[Vector2, PlaneMesh] = {}
var fresh_snow: ImageTexture
var view_center := Vector2i(1000000, 1000000)
var last_stamp := Vector2(INF, INF)
var last_heading := Vector2.ZERO
var revision := 0
var previous_axle := Vector2(INF, INF)
# A lane caches reachable lateral offsets at each consecutive cleared metre.
# The same measurements apply to east/west and north/south approaches.
class Lane:
	var entrance: Vector2
	var direction: Vector2
	var length: int
	var checked: Array[Array] = []

	func _init(start: Vector2, heading: Vector2, metres: int) -> void:
		entrance = start
		direction = heading
		length = metres

	func invalidate(from: Vector2, to: Vector2) -> void:
		if checked.is_empty():
			return
		var across := direction.orthogonal()
		var low := from - entrance
		var high := to - entrance
		if minf(low.dot(across), high.dot(across)) > 4 or maxf(low.dot(across), high.dot(across)) < -4:
			return
		if maxf(low.dot(direction), high.dot(direction)) < -2:
			return
		var first_changed := floori(minf(low.dot(direction), high.dot(direction)) - 2)
		if first_changed < checked.size():
			checked.resize(maxi(0, first_changed))

var lanes: Dictionary[String, Lane] = {}

func _ready() -> void:
	lanes["beck"] = Lane.new(Vector2(Route.FIRST_SLICE, Route.BECK_Z), Vector2.RIGHT, Route.FULL_LANE)
	for id: String in Route.SITES:
		if id == "beck":
			continue
		var site: Dictionary = Route.SITES[id]
		var heading: Vector2 = site.mouth.direction_to(site.yard)
		lanes[id] = Lane.new(site.mouth + heading * Route.LANE_START, heading, Route.lane_length(id))
	# Index lightweight rectangles for the whole survey. Pixel fields exist only
	# where somebody has driven. Meshes and textures follow the truck.
	var surfaces := Route.surfaces()
	for bounds: Array in surfaces:
		var rect := Rect2(bounds[0], bounds[1] - bounds[0])
		var first := _tile_key(rect.position)
		var last := _tile_key(rect.end)
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var key := Vector2i(x, z)
				if not tiles.has(key):
					tiles[key] = Tile.new(GRID_ORIGIN + Vector2(key) * TILE_METRES)
				tiles[key].bounds.append(rect)
	# Adjacent strips contribute to the feathered shoulder at tile seams.
	for bounds: Array in surfaces:
		var first := _tile_key(bounds[0] - Vector2.ONE * 1.5)
		var last := _tile_key(bounds[1] + Vector2.ONE * 1.5)
		var footprint := Vector4(bounds[0].x, bounds[0].y, bounds[1].x, bounds[1].y)
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var tile: Tile = tiles.get(Vector2i(x,z))
				if tile:
					tile.footprints.append(footprint)
	var blank := Image.create_empty(1, 1, false, Image.FORMAT_RG8)
	fresh_snow = ImageTexture.create_from_image(blank)
	stream_to(Route.HOME_PARK)

func stream_to(point: Vector2) -> void:
	var center := _tile_key(point)
	var movement := (center - view_center).abs()
	if maxi(movement.x, movement.y) <= RECENTER_TILES:
		return
	view_center = center
	for key: Vector2i in visible_tiles.keys():
		var offset := (center - key).abs()
		if maxi(offset.x, offset.y) > DRAW_RADIUS:
			var tile := visible_tiles[key]
			tile.geometry.queue_free()
			tile.geometry = null
			tile.material = null
			tile.texture = null
			tile.archive()
			visible_tiles.erase(key)
	for z in range(center.y - DRAW_RADIUS, center.y + DRAW_RADIUS + 1):
		for x in range(center.x - DRAW_RADIUS, center.x + DRAW_RADIUS + 1):
			var key := Vector2i(x,z)
			if tiles.has(key) and not visible_tiles.has(key):
				var tile := tiles[key]
				_mount(tile)
				visible_tiles[key] = tile

func _mount(tile: Tile) -> void:
	tile.geometry = Node3D.new()
	add_child(tile.geometry)
	tile.material = ShaderMaterial.new()
	tile.material.shader = SNOW_SHADER
	tile.material.set_shader_parameter("origin", tile.origin)
	tile.material.set_shader_parameter("extent", Vector2.ONE * TILE_METRES)
	tile.material.set_shader_parameter("ground_contacts", Route.SNOW_CONTACTS)
	tile.material.set_shader_parameter("footprints", tile.footprints)
	tile.material.set_shader_parameter("strip_count", tile.footprints.size())
	tile.material.set_shader_parameter("snow_map", fresh_snow)
	if tile.field != null or not tile.packed.is_empty():
		tile.writable_field()
		tile.upload()
	var area := Rect2(tile.origin, Vector2.ONE * TILE_METRES)
	for rect in tile.bounds:
		var piece := area.intersection(rect)
		if piece.has_area():
			_strip(piece, tile)

func _tile_key(point: Vector2) -> Vector2i:
	return Vector2i(((point - GRID_ORIGIN) / TILE_METRES).floor())

func _strip(piece: Rect2, tile: Tile) -> void:
	if not strip_meshes.has(piece.size):
		var surface := PlaneMesh.new()
		surface.size = piece.size
		surface.subdivide_width = ceili(piece.size.x / 0.45)
		surface.subdivide_depth = ceili(piece.size.y / 0.45)
		strip_meshes[piece.size] = surface
	var mesh := MeshInstance3D.new()
	mesh.mesh = strip_meshes[piece.size]
	mesh.position = Vector3(piece.get_center().x, 0, piece.get_center().y)
	mesh.material_override = tile.material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tile.geometry.add_child(mesh)

func on_surface(point: Vector2) -> bool:
	var tile: Tile = tiles.get(_tile_key(point))
	if tile:
		for rect: Rect2 in tile.bounds:
			if point.x >= rect.position.x and point.x <= rect.end.x and point.y >= rect.position.y and point.y <= rect.end.y:
				return true
	return false

func clearance(point: Vector2) -> float:
	if not on_surface(point):
		return 0.0
	var tile := tiles[_tile_key(point)]
	if tile.field == null and tile.packed.is_empty():
		return 0.0
	return tile.writable_field().get_pixelv(tile.pixel(point)).r

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
			var previous := tile.writable_field().get_pixelv(pixel)
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
		for lane: Lane in lanes.values():
			lane.invalidate(last_stamp, point)
	last_stamp = point
	last_heading = heading
	return touched

func _process(_delta:float) -> void:
	if dirty_tiles.is_empty():
		return
	for tile: Tile in dirty_tiles.values():
		if tile.field != null:
			if tile.material != null:
				tile.upload()
			else:
				tile.archive()
	dirty_tiles.clear()

# Each meter needs a truck-width opening connected to the opening before it.
func open_length() -> int:
	return lane_opened("beck")

func lane_opened(site_id: String) -> int:
	var lane := lanes[site_id]
	var across := lane.direction.orthogonal()
	var possible: Array = [] if lane.checked.is_empty() else lane.checked.back()
	for metre in range(lane.checked.size(), lane.length):
		var next: Array[int] = []
		var center := lane.entrance + lane.direction * metre
		for lateral in range(-7, 8):
			if metre > 0 and not (possible.has(lateral) or possible.has(lateral-1) or possible.has(lateral+1) or possible.has(lateral-2) or possible.has(lateral+2)):
				continue
			var clear_section := true
			for along in [-.25, 0.0, .25]:
				for offset in [-.625, -.375, -.125, .125, .375, .625]:
					var point := center + lane.direction * float(along) + across * (lateral * CELL + float(offset))
					if clearance(point) < .8:
						clear_section = false
						break
				if not clear_section:
					break
			if clear_section:
				next.append(lateral)
		if next.is_empty():
			break
		lane.checked.append(next)
		possible = next
	return lane.checked.size()

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
			var packed := tile.writable_field().get_pixelv(pixel)
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
