class_name Car
extends RigidBody3D
## Prototype car for phase 2: raycast suspension over a rigid body (D-003), engine and
## gearbox from the original .sim data (cars.json, tools/sim_dump.py).
## Tyres: every wheel spins on its own (wheel inertia, plus engine inertia through the gearing
## on driven wheels); forces come from slip ratio and slip angle combined into one normalised
## slip, with a peak and a drop to sliding friction, load sensitivity and rolling resistance.
## Wheel spin is integrated in substeps so it stays stable at low speed.

const LBFT_TO_NM := 1.3558
const CarDamage := preload("res://scripts/car_damage.gd")
const IDLE_RPM := 900.0
const GRAVITY := 9.81
const AIR_DENSITY := 1.225

@export_group("Damage consequences")
## Per zone damage 0..1 (CarDamage) at full damage gives:
@export var damage_toe_deg := 3.0  ## wheel on a damaged corner toes out (the car pulls to that side)
@export var damage_grip_loss := 0.15  ## that wheel's grip (bent suspension)
@export var damage_power_loss := 0.35  ## engine torque, from the zones around the engine
@export var damage_drag_gain := 0.15  ## drag area, from the average damage
@export var damage_steer_loss := 0.2  ## steering lock, from the front centre zone
@export var damage_wobble_deg := 8.0  ## wheel on a corner damaged past 50 % wobbles, this much at 100 %
@export var wheel_mass := 15.0  ## kg of a wheel that comes off (corner and its side both at 100 %)
@export_group("")
@export var bump_travel := 0.08  ## m the wheel can move up from the model's ride height
@export var droop_travel := 0.10  ## m the wheel can drop below it
@export var ride_frequency := 1.7  ## Hz, sets the spring rate; springs are preloaded to the model's ride height
@export var damping_ratio := 0.35
@export var anti_roll_front := 1.0  ## anti-roll bar stiffness relative to the spring rate
@export var anti_roll_rear := 0.3  ## 356: front bar only, rear swing axle without one
@export var bump_stop_rate := 10.0  ## stiffness multiplier in the last 25 % of bump travel
@export var grip := 1.0  ## multiplier on the friction coefficient derived from .sim 0x0F4
@export var grip_base := 0.444  ## mu = grip_base + grip_per_sim * 0x0F4 (356 A 1.15 -> 0.85, 2.0 -> 1.15)
@export var grip_per_sim := 0.353
@export var peak_slip_ratio := 0.12  ## longitudinal slip with the most force
@export var rear_grip := 1.12  ## rear tyre grip vs front (axle geometry, tyre pressures): mild understeer, lost under braking
@export var slide_grip := 0.75  ## share of the peak force left when fully sliding
@export var load_sensitivity := 0.1  ## mu drops by this share per +100 % load over the static load
@export var rolling_resistance := 0.015  ## times the wheel load
@export var wheel_inertia := 1.2  ## kg m2 per wheel (wheel, tyre, brake drum)
@export var engine_brake := 0.12  ## engine drag torque off throttle, share of peak torque at redline
@export var brake_front_bias := 0.58  ## matches the axle loads when braking at 0.8 g
@export var wheel_substeps := 8
@export var max_steer_deg := 30.0
@export var steering_assist := true  ## limit front wheel angle to the tyres' peak slip angle
@export var brake_assist := true  ## ABS: wheels do not lock under the foot brake (the original does not lock them)
@export var abs_slip := 0.8  ## ABS releases a front wheel above this share of the peak slip ratio (keeps steering)
@export var abs_slip_rear := 1.2  ## same for the rear, past the peak: the unloaded rear slides and steps out but does not lock
@export var assist_margin := 1.1  ## allowed front slip angle, times the peak slip angle
@export var steer_rate := 4.0  ## rad/s, how fast the front wheels follow the (filtered) steering input
@export_group("Keyboard input")
## Keys are on/off: like the arcade racers of the time, the pedals and the steering wheel move
## gradually while a key is held. Off for analog input (gamepad, wheel) and physics tests.
@export var digital_input := true
@export var throttle_rise_time := 0.3  ## s from 0 to full throttle
@export var throttle_fall_time := 0.1
@export var brake_rise_time := 0.6  ## s from 0 to full brake: a tap only brushes the brakes
@export var brake_fall_time := 0.15
@export var steer_time_slow := 0.25  ## s from centre to full lock at a standstill
@export var steer_time_fast := 0.8  ## s from centre to full lock at steer_fast_speed
@export var steer_fast_speed := 41.7  ## m/s (150 km/h)
@export var steer_return_time := 0.2  ## s from full lock back to centre
@export_group("")
@export var brake_decel_g := 0.8  ## brake torque, as deceleration it would give without slip (drums ~0.8 g)
@export var drivetrain_efficiency := 0.85
@export var drag_area := 0.6  ## Cd * frontal area, m2 (356: ~0.37 * 1.6)
@export var shift_time := 0.35  ## s without drive while shifting
@export var rev_drop_rate := 2500.0  ## rpm/s, engine falling off throttle with the clutch open
@export var rev_rise_rate := 6000.0  ## rpm/s, throttle blip on a downshift
@export var clutch_sync_rate := 6000.0  ## rpm/s, engine pulled to the new gear as the clutch closes

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
var mu := 1.0  ## tyre friction coefficient at static load
var peak_slip_angle := 0.12  ## rad, from the tyre aspect ratio (taller sidewall = larger)
var engine_inertia := 0.09  ## kg m2, .sim 0x058 / 1000 (hypothesis)
var torque_peak := 100.0
var damage: CarDamage  ## null until setup_damage()
var _model: Node3D

var gear := 1  ## -1 reverse, 1..n forward
var rpm := IDLE_RPM
var throttle := 0.0
var brake := 0.0
var handbrake := false
var steer := 0.0
var forward_speed := 0.0
var telemetry: Dictionary = {}

var _shift_timer := 0.0
var _since_shift := 10.0
var _accel_key := 0.0  ## keyboard pedal values after the ramps
var _brake_key := 0.0
var _steer_key := 0.0
var _clutch_slipping := false  ## engine still being pulled to the new gear after a shift
var _last_velocity := Vector3.ZERO


class Wheel:
	var front := false
	var center := Vector3.ZERO  ## design position of the wheel centre in car space
	var ray: RayCast3D
	var visuals: Array[Node3D] = []
	var rest: Array[Transform3D] = []
	var compression := 0.0
	var normal_load := 0.0
	var spin := 0.0  ## visual rotation angle
	var omega := 0.0  ## angular speed, rad/s, positive rolling forwards
	var slip_ratio := 0.0
	var slip_angle := 0.0
	var force := Vector2.ZERO  ## applied tyre force: x longitudinal, y lateral (N)
	var partner: Wheel  ## other wheel on the same axle (anti-roll bar)
	var contact := false
	var point := Vector3.ZERO
	var normal := Vector3.UP
	var compression_speed := 0.0
	var zone := -1  ## damage corner zone (CarDamage.CORNER_ZONES)
	var toe := 0.0  ## rad, from damage, positive = to the left
	var grip_factor := 1.0  ## from damage
	var wobble := 0.0  ## rad, eccentric run of a damaged wheel
	var detached := false  ## came off: no ray, no forces
	var debris: RigidBody3D  ## the wheel flying off
	var visual_parents: Array[Node] = []


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
	torque_peak = float(params.get("torque_peak_nm", 100.0))
	final_drive = float(params["final_drive"])
	reverse_ratio = float(params["reverse_ratio"])
	redline = float(params["redline_rpm"])
	front_drive_share = float(params["front_torque_split_pct"]) / 100.0
	var tyre: Dictionary = params["tyre"]
	wheel_radius = float(tyre["rim_in"]) * 0.0254 / 2.0 \
		+ float(tyre["width_mm"]) * float(tyre["aspect_pct"]) / 100.0 / 1000.0
	peak_slip_angle = deg_to_rad(3.0 + 0.08 * float(tyre["aspect_pct"]))  # 70 % -> 8.6 deg, 30 % -> 5.4 deg
	var unknown: Dictionary = params.get("unknown", {})
	mu = (grip_base + grip_per_sim * float(unknown.get("0x0F4", 1.15))) * grip
	engine_inertia = float(unknown.get("0x058", 90.0)) / 1000.0
	spring_rate = mass / 4.0 * pow(TAU * ride_frequency, 2.0)
	damper_rate = 2.0 * damping_ratio * sqrt(spring_rate * mass / 4.0)
	_model = model
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


## Enables damage from <car>_damage.json (tools/crp2gltf.py): zones and detachable parts.
func setup_damage(info: Dictionary) -> void:
	damage = CarDamage.new(self, _model, info)
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 8)
	for w in wheels:
		w.zone = damage.corner_of(w.center)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if damage == null:
		return
	var contacts := []
	var to_car := global_basis.inverse()
	for i in state.get_contact_count():
		var impulse := state.get_contact_impulse(i).length()
		if impulse > 0.0:
			contacts.append({"impulse": impulse, "point": to_local(state.get_contact_local_position(i)),
				"normal": to_car * state.get_contact_local_normal(i)})
	damage.add_tick(contacts)


func _update_damage() -> void:
	if damage == null:
		return
	for w in wheels:
		var d := damage.zone(w.zone)
		w.toe = deg_to_rad(damage_toe_deg) * d * (1.0 if w.center.x < 0.0 else -1.0)  # toe out
		w.grip_factor = 1.0 - damage_grip_loss * d
		w.wobble = deg_to_rad(damage_wobble_deg) * smoothstep(0.5, 1.0, d)
		var side := damage.zone(7 if w.center.x < 0.0 else 3)
		if not w.detached and d >= 1.0 and side >= 1.0:
			_detach_wheel(w)


## The wheel comes off: no more ray and forces, its tyre and rim fly off, the corner drops.
func _detach_wheel(w: Wheel) -> void:
	w.detached = true
	w.contact = false
	w.compression = 0.0
	w.omega = 0.0
	w.ray.enabled = false
	var nodes: Array[Node3D] = []
	w.visual_parents.clear()
	for v in w.visuals:
		w.visual_parents.append(v.get_parent())
		if str(v.name).contains("Shadow"):
			v.visible = false  # flat shadow quad under the wheel
		else:
			nodes.append(v)
	var col := CollisionShape3D.new()
	var tyre := CylinderShape3D.new()
	tyre.radius = wheel_radius
	tyre.height = 0.16
	col.shape = tyre
	col.basis = Basis(Vector3.BACK, PI / 2.0)  # cylinder axis along the axle (X)
	w.debris = CarDamage.make_debris(self, nodes, wheel_mass, col)


## Puts the car back together: dents, detached parts and wheels.
func repair() -> void:
	if damage != null:
		damage.repair()
	for w in wheels:
		if not w.detached:
			continue
		for i in w.visuals.size():
			var v := w.visuals[i]
			if v.get_parent() != w.visual_parents[i]:
				v.reparent(w.visual_parents[i], false)
			v.transform = w.rest[i]
			v.visible = true
		if w.debris != null:
			w.debris.queue_free()
			w.debris = null
		w.detached = false
		w.ray.enabled = true


## Share of the engine torque left after damage to the zones around the engine.
func engine_health() -> float:
	if damage == null:
		return 1.0
	var front := str(params.get("engine_position", "rear")) == "front"
	var centre := damage.zone(1 if front else 5)
	var sides := maxf(damage.zone(0 if front else 4), damage.zone(2 if front else 6))
	return 1.0 - damage_power_loss * maxf(centre, 0.5 * sides)


func reset_to(xf: Transform3D) -> void:
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	global_transform = xf
	gear = 1
	steer = 0.0
	_shift_timer = 0.0
	_clutch_slipping = false
	for w in wheels:
		w.omega = 0.0
	_accel_key = 0.0
	_brake_key = 0.0
	_steer_key = 0.0


# --- setup helpers -----------------------------------------------------------------------

func _relative_transform(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Body collision: convex hull of the body meshes (wheels excluded, they are rays), so the
## rounded corners and the real sill height (356: 0.19 m) are kept.
func _build_collision(model: Node3D) -> void:
	var points := PackedVector3Array()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if _is_wheel_part(mi.name) or mi.mesh == null:
			continue
		var xf := _relative_transform(mi, model)
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				points.append(xf * p)
	var col := CollisionShape3D.new()
	if points.is_empty():
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 1.0, 4.0)
		col.shape = box
		col.position = Vector3(0.0, 0.7, 0.0)
	else:
		var hull := ConvexPolygonShape3D.new()
		hull.points = points
		col.shape = hull
	add_child(col)


func _is_wheel_part(node_name: String) -> bool:
	for prefix in ["WheelFront", "WheelRear", "WheelShadow", "Tread"]:
		if node_name.begins_with(prefix):
			return true
	return false


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
	w.ray.position = center + Vector3.UP * bump_travel
	w.ray.target_position = Vector3.DOWN * (bump_travel + droop_travel + wheel_radius)
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
	_update_damage()
	_update_gearbox(delta)
	var engaged := _shift_timer <= 0.0
	var gearing := _gear_ratio() * final_drive
	var engine_torque := 0.0
	if engaged:
		engine_torque = _engine_torque() * throttle
		if throttle < 0.05:
			engine_torque = -engine_brake * torque_peak * rpm / redline
	# Engine inertia seen at the wheels; shared by the driven wheels (open differential).
	var driven := 0
	for w in wheels:
		if _drive_share(w) > 0.0:
			driven += 1
	var engine_inertia_at_wheel := 0.0
	if engaged and driven > 0:
		engine_inertia_at_wheel = engine_inertia * gearing * gearing / driven
	for w in wheels:
		_update_contact(w, delta)
	for w in wheels:
		var share := _drive_share(w)
		var torque := engine_torque * gearing * (drivetrain_efficiency if engine_torque > 0.0 else 1.0) * share
		_apply_wheel(w, delta, torque, wheel_inertia + (engine_inertia_at_wheel if share > 0.0 else 0.0))
	var v := linear_velocity
	var drag := drag_area * (1.0 + damage_drag_gain * (damage.total() if damage != null else 0.0))
	apply_central_force(-v * v.length() * 0.5 * AIR_DENSITY * drag)
	_update_telemetry(delta)


func _read_input(delta: float) -> void:
	var accel_raw := Input.get_action_strength("accelerate")
	var brk_raw := Input.get_action_strength("brake")
	var steer_raw := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var accel := accel_raw
	var brk := brk_raw
	var steer_input := steer_raw
	if digital_input:
		# In reverse the keys swap roles, so each key ramps as the pedal it currently drives.
		var accel_is_brake := gear == -1
		_accel_key = _ramp(_accel_key, accel_raw, brake_rise_time if accel_is_brake else throttle_rise_time,
			brake_fall_time if accel_is_brake else throttle_fall_time, delta)
		_brake_key = _ramp(_brake_key, brk_raw, throttle_rise_time if accel_is_brake else brake_rise_time,
			throttle_fall_time if accel_is_brake else brake_fall_time, delta)
		accel = _accel_key
		brk = _brake_key
		var away := absf(steer_raw) > absf(_steer_key) and signf(steer_raw) == signf(_steer_key) or _steer_key == 0.0
		var turn_time := lerpf(steer_time_slow, steer_time_fast, clampf(absf(forward_speed) / steer_fast_speed, 0.0, 1.0))
		_steer_key = move_toward(_steer_key, steer_raw, delta / (turn_time if away else steer_return_time))
		steer_input = _steer_key
	handbrake = Input.is_action_pressed("handbrake")
	if gear == -1:
		throttle = brk
		brake = accel
		if accel_raw > 0.1 and forward_speed > -0.5:
			gear = 1
	else:
		throttle = accel
		brake = brk
		if brk_raw > 0.1 and accel_raw < 0.1 and absf(forward_speed) < 0.5:
			gear = -1  # arcade style: holding brake at standstill reverses
	var lock := deg_to_rad(max_steer_deg) * (1.0 - damage_steer_loss * (damage.zone(1) if damage != null else 0.0))
	var target := steer_input * lock
	if steering_assist:
		target = _assisted_steer(target, lock)
	steer = move_toward(steer, target, steer_rate * delta)


## Moves a key's pedal value towards the key state: rise_time from 0 to 1, fall_time back.
func _ramp(value: float, target: float, rise_time: float, fall_time: float, delta: float) -> float:
	var time := rise_time if target > value else fall_time
	return move_toward(value, target, delta / maxf(time, 0.001))


## Steering assist: keeps the front wheels within assist_margin x peak slip angle of the
## direction the front axle actually travels, so full lock means "as much grip as there is"
## and countersteering in a slide still works. Fades in between 2 and 6 m/s.
func _assisted_steer(target: float, lock: float) -> float:
	var front_offset := Vector3.ZERO
	var n := 0
	for w in wheels:
		if w.front:
			front_offset += w.center
			n += 1
	if n > 0:
		front_offset /= n
	var v := global_basis.inverse() * (linear_velocity + angular_velocity.cross(global_basis * (front_offset - center_of_mass)))
	if -v.z < 0.5:
		return target  # standing or reversing
	var travel := atan2(-v.x, -v.z)  # front axle heading relative to the car, positive = left
	var window := peak_slip_angle * assist_margin
	var assisted := clampf(target, travel - window, travel + window)
	var blend := clampf((-v.z - 2.0) / 4.0, 0.0, 1.0)
	return clampf(lerpf(target, assisted, blend), -lock, lock)


## Share of the drive torque for one wheel (two wheels per axle).
func _drive_share(w: Wheel) -> float:
	return (front_drive_share if w.front else 1.0 - front_drive_share) / 2.0


func _gear_ratio() -> float:
	if gear == -1:
		return reverse_ratio
	return gear_ratios[gear - 1]


func _update_gearbox(delta: float) -> void:
	_shift_timer = maxf(_shift_timer - delta, 0.0)
	# Engine speed follows the driven wheels (the clutch slips below idle).
	var omega := 0.0
	var driven := 0
	for w in wheels:
		if _drive_share(w) > 0.0 and not w.detached:
			omega += w.omega
			driven += 1
	if driven > 0:
		omega /= driven
	var wheel_rpm := absf(omega * _gear_ratio() * final_drive) * 60.0 / TAU
	_since_shift += delta
	if gear > 0 and _shift_timer <= 0.0 and _since_shift > 1.0:
		var ratio := gear_ratios[gear - 1]
		if gear < gear_ratios.size():
			# Up when the next gear gives at least as much wheel torque (or at the limiter).
			var next := gear_ratios[gear]
			if wheel_rpm > redline * 0.95 or (wheel_rpm > redline * 0.6 and throttle > 0.5
					and _torque_at(wheel_rpm * next / ratio) * next >= _torque_at(wheel_rpm) * ratio):
				_shift(gear + 1)
		if gear > 1 and _shift_timer <= 0.0 and wheel_rpm < redline * 0.5 \
				and wheel_rpm * gear_ratios[gear - 2] / ratio < redline * 0.8:
			_shift(gear - 1)
		if _shift_timer > 0.0:
			wheel_rpm *= _gear_ratio() / ratio  # the gear just selected
	_update_engine_speed(delta, clampf(wheel_rpm, IDLE_RPM, redline))


## Engine speed. Locked to the driven wheels while the clutch is engaged; during a shift the
## clutch is open and the engine falls off throttle (upshift) or is blipped up (downshift)
## towards the new gear's speed, then the closing clutch pulls it the rest of the way.
func _update_engine_speed(delta: float, target: float) -> void:
	if _shift_timer > 0.0:
		var rate := rev_drop_rate if target < rpm else rev_rise_rate
		rpm = move_toward(rpm, target, rate * delta)
	elif _clutch_slipping:
		rpm = move_toward(rpm, target, clutch_sync_rate * delta)
		_clutch_slipping = absf(rpm - target) > 1.0
	else:
		rpm = target


func _shift(to: int) -> void:
	gear = to
	_shift_timer = shift_time
	_clutch_slipping = true
	_since_shift = 0.0


func _engine_torque() -> float:
	if rpm >= redline:
		return 0.0  # rev limiter
	return _torque_at(rpm) * engine_health()


## Full-throttle torque (Nm) at engine speed r, from the .sim curve.
func _torque_at(r: float) -> float:
	if torque_curve.is_empty():
		return 0.0
	var f := r / 500.0
	var i := mini(int(f), torque_curve.size() - 1)
	var j := mini(i + 1, torque_curve.size() - 1)
	return lerpf(torque_curve[i], torque_curve[j], f - float(i))


func _update_contact(w: Wheel, delta: float) -> void:
	# Cast now, from the current body transform: the node's own result is a couple of physics
	# ticks old, which at speed put the contact behind the wheel and let the body sink.
	if w.detached:
		w.contact = false
		w.compression = 0.0
		w.compression_speed = 0.0
		return
	w.ray.force_raycast_update()
	w.contact = w.ray.is_colliding()
	if not w.contact:
		w.compression = 0.0
		w.compression_speed = 0.0
		return
	w.point = w.ray.get_collision_point()
	w.normal = w.ray.get_collision_normal()
	var compression := bump_travel + droop_travel + wheel_radius - w.ray.global_position.distance_to(w.point)
	w.compression_speed = (compression - w.compression) / delta
	w.compression = compression


func _apply_wheel(w: Wheel, delta: float, drive_torque: float, inertia: float) -> void:
	if w.detached:
		w.normal_load = 0.0
		w.force = Vector2.ZERO
		w.slip_ratio = 0.0
		w.slip_angle = 0.0
		return
	var brake_torque := brake * brake_decel_g * mass * GRAVITY * wheel_radius \
		* (brake_front_bias if w.front else 1.0 - brake_front_bias) / 2.0
	var abs_on := brake_assist and (w.front or not handbrake)
	var abs_limit := (abs_slip if w.front else abs_slip_rear) * peak_slip_ratio
	if handbrake and not w.front:
		brake_torque = maxf(brake_torque, mass * GRAVITY * wheel_radius)
	if throttle < 0.05 and absf(forward_speed) < 0.5:
		brake_torque = maxf(brake_torque, 0.3 * mass * GRAVITY * wheel_radius / 4.0)  # hold at standstill
	if not w.contact:
		w.normal_load = 0.0
		w.force = Vector2.ZERO
		w.slip_ratio = 0.0
		w.slip_angle = 0.0
		w.omega = _spin_wheel(w.omega, drive_torque, brake_torque, inertia, delta)
		w.spin = fmod(w.spin + w.omega * delta, TAU)
		_update_visual(w)
		return
	# Preloaded spring: carries a quarter of the weight at the model's ride height (lift 0).
	var lift := w.compression - droop_travel
	var wheel_load := mass * GRAVITY / 4.0 + spring_rate * lift + damper_rate * w.compression_speed
	var stop_start := bump_travel * 0.75
	if lift > stop_start:
		wheel_load += spring_rate * bump_stop_rate * (lift - stop_start)
	if w.partner != null:
		var bar := anti_roll_front if w.front else anti_roll_rear
		wheel_load += spring_rate * bar * (w.compression - w.partner.compression)
	w.normal_load = maxf(wheel_load, 0.0)
	var normal := w.normal
	var offset := w.point - global_position
	apply_force(normal * w.normal_load, offset)

	# A wobbling wheel also shakes the car: its toe swings with the turn of the wheel.
	var wheel_basis := global_basis * Basis(Vector3.UP, (steer if w.front else 0.0) + w.toe + 0.3 * w.wobble * sin(w.spin))
	var fwd := (-wheel_basis.z).slide(normal).normalized()
	var right := wheel_basis.x.slide(normal).normalized()
	var v := linear_velocity + angular_velocity.cross(offset)
	var v_long := v.dot(fwd)
	var v_lat := v.dot(right)
	var static_load := mass * GRAVITY / 4.0
	var load_factor := 1.0 - load_sensitivity * (w.normal_load / static_load - 1.0)
	var max_force := mu * (1.0 if w.front else rear_grip) * w.grip_factor * clampf(load_factor, 0.5, 1.2) * w.normal_load
	# Slip angle with a speed floor: at a standstill the tyre acts as a stiff damper.
	w.slip_angle = atan2(v_lat, maxf(absf(v_long), 3.0))
	var slip_y := tan(w.slip_angle) / tan(peak_slip_angle)
	var rolling := rolling_resistance * w.normal_load * clampf(v_long / 0.5, -1.0, 1.0)
	# Wheel spin in substeps with the body velocity held: the tyre force reacts on the wheel.
	var steps := maxi(wheel_substeps, 1)
	var h := delta / steps
	var f := Vector2.ZERO
	for i in steps:
		var slip := (w.omega * wheel_radius - v_long) / maxf(absf(v_long), 2.0)
		var tyre := _tyre_force(slip, slip_y, max_force)
		var braking := brake_torque
		if abs_on and absf(v_long) > 1.0 and slip * signf(v_long) < -abs_limit:
			braking = 0.0  # ABS: release this substep, the wheel spins back up
		w.omega = _spin_wheel(w.omega, drive_torque - tyre.x * wheel_radius, braking, inertia, h)
		f += tyre
	f /= steps
	w.slip_ratio = (w.omega * wheel_radius - v_long) / maxf(absf(v_long), 2.0)
	f.x -= rolling
	apply_force(fwd * f.x + right * f.y, offset)
	w.force = f
	w.spin = fmod(w.spin + w.omega * delta, TAU)
	_update_visual(w)


## Combined tyre force (x along the wheel, y to its right) from slip ratio and normalised lateral
## slip: one slip vector, rising to the peak at length 1, then falling to slide_grip.
func _tyre_force(slip_ratio: float, slip_y: float, max_force: float) -> Vector2:
	var slip := Vector2(slip_ratio / peak_slip_ratio, slip_y)
	var s := slip.length()
	if s < 1e-6:
		return Vector2.ZERO
	var shape := s * (2.0 - s) if s < 1.0 else lerpf(1.0, slide_grip, clampf((s - 1.0) / 2.0, 0.0, 1.0))
	return Vector2(slip.x, -slip.y) / s * shape * max_force


## Integrates wheel speed: net torque, then brakes as friction that stops but never reverses it.
func _spin_wheel(omega: float, torque: float, brake_torque: float, inertia: float, h: float) -> float:
	omega += torque / inertia * h
	var brake_step := brake_torque / inertia * h
	if absf(omega) <= brake_step:
		return 0.0
	return omega - signf(omega) * brake_step


func _update_visual(w: Wheel) -> void:
	var lift := w.compression - droop_travel
	var steer_basis := Basis(Vector3.UP, (steer if w.front else 0.0) + w.toe)
	var spin_basis := Basis(Vector3.RIGHT, -w.spin)
	# A bent wheel leans (camber) and wobbles: its axle tilt circles once per turn.
	var side := -1.0 if w.center.x < 0.0 else 1.0
	var wobble_basis := Basis(Vector3.BACK, side * w.wobble * 0.5 + w.wobble * sin(w.spin)) \
		* Basis(Vector3.UP, w.wobble * cos(w.spin))
	for i in w.visuals.size():
		var rest := w.rest[i]
		w.visuals[i].transform = Transform3D(steer_basis * wobble_basis * spin_basis * rest.basis, rest.origin + Vector3.UP * lift)


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
		"assist": steering_assist,
		"abs": brake_assist,
		"damage": _damage_summary(),
		"lat_g": snappedf(local.x / GRAVITY, 0.001),
		"long_g": snappedf(-local.z / GRAVITY, 0.001),
	}


func _damage_summary() -> Dictionary:
	if damage == null:
		return {}
	return {"front": maxf(damage.zone(1), maxf(damage.zone(0), damage.zone(2))),
		"rear": maxf(damage.zone(5), maxf(damage.zone(4), damage.zone(6))),
		"left": damage.zone(7), "right": damage.zone(3), "roof": damage.zone(8),
		"engine": 1.0 - engine_health(),
		"lost": damage.detached_count() + wheels.filter(func(w: Wheel) -> bool: return w.detached).size(),
		"loose": damage.hinged_count()}
