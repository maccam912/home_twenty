extends StaticBody3D

const Route = preload("res://world/route.gd")
const ROAD_EDGE := 4.3
const OUTER_EDGE := 15.0
const FIELD_EDGE := 1700.0
const ROW_SPACING := 2.0
const CHUNK_LENGTH := 96.0


# Metres relative to the crown of Q. The leeward pockets hold more drifted snow.
static func height_at(x: float, z: float) -> float:
	var distance := absf(x)
	if distance <= ROAD_EDGE or distance >= OUTER_EDGE or z <= Route.ROAD_NORTH_Z or z >= Route.ROAD_SOUTH_Z:
		return 0.0
	var entrance := Route.HOME_Z if x < 0 else Route.BECK_Z
	var cut := smoothstep(5.0, 10.5, absf(z - entrance))
	cut *= smoothstep(0.0, 10.0, minf(z - Route.ROAD_NORTH_Z, Route.ROAD_SOUTH_Z - z))
	var station := z * .01 + (19.0 if x < 0 else 0.0)
	var spill := .52 * sin(station * 7.1) + .24 * sin(station * 18.3 + sin(station * 3.2))
	var toe := 8.7 + .62 * sin(station * 2.1) + spill * .6
	var outer := 13.6 + .75 * sin(station * 1.8)
	var hollow := smoothstep(5.25 + spill, toe, distance) * (1.0 - smoothstep(toe, outer, distance))
	var lee := smoothstep(.35, .94, .5 + .5 * sin(station * 2.8 + 1.4 * sin(station * .91)))
	var depth := .95 + .12 * sin(station * 1.35) - .46 * lee
	# The low plow windrow sits at the break of slope, before the ground falls away.
	var lip_x := 5.37 + spill
	var lip_width := .96 + .30 * sin(station * 13.9)
	var scallop := smoothstep(-.85, .44, sin(station * 14.8 + sin(station * 5.7)))
	var lip := (1.0 - smoothstep(.0, lip_width, absf(distance - lip_x))) * (.025 + scallop * (.10 + .20 * lee))
	lip *= smoothstep(ROAD_EDGE, ROAD_EDGE + .45, distance)
	return cut * (lip - hollow * depth)


func build(snow: Material) -> void:
	name = "SnowGround"
	collision_layer = 2
	collision_mask = 0
	var columns := PackedFloat32Array([-FIELD_EDGE])
	# Both swales need closely spaced samples. The road and distant fields are level.
	for side in [-1, 1]:
		for i in range(23):
			var t: float = i / 22.0 if side > 0 else 1.0 - i / 22.0
			columns.append(side * lerpf(ROAD_EDGE, OUTER_EDGE, t))
	columns.append(FIELD_EDGE)
	var z := Route.ROAD_NORTH_Z
	_add_section(columns, z - 1200.0, z, 1, snow)
	while z < Route.ROAD_SOUTH_Z:
		var end := minf(z + CHUNK_LENGTH, Route.ROAD_SOUTH_Z)
		_add_section(columns, z, end, ceili((end - z) / ROW_SPACING), snow)
		z = end
	_add_section(columns, z, z + 1200.0, 1, snow)


func _add_section(columns: PackedFloat32Array, start: float, end: float, rows: int, snow: Material) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for row in range(rows + 1):
		var z := lerpf(start, end, float(row) / rows)
		for x in columns:
			var h := height_at(x, z)
			var dx := height_at(x + .15, z) - height_at(x - .15, z)
			var dz := height_at(x, z + .15) - height_at(x, z - .15)
			vertices.append(Vector3(x, h, z))
			normals.append(Vector3(-dx, .30, -dz).normalized())
			# The trough sees less open sky than the top of the shoulder.
			var sheltered := smoothstep(.04, 1.12, -h)
			colors.append(Color(1.0 - sheltered * .21, 1.0 - sheltered * .15, 1.0 - sheltered * .095))
	for row in rows:
		for column in range(columns.size() - 1):
			var a := row * columns.size() + column
			var b := a + columns.size()
			indices.append_array(PackedInt32Array([a, a+1, b, a+1, b+1, b]))
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
	var collider := CollisionShape3D.new()
	collider.shape = mesh.create_trimesh_shape()
	add_child(collider)
