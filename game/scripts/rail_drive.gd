class_name RailDrive
extends RefCounted
## Low quality (D-052): an opponent drives on its line like the original's AI cars (docs/opponents.md),
## without wheels, tyres or gearbox. AIDriver still plans the speed and the passing offset; this
## moves the car there by setting the body's velocities, so it stays a Jolt body that the player
## and the other cars collide with. The original's control cascade (AI/TRAFCFG.DAT, "in control"):
## the lateral offset asks for a lateral speed, the lateral speed error for a lateral acceleration,
## and the heading follows the direction of travel. The gains are our own: the units of TRAFCFG's
## values are not decoded. The car is held at its ride height over the road (no gravity, no
## springs) and its speed follows the target at the acceleration its engine, gears and tyres allow
## (drive_accel) or at the brakes' deceleration. Two rays find the road under the axles (four wheel
## rays and the suspension in full physics).
##
## Out of control: a hit (a body contact pushing sideways or lengthways above HIT_IMPULSE, a car or
## a wall) hands the car to the full physics (Car with AIDriver's pedals and wheel, as in full
## quality), like the original's softer "out of control" set. Once the car runs calmly near its
## line again for CALM_TIME, or after a reset onto the line, it goes back on the rail.
## Rail cars do not jump: on a crest they stay on the road.

const LAT_POS_GAIN := 1.5  ## 1/s, lateral speed asked per m off the target offset (TRAFCFG dlpos_to_dlvel)
const MAX_LAT_SPEED := 4.0  ## m/s (TRAFCFG max_dlvel)
const LAT_SPEED_GAIN := 6.0  ## 1/s, lateral acceleration per m/s of lateral speed error (TRAFCFG dlvel_to_clacc)
const LAT_GRIP_SHARE := 0.5  ## largest lateral acceleration (beside the curve), share of mu g
const TURN_GAIN := 8.0  ## 1/s, angular speed per rad the heading is off (TRAFCFG dangle_to_dav)
const MAX_TURN_SPEED := 3.0  ## rad/s
const HEIGHT_GAIN := 10.0  ## 1/s, vertical speed per m off the ride height
const PROBE_UP := 1.0  ## m above the ride height a ground ray starts (a kerb up to this high is climbed)
const PROBE_DOWN := 1.5  ## m below the ground it looks
const HIT_IMPULSE := 0.3  ## N s per kg of the car (a speed change in m/s): a hit hands the car to the full physics
const MIN_FREE_TIME := 2.0  ## s at least under the full physics after a hit
const CALM_TIME := 1.0  ## s of calm driving before the car goes back on the rail
const CALM_OFFSET := 1.0  ## m off the target offset still calm
const CALM_ANGLE_DEG := 8.0  ## heading off the line still calm
const CALM_TURN := 0.6  ## rad/s of yaw rate off the line's still calm
const ROLLING := 0.015  ## rolling resistance, times the weight
const DRIVE_AXLE_SHARE := 0.55  ## weight on a two wheel drive's driven axle while accelerating

var car: Car
var driver: AIDriver
var active := false  ## on the rail now; false = the full physics drives
var hits := 0  ## times a hit took the car off the rail
var _speed := 0.0  ## m/s along the line
var _lat_speed := 0.0  ## m/s across it (the line's own frame: a curve does not add to it)
var _ride := 0.4  ## m from the ground to the body's origin at rest
var _free_time := 0.0
var _calm_time := 0.0
var _wheelbase := 2.4
var _front_z := -1.2  ## car space z of the front axle
var _rear_z := 1.2
var _query: PhysicsRayQueryParameters3D


class Frame:
	var origin := Vector3.ZERO
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	var up := Vector3.UP


func _init(driven: Car, ai: AIDriver) -> void:
	car = driven
	driver = ai
	var lowest := INF
	var front := 0.0
	var rear := 0.0
	for w in car.wheels:
		lowest = minf(lowest, w.center.y - car.wheel_radius)
		if w.front:
			front = w.center.z
		else:
			rear = w.center.z
	if lowest < INF:
		_ride = -lowest
	if front != rear:
		_wheelbase = absf(rear - front)
		_front_z = front
		_rear_z = rear
	_query = PhysicsRayQueryParameters3D.new()
	_query.exclude = [car.get_rid()]
	_query.hit_back_faces = false
	if not car.wheels.is_empty():
		_query.collision_mask = car.wheels[0].ray.collision_mask


## Puts the car on the rail, keeping its speed along the line.
func enter() -> void:
	active = true
	car.on_rail = true
	car.gravity_scale = 0.0
	var f := _frame()
	_speed = maxf(car.linear_velocity.dot(f.forward), 0.0)
	_lat_speed = clampf(car.linear_velocity.dot(f.right), -MAX_LAT_SPEED, MAX_LAT_SPEED)
	_calm_time = 0.0
	for w in car.wheels:
		w.ray.enabled = false


## Hands the car to the full physics: wheels spinning with the road, springs at rest.
func leave() -> void:
	active = false
	car.on_rail = false
	car.gravity_scale = 1.0
	_free_time = 0.0
	_calm_time = 0.0
	for w in car.wheels:
		w.ray.enabled = not w.detached
		w.omega = car.forward_speed / car.wheel_radius
		w.travel = 0.0
		w.travel_speed = 0.0


## Every tick while on the rail, after AIDriver planned target_speed and pass_offset.
func step(delta: float) -> void:
	if car.hit_impulse > HIT_IMPULSE * car.mass:
		hits += 1
		leave()
		return
	var f := _frame()
	if car.held:
		_speed = 0.0
		# Start line: clutch down, the engine revs freely at the launch throttle (Car._update_gearbox).
		car.gear = 1
		car.throttle = 0.6
		var free := lerpf(Car.IDLE_RPM, car.redline, car.throttle)
		car.rpm = move_toward(car.rpm, free, car.rev_rise_rate * delta)
	else:
		var target := driver.target_speed
		var up_hill := -f.forward.y * Car.GRAVITY
		if target > _speed:
			var a := drive_accel(_speed) * driver.throttle_share + up_hill
			_speed = minf(_speed + maxf(a, 0.0) * delta, target) if a > 0.0 else maxf(_speed + a * delta, 0.0)
			car.throttle = driver.throttle_share
		else:
			var decel := minf(car.brake_decel_g, car.mu) * Car.GRAVITY
			_speed = maxf(move_toward(_speed, target, decel * delta), 0.0)
			car.throttle = 0.0
		_update_engine()
	# Lateral cascade: offset -> lateral speed -> lateral acceleration.
	var lateral := (car.global_position - f.origin).dot(f.right)
	var want := clampf(LAT_POS_GAIN * (driver.pass_offset - lateral), -MAX_LAT_SPEED, MAX_LAT_SPEED)
	var lat_max := LAT_GRIP_SHARE * car.mu * Car.GRAVITY
	_lat_speed += clampf(LAT_SPEED_GAIN * (want - _lat_speed), -lat_max, lat_max) * delta
	if _speed < 0.5:
		_lat_speed = 0.0
	var lat_speed := _lat_speed
	# The road surface under the axles: kerbs and squares off the slices' plane (Monte Carlo's
	# crossings lie higher than the slices) would catch the body.
	var plane := f.origin + f.right * lateral
	var front := _ground(_front_z, plane, f)
	var rear := _ground(_rear_z, plane, f)
	var along := front - rear
	along -= f.right * along.dot(f.right)
	var up := f.up
	if along.length_squared() > 0.25:
		up = f.right.cross(along.normalized())
		if up.dot(f.up) < 0.0:
			up = -up
	f.up = up
	f.forward = (f.forward - up * f.forward.dot(up)).normalized()
	var height := ((front + rear) * 0.5 + up * _ride - car.global_position).dot(up)
	car.linear_velocity = f.forward * _speed + f.right * lat_speed + up * height * HEIGHT_GAIN
	# Heading along the travel, upright on the road.
	var travel := f.forward * _speed + f.right * lat_speed
	var heading := travel.normalized() if _speed > 0.5 else f.forward
	var want_basis := Basis.looking_at(heading, f.up)
	var turn := (want_basis * car.global_basis.inverse()).orthonormalized().get_rotation_quaternion()
	var angle := turn.get_angle()
	if angle > PI:
		angle -= TAU
	var spin := turn.get_axis() * angle * TURN_GAIN if absf(angle) > 1e-5 else Vector3.ZERO
	# Plus the line's own yaw rate, so the heading does not lag behind in a hairpin.
	var k: float = driver.curvature[driver.slice] * driver.turn_side[driver.slice]
	spin -= up * k * _speed
	car.angular_velocity = spin.limit_length(MAX_TURN_SPEED)
	_update_wheels(delta, f)
	car.odometer_m += _speed * delta


## Road surface below the car's axle at `z` (car space): a ray down along the road's up, the
## point on the slices' plane (`plane`, beside the line where the car is) when it finds no road.
func _ground(z: float, plane: Vector3, f: Frame) -> Vector3:
	var at := car.global_transform * Vector3(0.0, 0.0, z)
	var fallback := at + f.up * (plane - at).dot(f.up)
	_query.from = at + f.up * PROBE_UP
	_query.to = at - f.up * (_ride + PROBE_DOWN)
	var hit := car.get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty() or hit["collider"] is Car or (hit["normal"] as Vector3).dot(f.up) < 0.7:
		return fallback
	return hit["position"]


## Every tick under the full physics: back on the rail after a calm CALM_TIME near the line.
func watch(delta: float) -> void:
	_free_time += delta
	var f := _frame()
	var lateral := (car.global_position - f.origin).dot(f.right)
	var off := rad_to_deg((-car.global_basis.z).angle_to(f.forward))
	var yaw := absf(car.angular_velocity.dot(f.up))
	var grounded := car.wheels.all(func(w: Car.Wheel) -> bool: return w.contact or w.detached)
	var calm := grounded and car.side_contacts == 0 and absf(lateral - driver.pass_offset) < CALM_OFFSET \
		and off < CALM_ANGLE_DEG and yaw < CALM_TURN + absf(car.forward_speed * driver.curvature[driver.slice])
	_calm_time = _calm_time + delta if calm else 0.0
	if _free_time >= MIN_FREE_TIME and _calm_time >= CALM_TIME:
		enter()


## m/s2 the engine can give at `speed` along a level road: the best gear's wheel force (the clutch
## slips in first gear below the launch revs), at most the driven tyres' grip, less drag and rolling.
func drive_accel(speed: float) -> float:
	var force := 0.0
	for g in car.gear_ratios.size():
		var r := _engine_rpm(speed, g + 1)
		if r > car.redline:
			continue
		force = maxf(force, car._torque_at(maxf(r, car.launch_rpm)) * car.gear_ratios[g] * car.final_drive / car.wheel_radius)
	force *= car.drivetrain_efficiency * car.drivetrain_health() * car.engine_health() * car.power_scale
	var driven := 1.0 if car.front_drive_share > 0.0 and car.front_drive_share < 1.0 else DRIVE_AXLE_SHARE
	force = minf(force, car.mu * Car.GRAVITY * car.mass * driven)
	var drag := 0.5 * Car.AIR_DENSITY * car.drag_area * speed * speed
	return (force - drag) / car.mass - ROLLING * Car.GRAVITY


func _engine_rpm(speed: float, gear: int) -> float:
	return speed / car.wheel_radius * car.gear_ratios[gear - 1] * car.final_drive * 60.0 / TAU


## Gear with the most wheel torque at this speed (a racing driver's), engine speed from it.
func _update_engine() -> void:
	var best := car.gear
	var best_force := -1.0
	for g in car.gear_ratios.size():
		var r := _engine_rpm(_speed, g + 1)
		if r > car.redline * 0.98:
			continue
		var force := car._torque_at(maxf(r, Car.IDLE_RPM)) * car.gear_ratios[g]
		if g + 1 == car.gear:
			force *= 1.05  # keep the gear unless another is clearly better
		if force > best_force:
			best_force = force
			best = g + 1
	car.gear = best
	car.rpm = clampf(_engine_rpm(_speed, best), Car.IDLE_RPM, car.redline)


## Wheels roll with the speed and the front ones turn into the line's curve; the contacts the
## shadow and the sounds read lie on the road under them.
func _update_wheels(delta: float, f: Frame) -> void:
	var k: float = driver.curvature[driver.slice] * driver.turn_side[driver.slice]
	car.steer = -atan(_wheelbase * k) if _speed > 0.5 else 0.0
	var omega := _speed / car.wheel_radius
	for w in car.wheels:
		if w.detached:
			continue
		w.omega = omega
		w.spin = fmod(w.spin + omega * delta, TAU)
		w.slip_ratio = 0.0
		w.slip_angle = 0.0
		w.travel = 0.0
		w.contact = true
		w.point = car.to_global(Vector3(w.center.x, w.center.y - car.wheel_radius, w.center.z))
		w.normal = f.up
		car._update_visual(w)


## The line where the car is: the point on it beside the car, the direction along it and the
## road's right and up there, blended between the car's slice and the next one.
func _frame() -> Frame:
	var road := driver.road
	var i := driver.slice
	var j := road.ahead(i, 1)
	var a := driver.line[i]
	var b := driver.line[j]
	var seg := b - a
	var t := clampf((car.global_position - a).dot(seg) / maxf(seg.length_squared(), 1e-4), 0.0, 1.0)
	var k := road.ahead(j, 1)
	var dir_i := seg.normalized() if seg.length_squared() > 1e-4 else road.forwards[i]
	var dir_j := (driver.line[k] - b).normalized() if k != j else dir_i
	var forward := dir_i.lerp(dir_j, t).normalized()
	var up := road.ups[i].lerp(road.ups[j], t)
	var right := forward.cross(up).normalized()
	if right.dot(road.rights[i]) < 0.0:
		right = -right
	var f := Frame.new()
	f.origin = a + seg * t
	f.forward = forward
	f.right = right
	f.up = (up - forward * up.dot(forward)).normalized()
	return f
