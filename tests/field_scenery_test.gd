extends SceneTree

const Route = preload("res://world/route.gd")
const Township = preload("res://world/township.gd")
const Roadside = preload("res://world/roadside.gd")

var failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var town := Township.new()
	root.add_child(town)
	await physics_frame
	await physics_frame
	var space := town.get_world_3d().direct_space_state
	var labels := town.find_children("*", "Label3D", false, false)
	_check_business_signs(town)
	for id: String in Route.SITES:
		if Route.CORE_SITES.has(id):
			continue
		var site: Dictionary = Route.SITES[id]
		var yard := Vector3(site.yard.x,1.08,site.yard.y)
		var fixture := Vector3(site.stop.x,1.08,site.stop.y)
		var path := PhysicsRayQueryParameters3D.create(yard, fixture, 1)
		# Walk from the driver's side of the fixture until it is within reach.
		var hit := space.intersect_ray(path)
		if hit.is_empty() or hit.position.distance_to(fixture) > 1.6:
			failures.append("Missing or obstructed outdoor handoff at " + site.name)
		var label: String = site.fixture.trim_prefix("the ").to_upper()
		if not _signed(labels,label,site.stop,2.4) or not _signed(labels,site.name.to_upper(),site.mouth,12):
			failures.append("Missing fixture or entrance sign at " + site.name)
	# Include the four corners and seams with the old Q terrain.
	for x: float in [-6398,-4800,-725,-15.05,-14.95,0,14.95,15.05,725,4800,6398]:
		for z: float in [-6398,-2200.1,-2199.9,199.9,200.1,6398]:
			_check_ground(space, Vector2(x, z))
	var low := INF
	var high := -INF
	# Cross a swale, then walk a crest deep into a field between the county roads.
	for x in range(17, 1840, 17):
		var p := Vector2(x, 1400 + x * .38)
		var y := _check_ground(space, p)
		low = minf(low, y)
		high = maxf(high, y)
	if high - low < 8.0:
		failures.append("Missing rolling relief across the open fields")
	town.free()
	if failures.is_empty():
		print("PASS: 28 signed outer driveways and accessible fixtures, and rolling field collision (%.1f m of relief)" % (high - low))
	else:
		for reason in failures:
			push_error(reason)
	quit(int(not failures.is_empty()))

func _check_business_signs(town: Township) -> void:
	var faces := town.find_children("*", "MeshInstance3D", false, false)
	for id: String in Route.Survey.BUSINESS_SIGNS:
		var design: Dictionary = Route.Survey.BUSINESS_SIGNS[id]
		var site: Dictionary = Route.SITES[id]
		var traffic: Vector2 = site.mouth.direction_to(site.yard).orthogonal()
		for direction: float in [-1.0, 1.0]:
			var approach := traffic * direction
			if not Route.directions(site.mouth + approach * 75.0, id).contains(design.mark):
				failures.append("Deb's final turn misses the painted landmark at " + site.name)
			var readable := false
			for face: MeshInstance3D in faces:
				var quad := face.mesh as QuadMesh
				if not quad or not quad.material is StandardMaterial3D or quad.material.albedo_texture != design.art:
					continue
				var at := Vector2(face.position.x, face.position.z)
				var normal := Vector2(face.basis.z.x, face.basis.z.z)
				if at.distance_to(site.mouth) < 25.0 and normal.dot(approach) > .95:
					readable = true
			if not readable:
				failures.append("Missing painted sign face on approach to " + site.name)

func _check_ground(space: PhysicsDirectSpaceState3D, p: Vector2) -> float:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40, p.y), Vector3(p.x, -40, p.y), 2)
	var hit := space.intersect_ray(ray)
	var grade := Roadside.height_at(p.x, p.y)
	if hit.is_empty():
		failures.append("Missing field collision under %s" % p)
	elif absf(hit.position.y - grade) > .2:
		failures.append("Field mesh at %s is %.2f m from the wheel contact grade" % [p, hit.position.y - grade])
	return grade


func _signed(labels: Array[Node], text: String, near: Vector2, reach: float) -> bool:
	for label: Label3D in labels:
		var p := Vector2(label.position.x,label.position.z)
		if label.text == text and p.distance_squared_to(near) < reach*reach:
			return true
	return false
