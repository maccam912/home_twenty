extends StaticBody3D

const Route = preload("res://world/route.gd")
const FieldRelief = preload("res://world/field_relief.gd")
# Distance from the plowed edge to the far side of the swale.
const DITCH_REACH := 10.7
const FIELD_STEP := 24.0
const CHUNK_SIZE := 1024.0
# Span of the original utility line, field drifts and grass along County Q.
const CORE_NORTH := -2200.0
const CORE_SOUTH := 200.0

static var _beds: Array[Rect2] = []
static var _road_cells: Dictionary = {}
static var _drive_cells: Dictionary = {}


static func _index_survey() -> void:
	if not _beds.is_empty():
		return
	for road: Dictionary in Route.ROADS:
		var centerline := Rect2(road.a, Vector2.ZERO).expand(road.b)
		var bed := centerline.grow(Route.road_half_width(road.name))
		_beds.append(bed)
		_index_rect(_road_cells, bed, DITCH_REACH)
	var entrances := Route.SITES.values()
	entrances.append({"mouth": Vector2(0, Route.HOME_Z), "yard": Route.HOME_PARK})
	for site: Dictionary in entrances:
		var mouth: Vector2 = site.mouth
		var yard: Vector2 = site.yard
		var side := mouth.direction_to(yard).orthogonal().abs() * 4.8
		var drive := Rect2(mouth.min(yard) - side, (yard - mouth).abs() + side * 2.0)
		_index_rect(_drive_cells, drive, 5.5)


static func _index_rect(cells: Dictionary, rect: Rect2, reach: float) -> void:
	var bounds := rect.grow(reach)
	var start := Vector2i((bounds.position / CHUNK_SIZE).floor())
	var finish := Vector2i((bounds.end / CHUNK_SIZE).floor())
	for z in range(start.y, finish.y + 1):
		for x in range(start.x, finish.x + 1):
			var cell := Vector2i(x,z)
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(rect)


static func height_at(x: float, z: float) -> float:
	_index_survey()
	var p := Vector2(x,z)
	var cell := Vector2i((p / CHUNK_SIZE).floor())
	# Distance to the union of the roadbeds turns the ditch around a bend and
	# leaves every paved arm of a T or four-way junction at road grade.
	var edge_distance := DITCH_REACH
	for bed: Rect2 in _road_cells.get(cell, []):
		edge_distance = minf(edge_distance, p.distance_to(p.clamp(bed.position, bed.end)))
		if edge_distance == 0.0:
			return 0.0
	if edge_distance >= DITCH_REACH:
		return FieldRelief.height_at(x, z)
	var entrance_distance := 5.5
	for drive: Rect2 in _drive_cells.get(cell, []):
		entrance_distance = minf(entrance_distance, p.distance_to(p.clamp(drive.position, drive.end)))
		if entrance_distance == 0.0:
			return 0.0
	# The windrow on the verge and the sheltered, snow-filled trough follow
	# world coordinates so neighboring stretches meet at the same elevation.
	var station := (z + x * .87) * .01
	var spill := .52 * sin(station * 7.1) + .24 * sin(station * 18.3 + sin(station * 3.2))
	var toe := 4.4 + .62 * sin(station * 2.1) + spill * .6
	var outer := 9.3 + .75 * sin(station * 1.8)
	var hollow := smoothstep(.95 + spill, toe, edge_distance) * (1.0 - smoothstep(toe, outer, edge_distance))
	var lee := smoothstep(.35, .94, .5 + .5 * sin(station * 2.8 + 1.4 * sin(station * .91)))
	var depth := .95 + .12 * sin(station * 1.35) - .46 * lee
	var lip_width := .96 + .30 * sin(station * 13.9)
	var scallop := smoothstep(-.85, .44, sin(station * 14.8 + sin(station * 5.7)))
	var lip := (1.0 - smoothstep(0.0, lip_width, absf(edge_distance - 1.07 - spill))) * (.025 + scallop * (.10 + .20 * lee))
	lip *= smoothstep(0.0, .45, edge_distance)
	return smoothstep(0.0, 5.5, entrance_distance) * (lip - hollow * depth)


func build(snow: Material) -> void:
	name = "SnowGround"
	collision_layer = 2
	collision_mask = 0
	_index_survey()
	var fields := Route.COUNTY_BOUNDS.grow(850.0)
	var xs := _section_edges(fields, Vector2.AXIS_X)
	var zs := _section_edges(fields, Vector2.AXIS_Y)
	for zi in range(zs.size() - 1):
		for xi in range(xs.size() - 1):
			var bounds := Rect2(xs[xi], zs[zi], xs[xi+1] - xs[xi], zs[zi+1] - zs[zi])
			var spacing := Vector2.ONE * FIELD_STEP
			for bed in _beds:
				if not bounds.intersects(bed.grow(DITCH_REACH)):
					continue
				var step := Vector2(.95, 4) if bed.size.y > bed.size.x else Vector2(4, .95)
				spacing = spacing.min(step)
			_add_section(bounds, spacing, snow)


# Partition at the outside of every ditch. Only the road corridors need
# closely spaced cross sections. The large field patches share their edges.
func _section_edges(fields: Rect2, axis: int) -> PackedFloat32Array:
	var cuts := {fields.position[axis]: true, fields.end[axis]: true}
	for bed in _beds:
		var verge := bed.grow(DITCH_REACH)
		cuts[verge.position[axis]] = true
		cuts[verge.end[axis]] = true
	for tile in range(ceili(fields.position[axis] / CHUNK_SIZE), ceili(fields.end[axis] / CHUNK_SIZE)):
		cuts[tile * CHUNK_SIZE] = true
	var edges := PackedFloat32Array(cuts.keys())
	edges.sort()
	return edges


func _samples(start: float, end: float, step: float) -> PackedFloat32Array:
	var count := ceili((end - start) / step)
	var values := PackedFloat32Array()
	values.resize(count + 1)
	for i in range(count + 1):
		values[i] = lerpf(start, end, float(i) / count)
	return values


func _add_section(bounds: Rect2, spacing: Vector2, snow: Material) -> void:
	var xs := _samples(bounds.position.x, bounds.end.x, spacing.x)
	var zs := _samples(bounds.position.y, bounds.end.y, spacing.y)
	var vertices := PackedVector3Array()
	var heights := PackedFloat32Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var width := xs.size()
	var count := width * zs.size()
	vertices.resize(count)
	heights.resize(count)
	normals.resize(count)
	colors.resize(count)
	indices.resize((width - 1) * (zs.size() - 1) * 6)
	var in_corridor := spacing.x < FIELD_STEP or spacing.y < FIELD_STEP
	for row in zs.size():
		for column in width:
			var idx := row * width + column
			var h := height_at(xs[column], zs[row])
			vertices[idx] = Vector3(xs[column], h, zs[row])
			heights[idx] = h
			var sheltered := smoothstep(.04, 1.12, -h) if in_corridor else 0.0
			colors[idx] = Color(1.0 - sheltered * .24, 1.0 - sheltered * .18, 1.0 - sheltered * .12)
	for row in zs.size():
		for column in width:
			var idx := row * width + column
			var dx := vertices[row * width + mini(column + 1, width - 1)] - vertices[row * width + maxi(column - 1, 0)]
			var dz := vertices[mini(row + 1, zs.size() - 1) * width + column] - vertices[maxi(row - 1, 0) * width + column]
			normals[idx] = dz.cross(dx).normalized()
			if row < zs.size() - 1 and column < width - 1:
				var face := (row * (width - 1) + column) * 6
				indices[face] = idx
				indices[face + 1] = idx + 1
				indices[face + 2] = idx + width
				indices[face + 3] = idx + 1
				indices[face + 4] = idx + width + 1
				indices[face + 5] = idx + width
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var section := MeshInstance3D.new()
	section.mesh = mesh
	section.material_override = snow
	section.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(section)
	# A heightfield stores one elevation per sample and stays resident across
	# the county. The rendered grid and the collider share the same spacing.
	var shape := HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = zs.size()
	shape.map_data = heights
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(bounds.get_center().x, 0, bounds.get_center().y)
	collider.scale = Vector3(bounds.size.x / (width - 1), 1.0, bounds.size.y / (zs.size() - 1))
	add_child(collider)
