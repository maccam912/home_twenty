extends SceneTree

const Snow = preload("res://world/plowed_snow.gd")
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
	for edge: Vector2 in [Vector2(-4.3,-129),Vector2(4.3,72),Vector2(51,-38),Vector2(-7.5,37)]:
		expect(snow.on_surface(edge), "Driveable snow should include %s" % edge)
	for outside: Vector2 in [Vector2(0,-130),Vector2(5,10),Vector2(51.1,-38),Vector2(200,-900)]:
		expect(not snow.on_surface(outside) and is_zero_approx(snow.clearance(outside)), "Off-road sampling is safe at %s" % outside)
	expect(snow.open_length()==0, "New route has no cleared sections")
	for i in range(90):
		snow.press_tires(Vector3(i*.5,0,-38),Vector3.RIGHT)
	expect(snow.open_length()==0, "Driving without the blade cannot clear a job")
	expect(snow.clearance(Vector2(14,-37.2)) > .15 and snow.clearance(Vector2(14,-37.2)) < .5,"Tires compact two tracks")
	expect(is_zero_approx(snow.clearance(Vector2(14,-38))), "Center snow between tire tracks stays fresh")
	_pass(3,14)
	var partial := snow.open_length()
	expect(partial>=9 and partial<=11, "A short first pass opens only the entrance")
	expect(snow.clearance(Vector2(8,-38))>.99, "Blade fully clears the center of a pass")
	var bank := snow.field.get_pixelv(snow._pixel(Vector2(8,-36.57))).g
	expect(bank>.67, "Blade deposits a windrow on the right edge")
	_pass(28,42)
	expect(snow.open_length()==partial, "A gap between two strips prevents through access")
	expect(snow.clearance(Vector2(19,-38))<.8, "Lifting the blade doesn't connect distant strips")
	_pass(14,28)
	expect(snow.open_length()==36, "Joining the entrance and unloading strip opens a continuous lane")
	_pass(42,3)
	expect(snow.open_length()==36, "A return pass preserves a complete lane")
	snow.press_tires(Vector3(7,0,-38),Vector3.RIGHT)
	expect(snow.clearance(Vector2(7,-38))>.99,"Tires cannot bury a cleared surface")
	snow.cut(Vector3(80,0,70), Vector3.FORWARD)
	expect(snow.clearance(Vector2(26,-20)) < .8, "Moving the blade across a large distance doesn't plow a phantom line")
	snow._process(0)
	expect(not snow.dirty, "Uploaded snow state stays unchanged until another cut")
	print("Snow tests: ",checks," checks, ",failures," failures")
	quit(int(failures>0))

func _pass(from_x:int,to_x:int) -> void:
	snow.stop_pass()
	var step := 1 if from_x < to_x else -1
	var forward := Vector3.RIGHT*step
	for i in range(from_x*5,to_x*5+step,step):
		snow.cut(Vector3(i*.2,0,-38),forward)
	snow.stop_pass()
