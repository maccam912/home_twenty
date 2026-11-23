extends Node3D

signal horn_used
signal blade_changed
signal cab_changed
signal collapse_recovered

const TruckMesh = preload("res://vehicle/truck_mesh.gd")
const Route = preload("res://world/route.gd")
const TRUCK_START := Vector3(Route.HOME_PARK.x, 0.0, Route.HOME_PARK.y)
const WHEELBASE := 3.24
const WALK_SPEED := 2.9

var in_cab := true
var blade_down := false
var speed_mps := 0.0
var cold := 0.0
var snow_load := 0.0

var _truck: CharacterBody3D
var _walker: CharacterBody3D
var _walker_shape: CollisionShape3D
var _model: TruckMesh
var _camera: Camera3D
var _cab_view := false
var _steering := 0.0
var _walk_yaw := 0.0
var _walk_pitch := 0.0
var _walk_phase := 0.0
var _cab_yaw := 0.0
var _cab_pitch := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _mouse_idle := 0.0


func _ready() -> void:
	_truck = CharacterBody3D.new()
	_truck.name = "Truck"
	_truck.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_truck.wall_min_slide_angle = 0.0
	add_child(_truck)
	_truck.global_position = TRUCK_START
	_truck.rotation.y = -PI / 2.0
	var hull := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.96, 1.38, 5.28)
	hull.shape = box
	hull.position = Vector3(0, 1.07, 0.10)
	_truck.add_child(hull)
	_model = TruckMesh.new()
	_model.name = "Pickup"
	_truck.add_child(_model)

	_walker = CharacterBody3D.new()
	_walker.name = "Walker"
	_walker.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_walker.wall_min_slide_angle = 0.0
	add_child(_walker)
	_walker_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.65
	_walker_shape.shape = capsule
	_walker_shape.position.y = 0.89
	_walker_shape.disabled = true
	_walker.add_child(_walker_shape)
	_walker.global_position = _truck.global_position
	_camera = Camera3D.new()
	_camera.name = "DriverCamera"
	_camera.near = 0.055
	_camera.far = 1400
	_camera.fov = 64
	add_child(_camera)
	_camera.make_current()
	_place_camera(0.0, true)


func get_truck_position() -> Vector3:
	return _truck.global_position


func get_driver_position() -> Vector3:
	return _truck.global_position if in_cab else _walker.global_position


func get_blade_position() -> Vector3:
	return _truck.to_global(Vector3(0, 0.12, -3.23))


func set_storm_strength(strength: float) -> void:
	_model.set_storm_strength(strength)


func get_forward() -> Vector3:
	return -_truck.global_basis.z.normalized()


func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("mobile"):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is not InputEventMouseMotion or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion: Vector2 = event.relative * 0.003
	if not in_cab:
		_walk_yaw -= motion.x
		_walk_pitch = clampf(_walk_pitch - motion.y, -1.12, 1.12)
	elif _cab_view:
		_cab_yaw = clampf(_cab_yaw - motion.x, -1.54, 1.54)
		_cab_pitch = clampf(_cab_pitch - motion.y, -0.82, 0.69)
	else:
		_orbit_yaw = wrapf(_orbit_yaw - motion.x, -PI, PI)
		_orbit_pitch = clampf(_orbit_pitch + motion.y, -0.25, 0.72)
	_mouse_idle = 2.5


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("horn"):
		horn_used.emit()
	if Input.is_action_just_pressed("interact"):
		if in_cab:
			_leave_truck()
		elif _walker.global_position.distance_to(_truck.global_position) <= 4.2:
			_enter_truck()
	if in_cab:
		if Input.is_action_just_pressed("blade"):
			blade_down = not blade_down
			blade_changed.emit()
		if Input.is_action_just_pressed("camera_view"):
			_cab_view = not _cab_view
			_cab_yaw = 0
			_cab_pitch = 0
			_orbit_yaw = 0
			_orbit_pitch = 0
			_place_camera(delta, true)
		_drive(delta)
		cold = maxf(0.0, cold - delta / 15.0)
	else:
		_walk(delta)
		cold = minf(1.0, cold + delta / 110.0)
		if cold >= 1.0:
			cold = 0.32
			_enter_truck()
			collapse_recovered.emit()
	_model.animate(delta, speed_mps, _steering, blade_down)
	_place_camera(delta)


func _drive(delta: float) -> void:
	var throttle := Input.get_action_strength("accelerate") - Input.get_action_strength("reverse")
	var steer := Input.get_axis("steer_left", "steer_right")
	_steering = move_toward(_steering, steer, delta * 4.0)
	var load := clampf(snow_load, 0.0, 1.0)
	var forward_limit := lerpf(15.0, 6.1, load)
	if blade_down:
		forward_limit = minf(forward_limit, lerpf(9.2, 4.9, load))
	var target := throttle * (forward_limit if throttle >= 0 else lerpf(5.3, 3.6, load))
	var acceleration := lerpf(5.3, 2.95, load)
	if is_zero_approx(throttle):
		acceleration = 2.8 + load * 1.5
	elif throttle * speed_mps < -0.05:
		acceleration = 9.5
	speed_mps = move_toward(speed_mps, target, acceleration * delta)
	var angle := _steering * lerpf(0.58, 0.31, clampf(absf(speed_mps) / 14.0, 0, 1))
	var turn_rate := -speed_mps * tan(angle) / WHEELBASE
	_truck.rotation.y += turn_rate * delta
	var forward := get_forward()
	_truck.velocity = forward * speed_mps
	if _truck.move_and_slide():
		# Keep the tangent component when glancing off a fence or parked car.
		speed_mps = _truck.get_real_velocity().dot(forward)


func _walk(delta: float) -> void:
	var steer := Input.get_axis("steer_left", "steer_right")
	_walk_yaw -= steer * 1.88 * delta
	var walk := Input.get_action_strength("accelerate") - Input.get_action_strength("reverse")
	var direction := Vector3.FORWARD.rotated(Vector3.UP, _walk_yaw)
	_walker.velocity = direction * walk * WALK_SPEED
	_walker.move_and_slide()
	_walk_phase = fmod(_walk_phase + _walker.get_real_velocity().length() * delta * 2.8, TAU)


func _leave_truck() -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _walker_shape.shape
	query.exclude = [_walker.get_rid(), _truck.get_rid()]
	# Try both doors, then the tailgate if the truck stopped beside an obstruction.
	for offset: Vector3 in [Vector3(-1.57, 0, -0.25), Vector3(1.57, 0, -0.25), Vector3(-1.58, 0, 1.10), Vector3(1.58, 0, 1.10), Vector3(0, 0, 3.21)]:
		var spot := _truck.to_global(offset)
		query.transform = Transform3D(Basis.IDENTITY, spot + _walker_shape.position)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		_walker.global_position = spot
		_walker_shape.disabled = false
		_walk_yaw = _truck.global_rotation.y
		_walk_pitch = 0.0
		_walk_phase = 0.0
		in_cab = false
		speed_mps = 0.0
		_truck.velocity = Vector3.ZERO
		_steering = 0.0
		_place_camera(0.0, true)
		cab_changed.emit()
		return


func _enter_truck() -> void:
	_walker_shape.disabled = true
	_walker.velocity = Vector3.ZERO
	in_cab = true
	_cab_pitch = 0
	_cab_yaw = 0
	_orbit_yaw = 0
	_orbit_pitch = 0
	_place_camera(0.0, true)
	cab_changed.emit()


func _place_camera(delta: float, snap := false) -> void:
	if not in_cab:
		_camera.fov = 69
		var bob := sin(_walk_phase) * 0.019
		_camera.global_position = _walker.global_position + Vector3(0, 1.66 + bob, 0)
		_camera.global_rotation = Vector3(_walk_pitch, _walk_yaw, 0)
		return
	_mouse_idle = maxf(0.0, _mouse_idle - delta)
	if _cab_view:
		_camera.fov = 75
		_camera.global_position = _truck.to_global(Vector3(-0.475, 1.76, -0.287))
		_camera.global_rotation = Vector3(_cab_pitch - 0.085, _truck.global_rotation.y + _cab_yaw, 0)
		return
	if _mouse_idle <= 0 and absf(speed_mps) > 0.5:
		_orbit_yaw = lerp_angle(_orbit_yaw, 0.0, 1.0 - exp(-delta * 2.0))
		_orbit_pitch = lerpf(_orbit_pitch, 0.0, 1.0 - exp(-delta * 2.0))
	_camera.fov = 64
	var orbit := _truck.global_rotation.y + _orbit_yaw
	var anchor := _truck.global_position + Vector3.UP * 1.38
	var boom := Vector3(0, 0, 7.2).rotated(Vector3.RIGHT, -0.31 - _orbit_pitch).rotated(Vector3.UP, orbit)
	var wanted := anchor + boom
	var ray := PhysicsRayQueryParameters3D.create(anchor, wanted)
	ray.exclude = [_truck.get_rid(), _walker.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		wanted = hit.position + (anchor - wanted).normalized() * 0.22
	if snap or not hit.is_empty():
		_camera.global_position = wanted
	else:
		_camera.global_position = _camera.global_position.lerp(wanted, 1.0 - exp(-delta * 12.0))
	var look_target := anchor + Vector3.FORWARD.rotated(Vector3.UP, orbit) * 1.4
	if _camera.global_position.distance_squared_to(look_target) > 0.001:
		_camera.look_at(look_target, Vector3.UP)
