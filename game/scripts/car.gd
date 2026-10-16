class_name Car
extends RigidBody3D
## Prototype car for phase 2: raycast suspension over a rigid body (D-003), engine and
## gearbox from the original .sim data (cars.json, tools/sim_dump.py).
## The tyre model is a deliberately simple placeholder (slip angle with saturation and a
## friction circle); it is the part to replace while comparing with the original (R-1).

const LBFT_TO_NM := 1.3558
const IDLE_RPM := 900.0
const GRAVITY := 9.81
const AIR_DENSITY := 1.225

@export var suspension_travel := 0.12  ## m up and down from the design ride height
@export var damping_ratio := 0.35
@export var anti_roll := 1.0  ## anti-roll bar stiffness relative to the spring rate (per axle)
@export var bump_stop_rate := 10.0  ## stiffness multiplier in the last 10 % of travel
@export var grip := 1.0  ## tyre friction coefficient (placeholder; .sim 0x0F4 is a candidate)
@export var peak_slip_angle := 0.12  ## rad, lateral force saturates here
@export var max_steer_deg := 30.0
@export var steer_rate := 2.5  ## rad/s
@export var brake_decel_g := 1.0  ## brake force before the grip limit
@export var drivetrain_efficiency := 0.85
@export var drag_area := 0.6  ## Cd * frontal area, m2 (356: ~0.37 * 1.6)
@export var shift_time := 0.35  ## s without drive while shifting

var params: Dictionary = {}
var wheels: Array[Wheel] = []
var torque_curve := PackedFloat32Array()  ## Nm per 500 rpm, from 0 rpm
var gear_ratios := PackedFloat32Array()
var final_drive := 4.0
var reverse_ratio := -3.5
var redline := 6000.0
var wheel_radius := 0.3
var front_drive_share := 0.0
var spring_rate := 0.0
var damper_rate := 0.0

var gear := 1  ## -1 reverse, 1..n forward
var rpm := IDLE_RPM
var throttle := 0.0
var brake := 0.0
var handbrake := false
var steer := 0.0
var forward_speed := 0.0
var telemetry: Dictionary = {}

var _shift_timer := 0.0
var _last_velocity := Vector3.ZERO


class Wheel:
	var front := false
	var center := Vector3.ZERO  ## design position of the wheel centre in car space
	var ray: RayCast3D
	var visuals: Array[Node3D] = []
	var rest: Array[Transform3D] = []
	var compression := 0.0
	var normal_load := 0.0
	var spin := 0.0
	var force := Vector2.ZERO  ## applied tyre force: x longitudinal, y lateral (N)
	var partner: Wheel  ## other wheel on the same axle (anti-roll bar)
	var contact := false
	var point := Vector3.ZERO
	var normal := Vector3.UP
	var compression_speed := 0.0


func setup(model: Node3D, car_params: Dictionary) -> void:
	params = car_params
	can_sleep = false
	# Resistances are modelled explicitly (air drag, tyres); no engine-side damping.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	mass = float(params["mass_kg"])
	for ratio: float in params["gears"]:
		gear_ratios.append(ratio)
	for lbft: float in params["torque_curve_lbft_per_500rpm"]:
		torque_curve.append(lbft * LBFT_TO_NM)
	final_drive = float(params["final_drive"])
	reverse_ratio = float(params["reverse_ratio"])
	redline = float(params["redline_rpm"])
	front_drive_share = float(params["front_torque_split_pct"]) / 100.0
	var tyre: Dictionary = params["tyre"]
	wheel_radius = float(tyre["rim_in"]) * 0.0254 / 2.0 \
		+ float(tyre["width_mm"]) * float(tyre["aspect_pct"]) / 100.0 / 1000.0
	spring_rate = mass * GRAVITY / 4.0 / suspension_travel
	damper_rate = 2.0 * damping_ratio * sqrt(spring_rate * mass / 4.0)
	if model != null:
		add_child(model)
		_build_collision(model)
		_find_wheels(model)
	if wheels.is_empty():
		_default_wheels()
	for w in wheels:
		for other in wheels:
			if other != w and other.front == w.front and signf(other.center.x) != signf(w.center.x):
				w.partner = other
	_set_center_of_mass()


func reset_to(xf: Transform3D) -> void:
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	global_transform = xf
	gear = 1
	steer = 0.0


# --- setup helpers -----------------------------------------------------------------------

func _relative_transform(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _build_collision(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var b := _relative_transform(mi, model) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-0.8, 0.0, -2.0), Vector3(1.6, 1.3, 4.0))
	# Keep the body box above the wheels' contact patch so only the rays touch the road.
	var bottom := maxf(box.position.y, wheel_radius * 1.1)
	var top := box.end.y
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.size.x, top - bottom, box.size.z)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(box.get_center().x, (top + bottom) / 2.0, box.get_center().z)
	add_child(col)


func _find_wheels(model: Node3D) -> void:
	var nodes: Array[Node3D] = []
	for child in model.find_children("*", "Node3D", true, false):
		nodes.append(child as Node3D)
	for node in nodes:
		var front := node.name.begins_with("WheelFront")
		if not (front or node.name.begins_with("WheelRear")):
			continue
		var w := _add_wheel(_relative_transform(node, model).origin, front)
		# Tyre tread and shadow are separate parts at the same place: move them together.
		for other in nodes:
			var origin := _relative_transform(other, model).origin
			if origin.distance_to(w.center) < 0.05 and (other.get_parent() == node.get_parent()):
				w.visuals.append(other)
				w.rest.append(other.transform)


func _default_wheels() -> void:
	var half_base := float(params.get("wheelbase_mm", 2300.0)) / 2000.0
	for z: float in [-half_base, half_base]:
		for x: float in [-0.7, 0.7]:
			_add_wheel(Vector3(x, wheel_radius, z), z < 0.0)


func _add_wheel(center: Vector3, front: bool) -> Wheel:
	var w := Wheel.new()
	w.center = center
	w.front = front
	w.ray = RayCast3D.new()
	w.ray.position = center + Vector3.UP * suspension_travel
	w.ray.target_position = Vector3.DOWN * (2.0 * suspension_travel + wheel_radius)
	add_child(w.ray)
	wheels.append(w)
	return w


func _set_center_of_mass() -> void:
	var front_z := 0.0
	var rear_z := 0.0
	for w in wheels:
		if w.front:
			front_z += w.center.z
		else:
			rear_z += w.center.z
	front_z /= 2.0
	rear_z /= 2.0
	var wheelbase := rear_z - front_z
	var shift := {"rear": 0.08, "front": -0.04, "mid": 0.04}.get(params.get("engine_position", "mid"), 0.0) as float
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.45, (front_z + rear_z) / 2.0 + shift * wheelbase)


# --- simulation ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if wheels.is_empty() or delta <= 0.0:
		return
	forward_speed = -global_basis.z.dot(linear_velocity)
	_read_input(delta)
	_update_gearbox(delta)
	var wheel_torque := 0.0
	if _shift_timer <= 0.0:
		wheel_torque = _engine_torque() * throttle * _gear_ratio() * final_drive * drivetrain_efficiency
	for w in wheels:
		_update_contact(w, delta)
	for w in wheels:
		var share := front_drive_share if w.front else 1.0 - front_drive_share
		_apply_wheel(w, delta, wheel_torque * share / 2.0)
	var v := linear_velocity
	apply_central_force(-v * v.length() * 0.5 * AIR_DENSITY * drag_area)
	_update_telemetry(delta)


func _read_input(delta: float) -> void:
	var accel := Input.get_action_strength("accelerate")
	var brk := Input.get_action_strength("brake")
	handbrake = Input.is_action_pressed("handbrake")
	if gear == -1:
		throttle = brk
		brake = accel
		if accel > 0.1 and forward_speed > -0.5:
			gear = 1
	else:
		throttle = accel
		brake = brk
		if brk > 0.1 and accel < 0.1 and absf(forward_speed) < 0.5:
			gear = -1  # arcade style: holding brake at standstill reverses
	var steer_input := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var limit := deg_to_rad(max_steer_deg) * lerpf(1.0, 0.35, clampf(absf(forward_speed) / 40.0, 0.0, 1.0))
	steer = move_toward(steer, steer_input * limit, steer_rate * delta)


func _gear_ratio() -> float:
	if gear == -1:
		return reverse_ratio
	return gear_ratios[gear - 1]


func _update_gearbox(delta: float) -> void:
	_shift_timer = maxf(_shift_timer - delta, 0.0)
	rpm = absf(forward_speed) / wheel_radius * absf(_gear_ratio()) * final_drive * 60.0 / TAU
	if gear > 0 and _shift_timer <= 0.0:
		if rpm > redline * 0.95 and gear < gear_ratios.size():
			gear += 1
			_shift_timer = shift_time
		elif gear > 1 and rpm < redline * 0.5:
			gear -= 1
			_shift_timer = shift_time
	rpm = clampf(rpm, IDLE_RPM, redline)


func _engine_torque() -> float:
	if torque_curve.is_empty() or rpm >= redline:
		return 0.0  # rev limiter
	var f := rpm / 500.0
	var i := mini(int(f), torque_curve.size() - 1)
	var j := mini(i + 1, torque_curve.size() - 1)
	return lerpf(torque_curve[i], torque_curve[j], f - float(i))


func _update_contact(w: Wheel, delta: float) -> void:
	w.contact = w.ray.is_colliding()
	if not w.contact:
		w.compression = 0.0
		w.compression_speed = 0.0
		return
	w.point = w.ray.get_collision_point()
	w.normal = w.ray.get_collision_normal()
	var compression := 2.0 * suspension_travel + wheel_radius - w.ray.global_position.distance_to(w.point)
	w.compression_speed = (compression - w.compression) / delta
	w.compression = compression


func _apply_wheel(w: Wheel, delta: float, drive_torque: float) -> void:
	if not w.contact:
		w.normal_load = 0.0
		w.force = Vector2.ZERO
		_update_visual(w)
		return
	var wheel_load := spring_rate * w.compression + damper_rate * w.compression_speed
	var stop_start := 2.0 * suspension_travel * 0.9
	if w.compression > stop_start:
		wheel_load += spring_rate * bump_stop_rate * (w.compression - stop_start)
	if w.partner != null:
		wheel_load += spring_rate * anti_roll * (w.compression - w.partner.compression)
	w.normal_load = maxf(wheel_load, 0.0)
	var normal := w.normal
	var offset := w.point - global_position
	apply_force(normal * w.normal_load, offset)

	# Placeholder tyre: lateral force from slip angle, longitudinal from drive and brakes,
	# both limited by a friction circle.
	var wheel_basis := global_basis * Basis(Vector3.UP, steer if w.front else 0.0)
	var fwd := (-wheel_basis.z).slide(normal).normalized()
	var right := wheel_basis.x.slide(normal).normalized()
	var v := linear_velocity + angular_velocity.cross(offset)
	var v_long := v.dot(fwd)
	var v_lat := v.dot(right)
	var max_force := grip * w.normal_load
	var slip_angle := atan2(v_lat, maxf(absf(v_long), 3.0))
	var f_lat := -clampf(slip_angle / peak_slip_angle, -1.0, 1.0) * max_force
	var f_long := drive_torque / wheel_radius
	var brake_force := brake * brake_decel_g * mass * GRAVITY / 4.0
	if handbrake and not w.front:
		brake_force = maxf(brake_force, mass * GRAVITY / 2.0)
	if absf(v_long) > 0.5:
		f_long -= signf(v_long) * brake_force
	elif throttle < 0.05:
		f_long -= v_long * mass / 4.0 / delta * 0.5  # hold the car at standstill
	var f := Vector2(f_long, f_lat)
	if max_force > 0.0 and f.length() > max_force:
		f = f.normalized() * max_force
	apply_force(fwd * f.x + right * f.y, offset)
	w.force = f
	if not (handbrake and not w.front):
		w.spin = fmod(w.spin + v_long / wheel_radius * delta, TAU)
	_update_visual(w)


func _update_visual(w: Wheel) -> void:
	var lift := w.compression - suspension_travel
	var steer_basis := Basis(Vector3.UP, steer if w.front else 0.0)
	var spin_basis := Basis(Vector3.RIGHT, -w.spin)
	for i in w.visuals.size():
		var rest := w.rest[i]
		w.visuals[i].transform = Transform3D(steer_basis * spin_basis * rest.basis, rest.origin + Vector3.UP * lift)


func _update_telemetry(delta: float) -> void:
	var accel := (linear_velocity - _last_velocity) / delta
	_last_velocity = linear_velocity
	var local := global_basis.transposed() * accel
	telemetry = {
		"speed_kmh": snappedf(forward_speed * 3.6, 0.01),
		"rpm": roundi(rpm),
		"gear": gear,
		"throttle": snappedf(throttle, 0.01),
		"brake": snappedf(brake, 0.01),
		"steer_deg": snappedf(rad_to_deg(steer), 0.1),
		"lat_g": snappedf(local.x / GRAVITY, 0.001),
		"long_g": snappedf(-local.z / GRAVITY, 0.001),
	}
