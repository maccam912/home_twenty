extends SceneTree

const Route = preload("res://world/route.gd")
const Township = preload("res://world/township.gd")
const BOUGH_TEXTURE = preload("res://world/trees/snow_bough.webp")
var failures := 0

# The headless renderer discards individual MultiMesh transforms. Inspect the
# actual geometry as it enters the normal rendering batch, including far meshes.
class SurveyedTown extends Township:
	var crowns: Array[Rect2] = []
	var roots := PackedVector2Array()
	var orchards := 0

	func _shape_at(mesh: Mesh, placement: Transform3D, material: String) -> void:
		if material in ["tree_bark", "spruce_needles"]:
			var bounds := placement * mesh.get_aabb()
			crowns.append(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z))
			if material == "tree_bark":
				roots.append(Vector2(placement.origin.x, placement.origin.z))
		super(mesh, placement, material)

	func _block(title: String, at: Vector3, dims: Vector3, yaw := 0.0) -> void:
		if title == "Apple trunk":
			crowns.append(Rect2(Vector2(at.x, at.z) - Vector2.ONE * 2, Vector2(4, 4)))
			orchards += 1
		super(title, at, dims, yaw)

func _initialize() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var town := SurveyedTown.new()
	root.add_child(town)
	_check_imports(town)
	_check_foliage(town)
	_check_stands(town)
	_check_survey(town)
	await physics_frame
	await physics_frame
	_check_clearance(town)
	if failures == 0:
		print("PASS: %d winter trees and %d orchard trees leave all roads, drives, and yards clear" % [town.roots.size(), town.orchards])
	town.free()
	quit(0 if failures == 0 else 1)

func _check_imports(town: Node3D) -> void:
	for variant in 3:
		for pattern in ["Spruce%dBoughs", "Spruce%dWood", "Birch%dWood"]:
			var detailed_name: String = pattern % variant
			var near_mesh := town.tree_meshes.get(detailed_name) as ArrayMesh
			var far_mesh := town.tree_meshes.get(detailed_name + "Far") as ArrayMesh
			expect(near_mesh != null and far_mesh != null, "Missing imported form for " + detailed_name)
			if not near_mesh or not far_mesh:
				continue
			var bounds := near_mesh.get_aabb()
			expect(bounds.size.y > 7.0 and bounds.size.y < 13.0, detailed_name + " has incorrect metres or vertical axis")
			expect(absf(bounds.get_center().x) < 2.5 and absf(bounds.get_center().z) < 2.5, detailed_name + " retained its Blender workbench translation")
			var near_count := near_mesh.surface_get_array_index_len(0)
			var far_count := far_mesh.surface_get_array_index_len(0)
			expect(far_count > 0 and far_count < near_count * .55, detailed_name + " has no low-cost outer-woodlot form")
			if pattern.ends_with("Boughs"):
				expect(bounds.size.x>2.0 and bounds.size.z>2.0, detailed_name + " has a flat crown")
				expect((near_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV) != 0, detailed_name + " is missing foliage UVs")
			else:
				expect((near_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0, detailed_name + " lost its painted bark")

func _check_foliage(town: Node3D) -> void:
	var mat := town.mats.get("spruce_needles") as ShaderMaterial
	expect(mat != null and mat.get_shader_parameter("needles") == BOUGH_TEXTURE,"The spruce material must use the imported spruce cutout")
	var bitmap := BOUGH_TEXTURE.get_image()
	if not bitmap:
		expect(false,"Cannot read the spruce foliage atlas")
		return
	expect(bitmap.has_mipmaps(),"Distant needle sprays need mipmaps to avoid flicker")
	var clear := 0
	var opaque := 0
	var snowy := 0
	for v in range(0,bitmap.get_height(),12):
		for u in range(0,bitmap.get_width(),12):
			var sample := bitmap.get_pixel(u,v)
			if sample.a<.12:
				clear += 1
			if sample.a>.9:
				opaque += 1
				if sample.r>.62 and sample.b>.62:
					snowy += 1
	expect(clear > 100 and opaque > 100 and snowy > 12,"Bough texture lost its open gaps or snow dusting")

func _check_stands(town: Node3D) -> void:
	var forms := {}
	var cells := {}
	var count := 0
	for node in town.get_children():
		if node is MultiMeshInstance3D and node.material_override == town.mats.spruce_needles:
			forms[node.multimesh.mesh] = true
			cells[node.position] = true
			var bounds: AABB = node.get_aabb()
			expect(maxf(bounds.size.x,bounds.size.z) < town.SCENERY_CELL + 50, "A distant tree should not keep a township-wide batch visible")
			count += node.multimesh.instance_count
	expect(forms.size() >= 3 and forms.size() <= 6, "Spruce forms should be shared, instanced batches")
	expect(count > 30 and cells.size() > 4, "The field stands are missing or lost instancing")

func _check_survey(town: SurveyedTown) -> void:
	for crown in town.crowns:
		for surface in town.road_bounds:
			if crown.intersects(surface, true):
				expect(false, "Tree extends onto a driving surface near %s" % crown.get_center())
				return
	expect(town.orchards > 0, "The orchard crowns must participate in the road survey")
	var stands := {}
	var field_trees := 0
	for point in town.roots:
		var cell := Vector2i((point / 100.0).floor())
		stands[cell] = stands.get(cell, 0) + 1
		if not town._near_surface(point, 65):
			field_trees += 1
	expect(stands.values().max() >= 40 and field_trees >= 200, "Missing woods and stands between fields")
	for road: Dictionary in Route.ROADS:
		var nearby := 0
		for point in town.roots:
			if point.distance_to(Route._projection(point, road)) < 38:
				nearby += 1
				if nearby >= 5:
					break
		expect(nearby >= 5, "Missing roadside trees along " + road.name)

func _check_clearance(town: Node3D) -> void:
	var space := town.get_world_3d().direct_space_state
	var trunk := PhysicsRayQueryParameters3D.create(Vector3(-83.0,1.4,Route.HOME_Z+16),Vector3(-81.0,1.4,Route.HOME_Z+16))
	expect(not space.intersect_ray(trunk).is_empty(),"Roadside spruce lost its trunk collider")
	var road := PhysicsRayQueryParameters3D.create(Vector3(0,1.4,Route.HOME_Z),Vector3(0,1.4,Route.BECK_Z))
	expect(space.intersect_ray(road).is_empty(),"A collider blocks the middle of County Q")
	var lane := PhysicsRayQueryParameters3D.create(Vector3(1,1.4,Route.BECK_Z),Vector3(Route.BECK_PARK.x,1.4,Route.BECK_Z))
	expect(space.intersect_ray(lane).is_empty(),"A collider blocks the tank lane")
	var bell := PhysicsRayQueryParameters3D.create(Vector3(355,1.4,-719.45), Vector3(455,1.4,-719.45), 1)
	expect(space.intersect_ray(bell).is_empty(), "A collider blocks School Road approaching Bell School")
