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
## Traffic: a car ahead in the same lane (`others`; the cars' widths overlap sideways, measured from
## the line on each car's slice) caps the target speed at its speed plus a term on the gap beyond
## FOLLOW_GAP + follow_time of the own speed, so the field queues up instead of running into each
## other. Passing: a car ahead is passed when it drives slower than this driver could drive at that
## place of the track (its own profile there, on the line moved beside the car: inside a corner the
## line is tighter, see _offset_factor) by at least pass_speed_margin, and it holds this driver up
## (it follows it, closes in on it by PASS_DIFF, or the car nearly stands). The profile carries the
## driver's skill (grip_use, brake_use), so a better driver passes more often; pass_speed_margin is
## how eager it is. An AI car that is speeding up at its own limit (the start), queuing behind another
## car or passing one is not passed: the car ahead of it is (the whole queue at once). With a car
## (nearly) standing on the road ahead, moving cars are not passed, only the standing one. The
## driver shifts its whole line sideways (pass_offset, at PASS_RATE) to PASS_MARGIN_MOVING beside
## the car (PASS_MARGIN beside one that nearly stands; its size counted as it stands, across the road
## it is wider), on the side with room on the road
## (the side it already took while that is still possible), and back once the car is a car length
## behind. The room must last from here to PASS_AHEAD slices past the car (the road may narrow), or
## the driver stays behind (a pass already alongside goes on). Passing is close and may touch.
## A car that nearly stands (below PASS_CRAWL) with too little room on both sides is squeezed past
## on the side with more and pushed: the driver drives into it PUSH_SPEED faster than it moves,
## slow enough that the impact stays under the damage threshold (CarDamage.threshold). Racecraft
## (defending, side by side) is step D.

const LOOK_TIME := 0.7  ## s of the current speed to the steering target (TRAFCFG look_ahead_factor)
const PASS_LOOK_TIME := 0.4  ## same while passing: pure pursuit cuts corners by about look^2 x curvature / 2, beside a car that matters
const MIN_LOOK := 10.0  ## m
const MAX_LOOK := 35.0  ## m
const CURVE_SPANS := [2, 3, 4]  ## slices between the three line points a radius is measured on; the tightest counts
const REACTION := 0.4  ## s of the current speed the pedals look ahead on the profile
const MIN_REACTION := 8.0  ## m
const MIN_BRAKE_SHARE := 0.3  ## share of the deceleration still planned where cornering takes all the grip
const SLIDE_LIFT_DEG := 4.0  ## slide angle where the throttle starts being cut back
const SLIDE_OFF_DEG := 10.0  ## slide angle with the throttle shut
const FOLLOW_RANGE := 60.0  ## m ahead other cars are looked at
const FOLLOW_WIDTH := 2.4  ## m sideways (in the car's frame) a car ahead counts as in the lane, plus FOLLOW_SPREAD per m ahead
const FOLLOW_SPREAD := 0.05  ## the lane widens ahead: a car in a curve ahead is off to the side
const FOLLOW_GAP := 6.0  ## m kept from centre to centre beyond CAR_LENGTH at a standstill
const FOLLOW_GAIN := 0.5  ## m/s of speed per m the gap is off
const CAR_LENGTH := 4.5  ## m
const HALF_WIDTH := 0.9  ## m, half a car's width (the 356 is 1.66 m wide)
const LANE_MARGIN := 0.2  ## m two cars side by side must be apart beyond their sizes not to block each other
const PASS_MARGIN := 0.6  ## m left between the cars when passing one that nearly stands (close: they may touch)
const PASS_MARGIN_MOVING := 1.0  ## m left beside a moving car (the line is followed to a few tenths)
const PASS_RANGE := 30.0  ## m ahead a slow car is passed from, plus PASS_TIME of the own speed
const PASS_TIME := 1.5  ## s
const PASS_DIFF := 3.0  ## m/s faster than a car ahead this driver must be closing in to pass it (unless it follows it)
const PASS_AHEAD := 15  ## slices past the car being passed the room beside it must last
const MIN_OFFSET_FACTOR := 0.5  ## lowest share of the profile speed left on a line moved inside a tight corner
const PASS_RATE := 2.5  ## m/s the line shifts sideways
const PASS_CRAWL := 3.0  ## m/s allowed close behind a car being passed, to get round it; a car slower than this may be pushed
const EDGE_MARGIN := 0.6  ## m kept from the road edge when passing
const PUSH_SPEED := 1.5  ## m/s faster than a car that cannot be passed: pushes it aside without damage
const MAX_SPEED := 120.0  ## m/s, cap of the corner speed on straights
const STUCK_SPEED := 1.0  ## m/s
const STUCK_TIME := 4.0  ## s below STUCK_SPEED (not held) before a reset
const OFF_ROAD := 4.0  ## m past the road's half width, measured from the line
const OFF_ROAD_TIME := 3.0  ## s
const UPSIDE_TIME := 2.0  ## s with the roof closer to the ground than the wheels
const TRACK_WINDOW := 10  ## slices searched ahead for the car's slice every tick
const LOST_DISTANCE := 30.0  ## m from the line at the tracked slice: search the whole road again
const OTHER_WINDOW := 40  ## slices ahead along the road another car is looked for
const OTHER_OFF_LINE := 12.0  ## m from the line a car may be and still count as on the road ahead

@export var grip_use := 0.8  ## share of the tyres' friction planned for in corners (skill)
@export var brake_use := 0.8  ## share of the possible deceleration planned for braking
@export var follow_time := 0.5  ## s of the own speed added to the gap kept behind a car
## m/s a car ahead must be slower than this driver could drive there for it to try a pass (eagerness).
@export var pass_speed_margin := 2.0
@export var speed_gain := 0.5  ## throttle per m/s below the target speed
@export var brake_gain := 0.35  ## brake per m/s above the target speed
@export var steer_gain := 1.0  ## times the pure pursuit wheel angle
@export var yaw_gain := 2.0  ## wheel angle per wheelbase x curvature the car turns too little (P)
@export var yaw_integral_gain := 1.5  ## same, per second the error lasts (I)

var car: Car
var road: Road
var enabled := true
## Pace of the race around the player (RaceRubberBand). The speed profile times pace is the same as
## grip_use and brake_use times pace^2, without building it again. throttle_share eases the
## throttle on top (a driver waiting does not floor it on straights, where the profile does not limit).
var pace := 1.0
var throttle_share := 1.0
var passes_waiting := false  ## passes cars waiting for the player too: this car is the player's (main.gd drive_by_ai)
var slice := 0  ## road slice the car is on
var target_speed := 0.0  ## m/s, this tick
var resets := 0  ## times the car was put back on the line
var reset_reason := ""  ## why the last reset happened: stuck, off road, upside down
var line_offsets := PackedFloat32Array()  ## m along the slice's right vector
var line := PackedVector3Array()  ## line point on every slice
var curvature := PackedFloat32Array()  ## 1/m of the line at every slice
var turn_side := PackedFloat32Array()  ## +1 the corner's centre is to the right of the line, -1 left
var corner_speed := PackedFloat32Array()  ## m/s the line's radius allows at every slice
var speed_limit := PackedFloat32Array()  ## m/s, the profile: corner speeds and the braking into them
var slide_deg := 0.0  ## angle between the car's heading and its travel, this tick
var others: Array[Car] = []  ## the other cars on the track (the own car is skipped)
var following: Car  ## car ahead that limits the speed this tick, null = none
var passing: Car  ## car being passed, null = none
var pass_offset := 0.0  ## m the line is shifted sideways now (+ = right), for passing
var pass_target := 0.0  ## m the line is moving to (pass_offset follows at PASS_RATE)
var pushing: Car  ## slow car with no room beside it, pushed out of the way; null = none
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
	turn_side.resize(n)
	turn_side.fill(1.0)
	for span: int in CURVE_SPANS:
		for i in n:
			var b := road.ahead(i, span)
			var c := road.ahead(b, span)
			if b == i or c == b:
				continue
			var k := 1.0 / _radius(line[i], line[b], line[c])
			if k > curvature[b]:
				curvature[b] = k
				# The chord's middle lies towards the centre of the circle.
				turn_side[b] = 1.0 if ((line[i] + line[c]) * 0.5 - line[b]).dot(road.rights[b]) >= 0.0 else -1.0
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
	_plan_pass(delta)
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
	# Waiting behind a car is not being stuck (pushing one that does not move is).
	var waiting := following != null and following != pushing
	_stuck_time = _stuck_time + delta if speed < STUCK_SPEED and not waiting else 0.0
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
	var look := clampf(speed * (PASS_LOOK_TIME if passing != null else LOOK_TIME), MIN_LOOK, MAX_LOOK)
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
			return _shifted(i).lerp(_shifted(j), clampf(left / maxf(step_length[i], 0.01), 0.0, 1.0))
		left -= step_length[i]
		i = j
	return _shifted(i)


## Line point on slice i moved sideways by the passing offset.
func _shifted(i: int) -> Vector3:
	return line[i] + road.rights[i] * pass_offset


func _pedals() -> void:
	var speed := car.forward_speed
	# The profile from here to the reaction distance ahead: the lowest speed in it is the target,
	# its end is where the brake must have brought the car to.
	var reach := maxf(speed * REACTION, MIN_REACTION)
	var allowed := speed_limit[slice] * pace * _offset_factor(slice, pass_offset)
	var dist := 0.0
	var i := slice
	while dist < reach:
		var j := road.ahead(i, 1)
		if j == i:
			break
		dist += step_length[i]
		i = j
		allowed = minf(allowed, speed_limit[i] * pace * _offset_factor(i, pass_offset))
	target_speed = minf(allowed, _follow_limit(speed))
	var error := target_speed - speed
	var end_limit := speed_limit[i] * pace * _offset_factor(i, pass_offset)
	var need := (speed * speed - end_limit * end_limit) / (2.0 * maxf(dist, 1.0))  # m/s2
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
	car.auto_throttle = minf(throttle, maxf(left, 0.2)) * calm * throttle_share


## Highest speed that keeps the gap to the nearest car ahead in the lane (INF: none). A car blocks
## the lane when the two cars' widths overlap sideways (from the line on each car's slice; a car
## turned across the road is wider). The car being passed may be approached at PASS_CRAWL while
## there is room behind it, but no faster than lets the line get beside it in time (PASS_RATE
## over the gap); the one being pushed at PUSH_SPEED faster than it moves.
func _follow_limit(speed: float) -> float:
	var limit := INF
	following = null
	var own := _lateral(car.global_position, slice)
	for other in others:
		if other == car or other == null:
			continue
		var local := car.to_local(other.global_position)
		var ahead := -local.z
		if ahead <= 0.0 or ahead > FOLLOW_RANGE:
			continue
		var at := _slice_ahead_of(other)
		if at < 0:
			continue  # not on the road ahead (a street beside, under or across this one)
		var other_lat := _lateral(other.global_position, at)
		if other == passing and absf(pass_target - pass_offset) < 0.1:
			# The line is beside it: the plan counts, a few tenths off it is not a reason to brake
			# (braking hard would push the car further off it); the bare widths still must not overlap.
			if absf(other_lat - pass_offset) > _half_size(other, at) + HALF_WIDTH and absf(other_lat - own) > _half_size(other, at) + HALF_WIDTH:
				continue
		elif absf(other_lat - own) > _half_size(other, at) + HALF_WIDTH + LANE_MARGIN:
			continue
		# Gap and speed along the road: round a hairpin the car ahead drives across or against this
		# car's heading, but it still gets away.
		ahead = _along_road(other, at)
		if ahead <= 0.0 or ahead > FOLLOW_RANGE:
			continue
		var other_speed := other.linear_velocity.dot(road.forwards[at])
		var gap := ahead - CAR_LENGTH - (FOLLOW_GAP + maxf(speed, 0.0) * follow_time)
		var keep := maxf(other_speed + FOLLOW_GAIN * gap, 0.0)
		if other == pushing:
			keep = maxf(keep, maxf(other_speed, 0.0) + PUSH_SPEED)
		elif other == passing:
			if ahead - CAR_LENGTH > 1.5:
				keep = maxf(keep, PASS_CRAWL)
			var shift := absf(pass_target - pass_offset)
			if shift > 0.1:
				keep = minf(keep, maxf(maxf(other_speed, 0.0) + maxf(ahead - CAR_LENGTH, 0.0) * PASS_RATE / shift, PASS_CRAWL))
		if keep < limit:
			limit = keep
			following = other
	return limit


## Share of the profile speed left on slice i with the line moved `offset` m sideways (+ = right).
## Moved to the inside of a corner the line's radius is smaller (1/k - offset), so the speed drops;
## on the outside the radius is larger, but the profile is kept (the braking points are not moved).
func _offset_factor(i: int, offset: float) -> float:
	var inside := maxf(offset * turn_side[i], 0.0)
	return sqrt(clampf(1.0 - curvature[i] * inside, MIN_OFFSET_FACTOR * MIN_OFFSET_FACTOR, 1.0))


## m sideways from the line on slice i (+ = right).
func _lateral(pos: Vector3, i: int) -> float:
	return (pos - line[i]).dot(road.rights[i])


## m sideways from its centre a car on slice i takes up: half its width when it points along the
## road, half its length when it stands across.
func _half_size(other: Car, i: int) -> float:
	var along := absf(other.global_basis.z.dot(road.forwards[i]))
	var across := sqrt(maxf(1.0 - along * along, 0.0))
	return along * HALF_WIDTH + across * CAR_LENGTH * 0.5


## Picks the car to pass and moves pass_offset beside it: on the side with room, or for a car that
## nearly stands squeezed against the edge with more room when neither has enough (then the car is
## also pushed). Without room beside a moving car the driver stays behind it.
func _plan_pass(delta: float) -> void:
	var speed := maxf(car.forward_speed, 0.0)
	var blocker: Car = null
	var blocker_ahead := INF
	var blocker_slice := slice
	var reach_ahead := PASS_RANGE + speed * PASS_TIME
	# AI cars ahead that are getting round or queuing behind another car are not passed themselves:
	# the car they are held up by is, also a little beyond the usual range (no swerve back to the
	# line between the two).
	var held_by := {}
	# A car (nearly) standing on the road ahead: no passing of moving cars into it, only round it.
	var standing_ahead := false
	for other in others:
		if other != null and other != car and other.linear_velocity.length() < PASS_CRAWL:
			var ahead := -car.to_local(other.global_position).z
			if ahead > 0.0 and ahead < reach_ahead + FOLLOW_RANGE and _slice_ahead_of(other) >= 0:
				standing_ahead = true
		var other_driver := other.get_node_or_null("AIDriver") as AIDriver if other != null and other != car else null
		if other_driver != null and other_driver.enabled:
			var front := other_driver.passing if other_driver.passing != null else other_driver.following
			if front != null and front != car:
				held_by[other] = front
	for other in others:
		if other == car or other == null:
			continue
		var ahead := -car.to_local(other.global_position).z
		if ahead <= -CAR_LENGTH or ahead > (reach_ahead + FOLLOW_RANGE if held_by.values().has(other) else reach_ahead):
			continue
		var at := _slice_ahead_of(other)
		if at < 0:
			continue  # not on the road ahead (a street beside, under or across this one)
		if held_by.has(other) and ahead > CAR_LENGTH * 0.5:
			continue  # held up by another car (and not yet alongside): pass that one
		if standing_ahead and other.linear_velocity.length() >= PASS_CRAWL and ahead > CAR_LENGTH * 0.5:
			continue
		if other != passing and other != pushing:
			# A new car to pass: in the shifted lane and slower than this driver could go there.
			if ahead <= 0.0 or absf(_lateral(other.global_position, at) - pass_offset) > _half_size(other, at) + HALF_WIDTH + LANE_MARGIN:
				continue
			var other_speed := other.linear_velocity.length()
			var beside := _half_size(other, at) + HALF_WIDTH + _pass_margin(other)
			var own_there := speed_limit[at] * pace * minf(_offset_factor(at, beside), _offset_factor(at, -beside))
			if other_speed > own_there - pass_speed_margin:
				continue
			var other_driver := other.get_node_or_null("AIDriver") as AIDriver
			if other_driver != null and other_driver.enabled and other_driver.following == null and other_driver.target_speed > other_speed + 2.0:
				continue  # an AI car speeding up as fast as it can (the start): nothing to gain
			if not passes_waiting and other_driver != null and other_driver.enabled and other_driver.pace < 1.0:
				continue  # waiting for the player (RaceRubberBand): the group stays in order until the player comes
			if other_speed > speed - PASS_DIFF and other != following and other_speed > STUCK_SPEED * 2.0:
				continue
		if ahead < blocker_ahead:
			blocker = other
			blocker_ahead = ahead
			blocker_slice = at
	passing = null
	pushing = null
	var target := 0.0
	if blocker != null:
		var lat := _lateral(blocker.global_position, blocker_slice)
		var reach := _half_size(blocker, blocker_slice) + HALF_WIDTH + _pass_margin(blocker)
		if absf(lat) >= reach and absf(pass_offset) < 0.1:
			blocker = null  # the line itself goes past it
	if blocker != null:
		var lat := _lateral(blocker.global_position, blocker_slice)
		var reach := _half_size(blocker, blocker_slice) + HALF_WIDTH + _pass_margin(blocker)
		var edges := _room(slice, road.ahead(blocker_slice, PASS_AHEAD))
		var side := _pass_side(blocker, lat, reach, edges, _lateral(car.global_position, slice))
		target = clampf(lat + side * reach, edges.x, edges.y)
		if blocker.linear_velocity.length() < PASS_CRAWL:
			if absf(target - lat) < reach - _pass_margin(blocker):
				pushing = blocker  # squeezed: not enough room beside a car that nearly stands
		elif absf(target - lat) < reach - 0.05 and blocker_ahead > CAR_LENGTH * 0.5:
			blocker = null  # a moving car with no room beside it for the whole pass: stay behind it
			target = 0.0
		passing = blocker
	pass_target = target
	pass_offset = move_toward(pass_offset, target, PASS_RATE * delta)


## Usable road on slice i, sideways from the line: (left edge, right edge) less EDGE_MARGIN.
func _edges(i: int) -> Vector2:
	var centre := -line_offsets[i]
	var half := _half_width(i)
	if absf(centre) > half:
		centre = 0.0  # the line runs beside the slices (Monte Carlo): its own road
	return Vector2(centre - half + EDGE_MARGIN, centre + half - EDGE_MARGIN)


## Slice of `other` on the road ahead of this car (up to OTHER_WINDOW slices), -1 when it is not
## near the line there: a car on another part of the track that happens to be close (hairpins,
## streets side by side, bridges) does not count as ahead.
func _slice_ahead_of(other: Car) -> int:
	var at := road.nearest_ahead(other.global_position, slice, OTHER_WINDOW)
	return at if line[at].distance_to(other.global_position) < OTHER_OFF_LINE else -1


## m along the road from this car to `other` on slice `at` (ahead of this car's slice).
func _along_road(other: Car, at: int) -> float:
	var dist := 0.0
	var i := slice
	for n in OTHER_WINDOW:
		if i == at:
			break
		var j := road.ahead(i, 1)
		if j == i:
			break
		dist += step_length[i]
		i = j
	return dist + (other.global_position - line[at]).dot(road.forwards[at]) - (car.global_position - line[slice]).dot(road.forwards[slice])


## m to leave beside `other` when passing it: more beside a moving car.
func _pass_margin(other: Car) -> float:
	return PASS_MARGIN if other.linear_velocity.length() < PASS_CRAWL else PASS_MARGIN_MOVING


## Usable road (as _edges) on every slice from `first` to `last` along the road: the narrowest.
func _room(first: int, last: int) -> Vector2:
	var room := _edges(first)
	var i := first
	for n in 200:
		if i == last:
			break
		var j := road.ahead(i, 1)
		if j == i:
			break
		i = j
		var e := _edges(i)
		room = Vector2(maxf(room.x, e.x), minf(room.y, e.y))
	return room


## +1 (right) or -1 (left): the side to pass `other` (sideways `lat`) on, `reach` from its centre.
## The side this car is on (sideways `own`) while it has room, so it never cuts across the other
## car's nose; else the side with room; with room on neither, the one with more.
func _pass_side(_other: Car, lat: float, reach: float, edges: Vector2, own: float) -> float:
	var right_room := edges.y - lat
	var left_room := lat - edges.x
	var here := 1.0 if own >= lat else -1.0
	if (here > 0.0 and right_room >= reach) or (here < 0.0 and left_room >= reach):
		return here
	if right_room >= reach or left_room >= reach:
		return 1.0 if right_room >= reach else -1.0
	return 1.0 if right_room >= left_room else -1.0
