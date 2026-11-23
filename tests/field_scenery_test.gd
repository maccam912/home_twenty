extends SceneTree

const Route = preload("res://world/route.gd")
const Township = preload("res://world/township.gd")

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
	# The four corners and seams with the old Q terrain used to have no ground.
	for x: float in [-6398,-4800,-725,-15.05,-14.95,0,14.95,15.05,725,4800,6398]:
		for z: float in [-6398,-2200.1,-2199.9,199.9,200.1,6398]:
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x,2,z),Vector3(x,-2,z),2)
			if space.intersect_ray(ray).is_empty():
				failures.append("Missing field collision under %s" % Vector2(x,z))
	town.free()
	if failures.is_empty():
		print("PASS: 28 signed outer driveways and accessible fixtures, and field collision in all four corners")
	else:
		for reason in failures:
			push_error(reason)
	quit(int(not failures.is_empty()))


func _signed(labels: Array[Node], text: String, near: Vector2, reach: float) -> bool:
	for label: Label3D in labels:
		var p := Vector2(label.position.x,label.position.z)
		if label.text == text and p.distance_squared_to(near) < reach*reach:
			return true
	return false
