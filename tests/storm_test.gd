extends SceneTree

const Route = preload("res://world/route.gd")
const Township = preload("res://world/township.gd")
var failures := PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func _expect(value: bool, explanation: String) -> void:
	if not value:
		failures.append(explanation)

func _run() -> void:
	var town := Township.new()
	root.add_child(town)
	town.set_process(false)
	_check_squalls(town)
	_check_lamps(town)
	_check_beam(town)
	_check_highway_snow(town)
	town.free()
	if failures.is_empty():
		print("PASS: gusts, weather visibility, localized lamps and snow illumination")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check_squalls(town: Township) -> void:
	var lightest := 1.0
	var strongest := 0.0
	var clear_density := INF
	var storm_density := 0.0
	for i in 420:
		town._process(.1)
		var intensity := town.gust_strength
		if not is_finite(intensity) or intensity < 0. or intensity > 1.:
			_expect(false, "gust envelope must be finite and bounded for both visual and audio mixing")
			break
		if intensity < lightest:
			lightest = intensity
			clear_density = town.storm_env.fog_density
		if intensity > strongest:
			strongest = intensity
			storm_density = town.storm_env.fog_density
	_expect(lightest < .2 and strongest > .80, "a shift must have genuine lulls and squalls")
	_expect(clear_density>0 and storm_density>clear_density*1.5, "a squall must close down distant landmarks")
	_expect(town.storm_env.ambient_light_energy < .55 and town.storm_env.fog_light_color.get_luminance()<.4, "ambient snow and fog must stay darker than the local lamps")
	_expect(is_equal_approx(town.flake_material.get_shader_parameter("gust"), town.gust_strength) and is_equal_approx(town.drift_material.get_shader_parameter("gust"), town.gust_strength), "airborne and ground powder must follow the same gust")
	_expect(absf(town.snowfall.direction.x)>absf(town.snowfall.direction.y), "airborne snow must travel across the road")

func _check_lamps(town: Township) -> void:
	var street_lamps := town.find_children("*","SpotLight3D",false,false)
	_expect(street_lamps.size() >= 2, "the main road needs isolated working lamps")
	for i in street_lamps.size():
		var lamp := street_lamps[i] as SpotLight3D
		_expect(lamp.light_color.r > lamp.light_color.b and lamp.spot_range > lamp.position.y and lamp.spot_range < 14., "a warm, downward streetlamp must reach its own base with a short pool")
		for j in range(i+1,street_lamps.size()):
			var next := street_lamps[j] as SpotLight3D
			_expect(lamp.position.distance_to(next.position) > lamp.spot_range+next.spot_range, "road between fixtures must stay unlit")
	var porches := town.find_children("*","OmniLight3D",false,false)
	_expect(porches.size()>=2, "home and Beck porches need local lights")
	for surface: ShaderMaterial in [town.flake_material,town.drift_material]:
		var centers: PackedVector3Array = surface.get_shader_parameter("yard_lamps")
		_expect(centers.size()==porches.size()+street_lamps.size(), "powder scattering must use the positions of the installed lights")

func _check_beam(town: Township) -> void:
	var at := Vector3(8.5, -.7, Route.BECK_Z + 90.)
	var chassis := Basis.from_euler(Vector3(.12, -1.4, .17))
	town.set_truck_pose(at, -chassis.z, chassis.y)
	for surface: ShaderMaterial in [town.flake_material,town.drift_material]:
		var position: Vector3 = surface.get_shader_parameter("truck_position")
		var heading: Vector3 = surface.get_shader_parameter("truck_forward")
		var up: Vector3 = surface.get_shader_parameter("truck_up")
		_expect(position == at and heading.is_equal_approx(-chassis.z) and up.is_equal_approx(chassis.y), "light on blowing snow follows the pitched and banked headlights in a ditch")
	town.set_truck_pose(Vector3.ZERO,Vector3.UP)
	_expect(town.truck_position == at and town.truck_forward.is_equal_approx(-chassis.z), "a degenerate heading must preserve the last valid light volume")

func _check_highway_snow(town: Township) -> void:
	var camera := Camera3D.new()
	town.add_child(camera)
	camera.make_current()
	town._process(0.)
	var parked := town.snowfall.global_position - camera.global_position
	for frame in 60:
		camera.position.z -= 22. / 30.
		town._process(1. / 30.)
	var moving := town.snowfall.global_position - camera.global_position
	_expect(parked.z - moving.z > 17., "the driver must keep entering fresh crosswind snow at 50 mph")
	camera.position.z += 7.
	town._process(1. / 30.)
	_expect((town.snowfall.global_position - camera.global_position).is_equal_approx(parked), "a camera cut must restart snow around the new view")
