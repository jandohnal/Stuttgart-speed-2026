class_name AIDriver
extends Node
## Opponent driver (D-026): drives a Car through its pedals and steering wheel (Car.auto_drive),
## so it has the same physics, grip and damage as the player.
##
## Line: the original's racing line (<track>_ai.json from tools/ai_lines.py: lateral offset from
## each road slice), taken as it is: where a layout uses a street beside the SimD slices (Monte
## Carlo) the line runs up to 26 m from them, and the slices lead into the barriers.
## Steering: pure pursuit towards a point on the line LOOK_TIME seconds ahead (MIN_LOOK..MAX_LOOK
## m; the original's TRAFCFG looks 12..30 m ahead), plus feedback on the yaw rate: the tyres need
## a slip angle on top of the geometric wheel angle, more so near the grip limit, and the car
## turns less than the arc asks. Speed: a profile along the line, built once: the corner speed
## sqrt(mu g R) from the line's radius, lowered by braking back from every corner at the deceleration
## the brakes allow and the grip leaves beside the cornering force (friction circle). The pedals
## follow the profile a reaction time ahead: the brake by the deceleration it asks for plus a P term
## on the speed, the throttle by the speed error, cut back while the tyres are busy cornering and
## when the car slides (a rear-engined 356 spins on full throttle in a corner). Recovery: a car that
## is stuck, off the road or on its roof is put back on the line, like the player's reset key.

const LOOK_TIME := 0.7  ## s of the current speed to the steering target (TRAFCFG look_ahead_factor)
const MIN_LOOK := 10.0  ## m
const MAX_LOOK := 35.0  ## m
const CURVE_SPANS := [2, 3, 4]  ## slices between the three line points a radius is measured on; the tightest counts
const REACTION := 0.4  ## s of the current speed the pedals look ahead on the profile
const MIN_REACTION := 8.0  ## m
const MIN_BRAKE_SHARE := 0.3  ## share of the deceleration still planned where cornering takes all the grip
const SLIDE_LIFT_DEG := 4.0  ## slide angle where the throttle starts being cut back
const SLIDE_OFF_DEG := 10.0  ## slide angle with the throttle shut
const MAX_SPEED := 120.0  ## m/s, cap of the corner speed on straights
const STUCK_SPEED := 1.0  ## m/s
const STUCK_TIME := 4.0  ## s below STUCK_SPEED (not held) before a reset
const OFF_ROAD := 4.0  ## m past the road's half width, measured from the line
const OFF_ROAD_TIME := 3.0  ## s
const UPSIDE_TIME := 2.0  ## s with the roof closer to the ground than the wheels
const TRACK_WINDOW := 10  ## slices searched ahead for the car's slice every tick
const LOST_DISTANCE := 30.0  ## m from the line at the tracked slice: search the whole road again

@export var grip_use := 0.8  ## share of the tyres' friction planned for in corners (skill)
@export var brake_use := 0.8  ## share of the possible deceleration planned for braking
@export var speed_gain := 0.5  ## throttle per m/s below the target speed
@export var brake_gain := 0.35  ## brake per m/s above the target speed
@export var steer_gain := 1.0  ## times the pure pursuit wheel angle
@export var yaw_gain := 2.0  ## wheel angle per wheelbase x curvature the car turns too little (P)
@export var yaw_integral_gain := 1.5  ## same, per second the error lasts (I)

var car: Car
var road: Road
var enabled := true
var slice := 0  ## road slice the car is on
var target_speed := 0.0  ## m/s, this tick
var resets := 0  ## times the car was put back on the line
var reset_reason := ""  ## why the last reset happened: stuck, off road, upside down
var line_offsets := PackedFloat32Array()  ## m along the slice's right vector
var line := PackedVector3Array()  ## line point on every slice
var curvature := PackedFloat32Array()  ## 1/m of the line at every slice
var corner_speed := PackedFloat32Array()  ## m/s the line's radius allows at every slice
var speed_limit := PackedFloat32Array()  ## m/s, the profile: corner speeds and the braking into them
var slide_deg := 0.0  ## angle between the car's heading and its travel, this tick
var step_length := PackedFloat32Array()  ## m from a slice's line point to the next one's

var _wheelbase := 2.4
var _stuck_time := 0.0
var _off_time := 0.0
var _upside_time := 0.0
var _yaw_integral := 0.0  ## wheelbase x curvature error, summed over time


## ai_data: the track's _ai.json (null or empty: the road centre); line_index: 0 or 1.
func setup(driven: Car, track_road: Road, ai_data: Variant, line_index := 0) -> void:
	car = driven
	road = track_road
	process_physics_priority = -1  # pedals set before the car reads them in the same tick
	car.auto_drive = true
	# Driver aids the player can choose are always on for the AI: it plans the limit, it does not
	# feel for it through the pedals.
	car.brake_assist = true
	car.traction_control = true
	var front := 0.0
	var rear := 0.0
	for w in car.wheels:
		if w.front:
			front = w.center.z
		else:
			rear = w.center.z
	if front != rear:
		_wheelbase = absf(rear - front)
	var offsets: Array = []
	if ai_data is Dictionary and ai_data.has("lines"):
		offsets = ai_data["lines"][clampi(line_index, 0, ai_data["lines"].size() - 1)]
	_build_line(offsets)
	slice = _nearest_line_point(car.global_position)


func _build_line(offsets: Array) -> void:
	var n := road.size()
	line_offsets.resize(n)
	line.resize(n)
	for i in n:
		var o := float(offsets[i]) if i < offsets.size() else 0.0
		line_offsets[i] = o
		line[i] = road.positions[i] + road.rights[i] * o
	step_length.resize(n)
	for i in n:
		var j := road.ahead(i, 1)
		step_length[i] = line[i].distance_to(line[j]) if j != i else 0.0
	curvature.resize(n)
	curvature.fill(0.0)
	for span: int in CURVE_SPANS:
		for i in n:
			var b := road.ahead(i, span)
			var c := road.ahead(b, span)
			if b == i or c == b:
				continue
			curvature[b] = maxf(curvature[b], 1.0 / _radius(line[i], line[b], line[c]))
	var grip := car.mu * Car.GRAVITY
	corner_speed.resize(n)
	for i in n:
		corner_speed[i] = minf(sqrt(grip * grip_use / maxf(curvature[i], 1e-6)), MAX_SPEED)
	# Braking back from every corner: passes against the road's direction until nothing changes
	# (a few, for the links between segments and the laps of a closed road).
	var decel := minf(car.brake_decel_g, car.mu) * Car.GRAVITY * brake_use
	speed_limit = corner_speed.duplicate()
	for sweep in 4:
		var changed := false
		for i in range(n - 1, -1, -1):
			var j := road.ahead(i, 1)
			var v := 0.0 if j == i else speed_limit[j]  # road ends: stop there
			var lateral := v * v * curvature[i] / grip
			var a := decel * maxf(sqrt(maxf(1.0 - lateral * lateral, 0.0)), MIN_BRAKE_SHARE)
			var limit := sqrt(v * v + 2.0 * a * step_length[i])
			if limit < speed_limit[i] - 0.01:
				speed_limit[i] = limit
				changed = true
		if not changed:
			break


## Half the drivable width at slice i. Which of the four SimD widths is which edge is not decoded
## yet; the widest of the first two is taken for both sides.
func _half_width(i: int) -> float:
	var w: Array = road.slices[i].get("widths", [])
	return maxf(float(w[0]), float(w[1])) if w.size() >= 2 else 4.0


## Radius of the circle through three points, measured in the horizontal plane.
static func _radius(a: Vector3, b: Vector3, c: Vector3) -> float:
	var p := Vector2(a.x, a.z)
	var q := Vector2(b.x, b.z)
	var r := Vector2(c.x, c.z)
	var cross := absf((q - p).cross(r - p))
	if cross < 1e-4:
		return INF
	return p.distance_to(q) * q.distance_to(r) * r.distance_to(p) / (2.0 * cross)


func _physics_process(delta: float) -> void:
	if not enabled or car == null or road == null or road.size() == 0:
		return
	_track(delta)
	if car.held:
		# Start line: brakes on, clutch down, engine at the launch revs.
		car.auto_throttle = 0.6
		car.auto_brake = 0.0
		car.auto_steer = 0.0
		return
	_steer(delta)
	_pedals()


func _track(delta: float) -> void:
	var pos := car.global_position
	slice = road.nearest_ahead(pos, slice, TRACK_WINDOW)
	if line[slice].distance_to(pos) > LOST_DISTANCE:
		slice = _nearest_line_point(pos)
	if car.held:
		_stuck_time = 0.0
		return
	var speed := car.linear_velocity.length()
	_stuck_time = _stuck_time + delta if speed < STUCK_SPEED else 0.0
	var lateral := absf((pos - line[slice]).dot(road.rights[slice]))
	_off_time = _off_time + delta if lateral > _half_width(slice) + OFF_ROAD else 0.0
	_upside_time = _upside_time + delta if car.global_basis.y.dot(road.ups[slice]) < 0.2 else 0.0
	if _stuck_time > STUCK_TIME:
		reset_on_line("stuck")
	elif _off_time > OFF_ROAD_TIME:
		reset_on_line("off road %.1f m" % lateral)
	elif _upside_time > UPSIDE_TIME:
		reset_on_line("upside down")


func _nearest_line_point(pos: Vector3) -> int:
	var best := 0
	var best_dist := INF
	for i in line.size():
		var d := line[i].distance_squared_to(pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best


## Puts the car back on the line at its slice, standing (the player's reset key).
func reset_on_line(reason := "") -> void:
	reset_reason = reason
	car.reset_to(road.transform_at(slice, line_offsets[slice]))
	_stuck_time = 0.0
	_off_time = 0.0
	_upside_time = 0.0
	resets += 1


func _steer(delta: float) -> void:
	var speed := maxf(car.forward_speed, 0.0)
	var look := clampf(speed * LOOK_TIME, MIN_LOOK, MAX_LOOK)
	var target := _point_ahead(look)
	var local := car.to_local(target)
	var dist2 := maxf(local.length_squared(), 1.0)
	# Pure pursuit: the arc through the target point; positive = left (car front is -Z).
	var curvature := -2.0 * local.x / dist2
	var angle := atan(_wheelbase * curvature) * steer_gain
	if speed > 3.0:
		# The curvature the car actually drives, from its yaw rate.
		var turning := car.angular_velocity.dot(car.global_basis.y) / speed
		var error := _wheelbase * (curvature - turning)
		_yaw_integral = clampf(_yaw_integral + error * delta, -0.1, 0.1)
		angle += yaw_gain * error + yaw_integral_gain * _yaw_integral
	else:
		_yaw_integral = 0.0
	car.auto_steer = clampf(angle / deg_to_rad(car.max_steer_deg), -1.0, 1.0)


## Point on the line `distance` m ahead of the car's slice.
func _point_ahead(distance: float) -> Vector3:
	var i := slice
	var left := distance
	for n in 200:
		var j := road.ahead(i, 1)
		if j == i or step_length[i] >= left:
			return line[i].lerp(line[j], clampf(left / maxf(step_length[i], 0.01), 0.0, 1.0))
		left -= step_length[i]
		i = j
	return line[i]


func _pedals() -> void:
	var speed := car.forward_speed
	# The profile from here to the reaction distance ahead: the lowest speed in it is the target,
	# its end is where the brake must have brought the car to.
	var reach := maxf(speed * REACTION, MIN_REACTION)
	var allowed := speed_limit[slice]
	var dist := 0.0
	var i := slice
	while dist < reach:
		var j := road.ahead(i, 1)
		if j == i:
			break
		dist += step_length[i]
		i = j
		allowed = minf(allowed, speed_limit[i])
	target_speed = allowed
	var error := target_speed - speed
	var need := (speed * speed - speed_limit[i] * speed_limit[i]) / (2.0 * maxf(dist, 1.0))  # m/s2
	var flat := car.linear_velocity - car.global_basis.y * car.linear_velocity.dot(car.global_basis.y)
	slide_deg = rad_to_deg(flat.angle_to(-car.global_basis.z)) if flat.length() > 3.0 else 0.0
	# Grip the cornering already uses is not there for braking or driving the wheels, and a car
	# sliding past SLIDE_LIFT_DEG gets its pedals eased so the rear tyres can grip again.
	var lateral := absf(speed * car.angular_velocity.dot(car.global_basis.y)) / (car.mu * Car.GRAVITY)
	var left := sqrt(maxf(1.0 - lateral * lateral, 0.0))
	var calm := clampf((SLIDE_OFF_DEG - slide_deg) / (SLIDE_OFF_DEG - SLIDE_LIFT_DEG), 0.0, 1.0)
	if error < -0.5 or need > 0.5:
		car.auto_throttle = 0.0
		var brake_max := car.brake_decel_g * Car.GRAVITY
		var brake := clampf(maxf(need, 0.0) / brake_max + maxf(-error, 0.0) * brake_gain, 0.0, 1.0)
		var grip_brake := car.mu * Car.GRAVITY / brake_max * maxf(left, MIN_BRAKE_SHARE)
		car.auto_brake = minf(brake, grip_brake * lerpf(MIN_BRAKE_SHARE, 1.0, calm))
		return
	car.auto_brake = 0.0
	var throttle := clampf(0.3 + error * speed_gain, 0.0, 1.0) if error >= 0.0 else 0.2
	car.auto_throttle = minf(throttle, maxf(left, 0.2)) * calm
