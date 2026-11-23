extends Node3D

## A grader or loader can leave fresh snow on a working apron. This thin
## second layer keeps the old lane cuts and tire tracks underneath intact.
const RIDGE_SHADER := preload("res://world/loading_bay.gdshader")
const CELL := 0.125
const WIDTH := 3.5
const HALF_BLADE := 1.2
var length_metres := 0
var revision := 0
var _mask: Image
var _texture: ImageTexture
var _material := ShaderMaterial.new()
var _needs_upload := false
var _center := Vector2.ZERO
var _within_reach := 0.0

func setup(path: PackedVector2Array) -> void:
	var along := path[0].direction_to(path[1])
	length_metres = roundi(path[0].distance_to(path[1]))
	_center = (path[0] + path[1]) * .5
	_within_reach = pow(length_metres * .5 + WIDTH + HALF_BLADE, 2)
	position = Vector3(_center.x, 0, _center.y)
	rotation.y = atan2(along.x, along.y)
	_mask = Image.create_empty(roundi(WIDTH / CELL), roundi(length_metres / CELL), false, Image.FORMAT_L8)
	_texture = ImageTexture.create_from_image(_mask)
	_material.shader = RIDGE_SHADER
	_material.set_shader_parameter("dimensions", Vector2(WIDTH, length_metres))
	_material.set_shader_parameter("deposit_mask", _texture)
	var surface := PlaneMesh.new()
	surface.size = Vector2(WIDTH, length_metres)
	surface.subdivide_width = _mask.get_width() - 1
	surface.subdivide_depth = _mask.get_height() - 1
	var drift := MeshInstance3D.new()
	drift.mesh = surface
	drift.material_override = _material
	drift.extra_cull_margin = 1
	drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drift)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#bd6b37")
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color("#f1e4bd")
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			var at := Vector3(side * (WIDTH * .5 + .4), 0, end * length_metres * .5)
			_stake_piece(at + Vector3.UP * .49, .98, paint)
			_stake_piece(at + Vector3.UP * .86, .09, tape)

func _stake_piece(at: Vector3, height: float, material: Material) -> void:
	var post := BoxMesh.new()
	post.size = Vector3(.065, height, .065)
	if height < .1:
		post.size += Vector3(.012, 0, .012)
	var mesh := MeshInstance3D.new()
	mesh.mesh = post
	mesh.position = at
	mesh.material_override = material
	add_child(mesh)

func deposit(variation: int) -> void:
	_mask.fill(Color.WHITE)
	_texture.update(_mask)
	_material.set_shader_parameter("variation", fmod(variation * 1.73, TAU))
	_needs_upload = false
	revision += 1

func cut(blade: Vector3, heading: Vector3) -> bool:
	if Vector2(blade.x, blade.z).distance_squared_to(_center) > _within_reach:
		return false
	var tip := to_local(blade)
	var forward := global_basis.inverse() * heading
	var axis := Vector2(forward.x, forward.z).normalized()
	var side := axis.orthogonal()
	var grid := Vector2(WIDTH, length_metres) * .5
	# Clear only covered texels, including a little depth behind the cutting edge.
	var center := Vector2(tip.x, tip.z) + grid
	var radius := side.abs() * HALF_BLADE + axis.abs() * .22
	var first := Vector2i(((center - radius) / CELL).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((center + radius) / CELL).floor()).min(_mask.get_size() - Vector2i.ONE)
	var changed := false
	for row in range(first.y, last.y + 1):
		for column in range(first.x, last.x + 1):
			var offset := (Vector2(column + .5, row + .5) * CELL) - center
			if absf(offset.dot(side)) > HALF_BLADE or absf(offset.dot(axis)) > .22:
				continue
			if _mask.get_pixel(column, row).r > .5:
				_mask.set_pixel(column, row, Color.BLACK)
				changed = true
	if changed:
		revision += 1
		_needs_upload = true
	return changed

func open_metres() -> int:
	# A metre is useful when there is a continuous truck-width path into it.
	# Carry all reachable centers forward so overlapping passes can join.
	var reachable: Array[int] = []
	var half_width := 5 # ten texels across = 1.25 metres
	for row in _mask.get_height():
		var next: Array[int] = []
		for center in range(half_width, _mask.get_width() - half_width + 1):
			if row > 0 and not (reachable.has(center) or reachable.has(center - 1) or reachable.has(center + 1)):
				continue
			var clear := true
			for x in range(center - half_width, center + half_width):
				if _mask.get_pixel(x, row).r > .5:
					clear = false
					break
			if clear:
				next.append(center)
		if next.is_empty():
			return floori(row * CELL)
		reachable = next
	return length_metres

func _process(_delta: float) -> void:
	if _needs_upload:
		_texture.update(_mask)
		_needs_upload = false
