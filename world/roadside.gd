extends StaticBody3D

const Route = preload("res://world/route.gd")
const ROAD_EDGE := 4.3
const OUTER_EDGE := 15.0
# The hand-sampled drainage profile belongs to the original maintained section of Q.
# The outer survey roads cross level, snow-covered fields.
const DITCH_NORTH := -2200.0
const DITCH_SOUTH := 200.0
const ROW_SPACING := 2.0
const CHUNK_LENGTH := 96.0


# Metres relative to the crown of Q. The leeward pockets hold more drifted snow.
static func height_at(x: float, z: float) -> float:
	var distance := absf(x)
	if distance <= ROAD_EDGE or distance >= OUTER_EDGE or z <= DITCH_NORTH or z >= DITCH_SOUTH:
		return 0.0
	var distance_to_turn := absf(z - Route.HOME_Z)
	if x > 0:
		distance_to_turn = minf(absf(z - Route.BECK_Z), absf(z - Route.SITES.quarry.mouth.y))
		distance_to_turn = minf(distance_to_turn, minf(absf(z - Route.ROADS[1].a.y), absf(z - Route.ROADS[3].a.y)))
	var cut := smoothstep(5.0, 10.5, distance_to_turn)
	cut *= smoothstep(0.0, 10.0, minf(z - DITCH_NORTH, DITCH_SOUTH - z))
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
	# Four broad flats surround the closely sampled core. They share exact edges
	# with the ditch mesh; neither ground nor collision needs to grow per metre.
	var fields := Route.COUNTY_BOUNDS.grow(850.0)
	_add_section(PackedFloat32Array([fields.position.x,-OUTER_EDGE]), fields.position.y, fields.end.y, 1, snow)
	_add_section(PackedFloat32Array([OUTER_EDGE,fields.end.x]), fields.position.y, fields.end.y, 1, snow)
	var center := PackedFloat32Array([-OUTER_EDGE,OUTER_EDGE])
	_add_section(center, fields.position.y, DITCH_NORTH, 1, snow)
	_add_section(center, DITCH_SOUTH, fields.end.y, 1, snow)
	var columns := PackedFloat32Array()
	# Both swales need closely spaced samples. The road and distant fields are level.
	for side in [-1, 1]:
		for i in range(23):
			var t: float = i / 22.0 if side > 0 else 1.0 - i / 22.0
			columns.append(side * lerpf(ROAD_EDGE, OUTER_EDGE, t))
	var z := DITCH_NORTH
	while z < DITCH_SOUTH:
		var end := minf(z + CHUNK_LENGTH, DITCH_SOUTH)
		_add_section(columns, z, end, ceili((end - z) / ROW_SPACING), snow)
		z = end


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
