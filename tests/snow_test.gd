extends SceneTree

const Snow = preload("res://world/plowed_snow.gd")
const Route = preload("res://world/route.gd")
var snow: Snow
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func _run() -> void:
	snow = Snow.new()
	root.add_child(snow)
	for edge: Vector2 in [Vector2(-4.3, Route.ROAD_NORTH_Z), Vector2(4.3, Route.ROAD_SOUTH_Z), Route.BECK_PARK, Route.HOME_PARK]:
		expect(snow.on_surface(edge), "Driveable snow should include %s" % edge)
	for outside: Vector2 in [Vector2(0, Route.ROAD_NORTH_Z - 1),Vector2(5,10),Vector2(139, Route.BECK_Z),Vector2(200,-900)]:
		expect(not snow.on_surface(outside) and is_zero_approx(snow.clearance(outside)), "Off-road sampling is safe at %s" % outside)
	expect(snow.open_length()==0, "New route has no cleared sections")
	for i in range(90):
		snow.press_tires(Vector3(i*.5,0,Route.BECK_Z),Vector3.RIGHT)
	expect(snow.open_length()==0, "Driving without the blade cannot clear a job")
	expect(snow.clearance(Vector2(14,Route.BECK_Z + .8)) > .15 and snow.clearance(Vector2(14,Route.BECK_Z + .8)) < .5,"Tires compact two tracks")
	expect(is_zero_approx(snow.clearance(Vector2(14,Route.BECK_Z))), "Center snow between tire tracks stays fresh")
	_pass(3,14)
	var partial := snow.open_length()
	expect(partial>=9 and partial<=11, "A short first pass opens only the entrance")
	expect(snow.clearance(Vector2(8,Route.BECK_Z))>.99, "Blade fully clears the center of a pass")
	var windrow := Vector2(8, Route.BECK_Z + 1.43)
	var tile := snow.tiles[snow._tile_key(windrow)]
	var bank := tile.field.get_pixelv(tile.pixel(windrow)).g
	expect(bank>.67, "Blade deposits a windrow on the right edge")
	_pass(28, Route.LAST_SLICE + 2)
	expect(snow.open_length()==partial, "A gap between two strips prevents through access")
	expect(snow.clearance(Vector2(19,Route.BECK_Z))<.8, "Lifting the blade doesn't connect distant strips")
	_pass(14,28)
	expect(snow.open_length()==Route.FULL_LANE, "Joining the entrance and unloading strip opens a continuous lane")
	_pass(Route.LAST_SLICE + 2, 3)
	expect(snow.open_length()==Route.FULL_LANE, "A return pass preserves a complete lane")
	snow.press_tires(Vector3(7,0,Route.BECK_Z),Vector3.RIGHT)
	expect(snow.clearance(Vector2(7,Route.BECK_Z))>.99,"Tires cannot bury a cleared surface")
	snow.cut(Vector3(80,0,70), Vector3.FORWARD)
	expect(snow.clearance(Vector2(26,-20)) < .8, "Moving the blade across a large distance doesn't plow a phantom line")
	snow._process(0)
	expect(snow.dirty_tiles.is_empty(), "Uploaded snow state stays unchanged until another cut")
	# A blade crossing a tile boundary must leave one continuous, persistent swath.
	for i in range(-10, 11):
		snow.cut(Vector3(0, 0, -960 + i * .2), Vector3.BACK)
	expect(snow.dirty_tiles.size() == 2, "Only the two tiles touched by this pass need uploading")
	for i in range(-6, 7):
		expect(snow.clearance(Vector2(0, -960 + i * .25)) > .99, "County tracks continue across tile edges")
	expect(snow.open_length() == Route.FULL_LANE, "Working a distant field preserves the Beck lane")
	var region := Vector2(5800, 800)
	snow.stream_to(region)
	var original: Vector2i = snow._tile_key(Vector2(8, Route.BECK_Z))
	expect(not snow.visible_tiles.has(original), "A distant farm releases its road mesh and texture")
	expect(snow.visible_tiles.size() < snow.tiles.size() / 8, "Only the driver's part of the county allocates road geometry")
	snow.cut(Vector3(region.x, 0, region.y), Vector3.RIGHT)
	snow._process(0)
	snow.stream_to(Route.BECK_PARK)
	expect(snow.clearance(Vector2(8, Route.BECK_Z)) > .99 and snow.open_length() == Route.FULL_LANE, "Revisiting the farm restores the cut and the completed lane")
	var far_tile := snow.tiles[snow._tile_key(region)]
	expect(far_tile.texture == null and far_tile.field == null and not far_tile.packed.is_empty(), "A worked road is archived when the truck travels to another district")
	snow.stream_to(region)
	expect(snow.clearance(region) > .99 and far_tile.texture.get_image().get_pixelv(far_tile.pixel(region)).r > .99, "A streamed road restores the same cut to physics and the visible snow texture")
	for indexed_tile in snow.tiles.values():
		if indexed_tile.footprints.size() > 16:
			expect(false, "The shader must have room for every road strip on a tile")
			break
	print("Snow tests: ",checks," checks, ",failures," failures")
	quit(int(failures>0))

func _pass(from_x:int,to_x:int) -> void:
	snow.stop_pass()
	var step := 1 if from_x < to_x else -1
	var forward := Vector3.RIGHT*step
	for i in range(from_x*5,to_x*5+step,step):
		snow.cut(Vector3(i*.2,0,Route.BECK_Z),forward)
	snow.stop_pass()
