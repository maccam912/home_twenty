extends RefCounted

const Route = preload("res://world/route.gd")

var rng := RandomNumberGenerator.new()
var clearings := PackedVector2Array()


func plant(town) -> void:
	rng.seed = 193604
	# Leave space for the outbuildings behind the aprons and for the roadside
	# landmarks Deb calls out. The original Q section has several unsigned farms.
	clearings = PackedVector2Array([Route.HOME_PARK, Vector2(45, Route.COOP_Z - 20),
			Vector2(-246, -1145), Vector2(310, -678)])
	for site: Dictionary in Route.SITES.values():
		clearings.append(site.yard)
	for marker: Dictionary in Route.LANDMARKS:
		clearings.append(marker.position)

	for road: Dictionary in Route.ROADS:
		var start: Vector2 = road.a
		var end: Vector2 = road.b
		var along := start.direction_to(end)
		var station := rng.randf_range(75, 160)
		var group := rng.randi_range(0, 3)
		while station < start.distance_to(end) - 40:
			var across := along.orthogonal() * (-1 if rng.randf() < .5 else 1)
			var edge := start + along * station
			var spruce_share := rng.randf_range(.32, .74) if edge.y < -2200 else rng.randf_range(.12, .52)
			match group % 4:
				0:
					# A woodlot comes close to the ditch on one edge and recedes into the field.
					var depth := rng.randf_range(32, 65)
					_stand(town, edge + across * (depth + 22), along,
							Vector2(rng.randf_range(45, 88), depth), 8.4, spruce_share)
				2:
					# A narrow boundary between parcels runs away from the road.
					_stand(town, edge + across * rng.randf_range(75, 155), across,
							Vector2(rng.randf_range(35, 72), rng.randf_range(5, 10)), 7.2, spruce_share)
				_:
					_stand(town, edge + across * rng.randf_range(21, 32), along,
							Vector2(rng.randf_range(18, 42), rng.randf_range(5, 11)), 7.7, spruce_share)
			station += rng.randf_range(130, 330)
			group += 1


func _stand(town, center: Vector2, axis: Vector2, radii: Vector2, spacing: float, spruce_share: float) -> void:
	var columns := floori(radii.x / spacing)
	var rows := floori(radii.y / spacing)
	for row in range(-rows, rows + 1):
		for col in range(-columns, columns + 1):
			var jitter := Vector2(rng.randf_range(-.42, .42), rng.randf_range(-.42, .42))
			var offset := (Vector2(col, row) + jitter) * spacing
			var rim := (offset / radii).length_squared()
			if rim > rng.randf_range(.8, 1.14) or rng.randf() < .11:
				continue
			var point := center + axis * offset.x + axis.orthogonal() * offset.y
			if _in_clearing(point):
				continue
			# Saplings mingle at the exposed edge; larger crowns share the interior.
			var height := rng.randf_range(7.0, 15.8) * lerpf(1.12, .74, minf(rim, 1.0))
			var at := Vector3(point.x, 0, point.y)
			var roadside: bool = town._near_surface(point, 30)
			if rng.randf() < spruce_share:
				town._pine(at, height, not roadside)
			else:
				town._bare_tree(at, height, roadside)


func _in_clearing(point: Vector2) -> bool:
	for yard in clearings:
		if point.distance_squared_to(yard) < 60.0 * 60.0:
			return true
	return false
