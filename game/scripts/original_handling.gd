class_name OriginalHandling
extends RefCounted
## The original's driving model (D-046), reimplemented from its description in
## docs/formats/sim.md ("Jízdní model originálu"): a grip model in fixed ticks with forces as
## accelerations. Each tick it reads the car's velocity, works out the wheel loads (static share,
## transfer from the last tick's acceleration, downforce), the engine and gearbox (revs in fixed
## steps), the brakes and the force of every tyre (side force from the slip angle up to the wheel's
## capacity, friction circle, locked or spinning wheels sliding), and changes the car's velocity
## and yaw rate directly. Jolt only carries the car on its springs and handles collisions.
## Constants come from the exe (tools/handling_exe.py, GameData/Simulation/handling.json, D-023);
## the car's values from its .sim entry in cars.json after parts (CarParts), in file units.

const FILE := "GameData/Simulation/handling.json"
const FULL_INPUT := 127  ## steering input range of the original, +-
const KEY_STEER_STEP := 12  ## steering units per tick towards the key's target (keyboard)
const STEER_PULL_MAX := 64  ## steering units the side slope of the road may pull
const BYTE := 255.0  ## pedal range of the original
const PEDAL_FULL := 252.0  ## pedal value that counts as fully pressed
const HARD_BRAKE := 0xEB  ## pedal value over which a wheel without ABS may lock
const SLOPE_BRAKE := 0x40  ## pedal value from which braking holds the car on a slope
const SHIFT_FAST := 5  ## shift delay (ticks) under which the gearbox is a race one
const SPIN_DIVISOR := 4.0  ## a spinning rear wheel keeps 1 - 1/this of its grip
const ASPHALT := 1  ## surface row of asphalt
const ABS_PULSE_TICKS := 4  ## with ABS a hard braked slow wheel locks one tick in this many
const NEUTRAL_ROLL := 0.99  ## speed kept per tick rolling in neutral
const NEUTRAL_ROLL_FAST := 0.998  ## same, fast and nearly straight
const NEUTRAL_FAST_STEER := 32  ## steering units under which "nearly straight"
const HANDBRAKE_STOP := 0.5  ## speed kept per tick when the handbrake holds a near standstill
const DAMAGE_SCALE := 100.0  ## the original's damage units at Car's full damage (1.0)
const RANDOM_MISFIRE := 1.0

var k: Dictionary = {}  ## constants from the exe
var surface_dry: Array = []
var surface_wet: Array = []
var slide_divisor: Array = []
var blip_light: Array = []
var blip_braking: Array = []

# Car values (.sim after parts, converted like the original's loader).
var grip := 1.0  ## 0x0F4
var front_grip := 0.5  ## 0x0F0 share
var transfer := 0.25  ## 0x0F8 share
var stiffness := 1.0  ## 0x11C
var lateral_split := 1.0  ## 0x130
var steer_lock := 12.0  ## 0x0FC, angle units
var toe := 0.0  ## 0x100
var brake_decel := 6.5  ## 0x104, m/s2
var brake_front := 0.6  ## 0x108 share
var downforce_front := 0.001  ## 0x10C x 0.001
var downforce_rear := 0.001
var engine_brake := 0.2  ## 0x098 share
var shift_delay := 8  ## 0x054 ticks
var drive_front := 0.0  ## 0x05C share
var redline := 6000.0
var torque_curve := PackedFloat32Array()  ## lb-ft per 500 rpm, as in the file
var rpm_per_speed := PackedFloat32Array()  ## by gear index (0 reverse, 1 neutral, 2.. forward): rpm per m/s
var drive_factor := PackedFloat32Array()  ## m/s2 per lb-ft, by gear index
var speed_per_rpm := PackedFloat32Array()  ## 1 / rpm_per_speed, by gear index
var drag := 0.0  ## m/s2 per (m/s)^3
var half_lever := 1.0  ## yaw lever of the original (angle units)
var tyre_type := 0  ## 0 road, 1 rain, 2 race
var pitch_per_accel := 0.004  ## 0x128 x 0.001
var roll_per_accel := 0.003
var pitch_keep := 0.85  ## 0x114
var roll_keep := 0.85
var pitch_limit := 1.0
var roll_limit := 1.0
var simple := false  ## the original's simplified handling (not used by the game: kept for reference)
var wet := false
var abs_on := false
var tc_on := false
var automatic := true
var allow_reverse := true  ## holding the brake at a standstill selects reverse (not for the AI)

# State.
var gear := 2  ## 0 reverse, 1 neutral, 2.. forward
var prev_gear := 1
var shift_ticks := 0  ## ticks left of the current shift
var downshift := false
var pedals_swapped := false  ## reverse selected by holding the brake: the pedals swap
var rpm := 0.0
var limiter_ticks := 0
var spin_flag := 0  ## 2: the engine just spun the driven wheels
var steer_units := 0  ## current steering, +-127, positive left
var accel_long := 0.0  ## last tick, m/s2, positive forwards
var accel_lat := 0.0  ## positive to the right
var skid: Array[float] = [0.0, 0.0, 0.0, 0.0]  ## per wheel 0..1, for sound and smoke
var cap: Array[float] = [0.0, 0.0, 0.0, 0.0]  ## wheel force capacity, m/s2
var steer_angle := 0.0  ## front wheel angle, rad (positive left)
var pitch := 0.0  ## visual body pitch, rad (nose down positive)
var roll := 0.0
var tick_count := 0
var _rng := RandomNumberGenerator.new()
var _slip := 0.0  ## drift, sideways / forward speed (the original's 0xDC0)


## Loads the exe constants; false when the data is missing (the switch then stays off).
static func available() -> bool:
	return OriginalAssets.available(FILE)


func _init(car_params: Dictionary) -> void:
	var data: Variant = OriginalAssets.load_json(FILE)
	if not data is Dictionary:
		return
	k = data["constants"]
	surface_dry = data["surface_grip"]["dry"]
	surface_wet = data["surface_grip"]["wet"]
	slide_divisor = data["slide_divisor"]
	blip_light = data["downshift_blip"]["light"]
	blip_braking = data["downshift_blip"]["braking"]
	_rng.seed = 5
	_load_car(car_params)


func is_ready() -> bool:
	return not k.is_empty()


## The car's values the way the original's loader converts them (0x49C6C0, 0x49CB50).
func _load_car(p: Dictionary) -> void:
	var u: Dictionary = p.get("unknown", {})
	var pct: float = k["percent"]
	var milli: float = k["milli"]
	var mass := float(p["mass_kg"])
	grip = float(u.get("0x0F4", 1.15)) * float(p.get("tyre_grip_factor", 1.0))
	front_grip = float(u.get("0x0F0", 48.5)) * pct
	transfer = float(u.get("0x0F8", 25.0)) * pct
	stiffness = maxf(float(u.get("0x11C", 1.0)), 0.01)
	lateral_split = maxf(float(u.get("0x130", 1.0)), 0.01)
	steer_lock = float(u.get("0x0FC", 12.0))
	toe = float(u.get("0x100", 0.0))
	brake_decel = float(u.get("0x104", 6.5))
	brake_front = float(u.get("0x108", 60.0)) * pct
	downforce_front = float(u.get("0x10C", 1.0)) * milli
	downforce_rear = float(u.get("0x110", 1.0)) * milli
	engine_brake = float(u.get("0x098", 20.0)) * pct
	shift_delay = int(u.get("0x054", 8))
	pitch_keep = float(u.get("0x114", 85.0)) * pct
	roll_keep = float(u.get("0x118", 85.0)) * pct
	pitch_per_accel = float(u.get("0x128", 4.0)) * milli
	roll_per_accel = float(u.get("0x12C", 3.0)) * milli
	pitch_limit = float(u.get("0x134", 1.0))
	roll_limit = float(u.get("0x138", 1.0))
	drive_front = float(p.get("front_torque_split_pct", 0.0)) * pct
	redline = float(p["redline_rpm"])
	tyre_type = int(p.get("tyre_type", 0))
	torque_curve = PackedFloat32Array(p["torque_curve_lbft_per_500rpm"])
	var efficiency := float(u.get("0x058", 90.0)) * pct
	var tyre: Dictionary = p["tyre"]
	var circumference := (float(tyre["rim_in"]) * float(k["rim_mm"]) + float(tyre["aspect_pct"])
		* float(k["sidewall_scale"]) * float(tyre["width_mm"])) * float(k["circumference"])
	var final := float(p["final_drive"])
	var ratios: Array[float] = [float(p["reverse_ratio"]), 0.0]
	for r: float in p["gears"]:
		ratios.append(r)
	for r in ratios:
		var per := r * final * float(k["rpm_per_minute"]) / circumference
		rpm_per_speed.append(per)
		speed_per_rpm.append(1.0 / per if per != 0.0 else 0.1)
		drive_factor.append(per / mass * float(k["force_scale"]) * efficiency)
	# Air drag: at the top speed the top gear's torque at that speed just covers it.
	var vmax := float(p["top_speed_mph"]) * float(k["mph"])
	var top := rpm_per_speed.size() - 1
	if vmax > 0.0:
		drag = _torque_at(vmax * rpm_per_speed[top]) * drive_factor[top] / (vmax * vmax * vmax)
	var wheelbase := float(p.get("wheelbase_mm", 2300.0)) * milli
	half_lever = wheelbase * 0.5 * float(k["lever_scale"]) * float(k["angle_turn"])
	gear = 2 if automatic else 1


func top_gear() -> int:
	return rpm_per_speed.size() - 1


## Torque curve of the file (lb-ft) at engine speed r, linear between the 500 rpm points.
func _torque_at(r: float) -> float:
	if torque_curve.is_empty() or r < 0.0:
		return 0.0
	var f := r * float(k["torque_step"])
	var i := int(f)
	if i >= torque_curve.size() - 1:
		return torque_curve[torque_curve.size() - 1] if i == torque_curve.size() - 1 else 0.0
	return lerpf(torque_curve[i], torque_curve[i + 1], f - float(i))


## One tick of the original's model. Inputs: pedals 0..1, steering -1 (right) .. 1 (left),
## digital = keyboard (the steering ramps), handbrake; v_long / v_lat (m/s, forwards / right),
## yaw rate (rad/s, positive left), up_y / fwd_y / right_y: the world up components of the car's
## axes; wheels_on: [front, rear] on the ground; damage: Car's 0..1 values {"engine", "drive",
## "brakes", "aero", "wheels": [fl, fr, rl, rr]}. Returns {"long", "lat"} (m/s2, car axes) and
## "yaw" (rad/s change for this tick); the caller applies them.
func step(throttle_in: float, brake_in: float, steer_in: float, digital: bool, handbrake: bool,
		v_long: float, v_lat: float, yaw_rate: float, up_y: float, fwd_y: float, right_y: float,
		wheels_on: Array, damage: Dictionary) -> Dictionary:
	tick_count += 1
	var speed := Vector2(v_long, v_lat).length()
	# Drift: sideways against forward speed (the original's 0xDC0), over 5 m/s forwards.
	_slip = v_lat / v_long if v_long > float(k["downforce_speed"]) else 0.0
	var wheel_damage: Array = damage.get("wheels", [0.0, 0.0, 0.0, 0.0])
	var throttle_byte := roundi(clampf(throttle_in, 0.0, 1.0) * BYTE)
	var brake_byte := roundi(clampf(brake_in, 0.0, 1.0) * BYTE)
	_select_direction(throttle_byte, brake_byte, speed)
	if pedals_swapped:
		var t := throttle_byte
		throttle_byte = brake_byte
		brake_byte = t
	if shift_ticks > 0:
		shift_ticks -= 1
	var throttle := minf(throttle_byte / PEDAL_FULL, 1.0)
	var brake := minf(brake_byte / PEDAL_FULL, 1.0)
	var front_on: bool = wheels_on[0]
	var rear_on: bool = wheels_on[1]

	# Steering: the keys move the wheel in fixed steps per tick, an analog input goes straight.
	var target := roundi(clampf(steer_in, -1.0, 1.0) * FULL_INPUT)
	if digital:
		steer_units += clampi(target - steer_units, -KEY_STEER_STEP, KEY_STEER_STEP)
	else:
		steer_units = target
	# The road's side slope pulls the steering downhill, a damaged front pulls to its side.
	var pull := clampi(roundi(float(k["gravity"]) * right_y * float(k["camber_pull"])), -STEER_PULL_MAX, STEER_PULL_MAX)
	var dmg_fl := float(wheel_damage[0]) * DAMAGE_SCALE
	var dmg_fr := float(wheel_damage[1]) * DAMAGE_SCALE
	var steer_now := clampi(steer_units + pull + roundi((dmg_fr - dmg_fl) * float(k["damage_pull"])), -FULL_INPUT, FULL_INPUT)
	var lock := steer_lock
	if speed < float(k["steer_low_speed"]):
		lock *= float(k["steer_low_base"]) - speed * float(k["steer_low_per_ms"])
	lock = minf(lock, float(k["steer_lock_cap"]))
	var angle := [0.0, 0.0]  # angle units, front left / right
	for i in 2:
		var d := dmg_fl if i == 0 else dmg_fr
		angle[i] = (float(steer_now) + (toe if i == 0 else -toe)) * (1.0 - d * float(k["steer_damage"])) \
			* lock * float(k["steer_input_scale"])
		if v_long > float(k["steer_high_speed"]):
			angle[i] /= v_long * float(k["steer_high_div"])
	steer_angle = (angle[0] + angle[1]) * 0.5 * float(k["steer_unit"]) * TAU

	# Engine and gearbox: drive acceleration with the air drag taken off.
	var drive := _engine(throttle, throttle_byte, brake_byte, v_long, speed, rear_on, damage)
	if not front_on and not rear_on:
		accel_long = 0.0
		accel_lat = 0.0
		for i in 4:
			skid[i] = 0.0
		return {"long": 0.0, "lat": 0.0, "yaw": 0.0}

	# Brakes: deceleration from the pedal, never more than stops the car this tick.
	var brake_acc := (1.0 - float(damage.get("brakes", 0.0)) * DAMAGE_SCALE * float(k["damage_grip"])) * brake_decel * brake
	brake_acc = minf(brake_acc, absf(v_long) * float(k["velocity_gain"]))
	if v_long > 0.0:
		brake_acc = -brake_acc
	var brake_f := brake_acc * brake_front

	_wheel_loads(up_y, throttle_byte, v_long, damage)
	var cmd: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var front_sum := cap[0] + cap[1]
	var rear_sum := cap[2] + cap[3]
	for i in 4:
		var share := drive_front if i < 2 else 1.0 - drive_front
		var axle := front_sum if i < 2 else rear_sum
		cmd[i] = drive * share * cap[i] / axle if axle > 0.0 else 0.0
		cmd[i] += (brake_f if i < 2 else brake_acc - brake_f) * 0.5

	# Velocity of every wheel as the acceleration that would take half of it away in one tick.
	var gain := float(k["velocity_gain"]) * float(k["velocity_share"])
	var yaw_turns := yaw_rate / TAU
	var lever_speed: float
	if speed >= float(k["yaw_slip_speed"]):
		lever_speed = (speed + float(k["yaw_slip_fast_add"])) * float(k["yaw_slip_fast_mul"])
	else:
		lever_speed = (speed + float(k["yaw_slip_slow_add"])) * float(k["yaw_slip_slow_mul"])
	var yaw_part := half_lever * yaw_turns * lever_speed
	var lat_sum := 0.0
	var long_sum := 0.0
	var front_lat := 0.0
	var rear_lat := 0.0
	var left_long := 0.0
	var right_long := 0.0
	for i in 4:
		var front := i < 2
		if (front and not front_on) or (not front and not rear_on):
			skid[i] = 0.0
			continue
		# The front axle moves left when the car yaws left, the rear right.
		var lat_v := v_lat - yaw_part if front else v_lat + yaw_part
		var f := _wheel(i, lat_v * gain, v_long * gain, cmd[i], angle[i] if front else 0.0,
			throttle, throttle_byte, brake_byte, speed, v_long, handbrake, float(wheel_damage[i]))
		lat_sum += f.x
		long_sum += f.y
		if front:
			front_lat += f.x
		else:
			rear_lat += f.x
		if i % 2 == 0:
			left_long += f.y
		else:
			right_long += f.y
	var a_lat := lat_sum
	var a_long := long_sum / grip
	# Slopes: half of gravity down a climb unless the brakes hold, the side slope only in a slide.
	if brake_byte < SLOPE_BRAKE:
		a_long += float(k["slope_long"]) * fwd_y
	if absf(v_lat) > 1.0 or up_y < float(k["slope_steep"]):
		a_lat += float(k["slope_lat"]) * right_y
	# Yaw: side force ahead of the centre against the force behind it, and the push of the left
	# wheels against the right ones, about the middle of the wheelbase.
	var moment := -(front_lat - rear_lat) / half_lever - (left_long - right_long) / half_lever
	var yaw_gain := float(k["yaw_gain_simple"] if simple else k["yaw_gain"])
	var yaw := moment * yaw_gain * TAU
	accel_long = a_long
	accel_lat = a_lat
	_body_motion()
	return {"long": a_long, "lat": a_lat, "yaw": yaw}


## Speed kept this tick by the original's slow-downs (a race car yawing off throttle, rolling in
## neutral, the handbrake holding a near standstill): x = velocity, y = yaw rate.
func slow_down(speed: float, v_long: float, yaw_rate: float, fwd_y: float, handbrake: bool) -> Vector2:
	if gear >= 2 and _last_throttle < float(k["drive_throttle_limit"]) and speed < float(k["steer_low_speed"]) \
			and grip > float(k["race_grip"]):
		return Vector2(1.0 - absf(yaw_rate / TAU) * float(k["race_yaw_slow"]), 1.0)
	if gear == 1 and absf(float(k["gravity"]) * fwd_y) < 0.5:
		var fast := absf(v_long) >= float(k["neutral_fast_speed"]) and absi(steer_units) <= NEUTRAL_FAST_STEER
		var keep := NEUTRAL_ROLL_FAST if fast else NEUTRAL_ROLL
		return Vector2(keep, keep)
	if handbrake and speed < 1.0:
		return Vector2(HANDBRAKE_STOP, 1.0)
	return Vector2.ONE


var _last_throttle := 0.0


## Reverse by holding the brake at a standstill, forwards again by the throttle (automatic).
func _select_direction(throttle_byte: int, brake_byte: int, speed: float) -> void:
	if not automatic or not allow_reverse:
		return
	var still := speed < float(k["still_speed"])
	if still and gear >= 2 and brake_byte > 0x80 and throttle_byte == 0 and not pedals_swapped:
		_shift_to(0)
		pedals_swapped = true
	elif still and gear == 0 and throttle_byte > 0x80 and pedals_swapped:
		_shift_to(2)
		pedals_swapped = false


func _shift_to(g: int) -> void:
	if g == gear:
		return
	downshift = g < gear and g >= 2
	prev_gear = gear
	gear = g
	shift_ticks = shift_delay


## Static share of every wheel, moved by the last tick's acceleration and by downforce (0x4A1900).
func _wheel_loads(up_y: float, throttle_byte: int, v_long: float, damage: Dictionary) -> void:
	var g := up_y * grip * float(k["gravity"])
	var table: Array = surface_wet if wet else surface_dry
	var type := tyre_type
	var row: Array = table[ASPHALT]
	var surface := float(row[clampi(type, 0, 2)])
	for i in 4:
		var share := front_grip if i < 2 else 1.0 - front_grip
		cap[i] = surface * share * g * 0.5
	var t := accel_long * transfer * float(k["transfer_scale"]) * g * float(k["transfer_long"]) / stiffness
	if throttle_byte != 0 and v_long > 0.0:
		t *= maxf(1.0 - absf(_slip) * float(k["transfer_slip_cut"]), 0.0)
	cap[0] -= t
	cap[1] -= t
	cap[2] += t
	cap[3] += t
	if simple:
		cap[0] *= float(k["simple_front_grip"])
		cap[1] *= float(k["simple_front_grip"])
	# Side transfer: the left wheels (0, 2) against the right ones (1, 3); one side gets it divided.
	var s := accel_lat * transfer * float(k["transfer_scale"]) * g * float(k["transfer_lat"]) / stiffness
	var split := s / lateral_split
	if s <= 0.0:
		cap[0] -= s
		cap[2] -= s
		cap[1] += split
		cap[3] += split
	else:
		cap[0] -= split
		cap[2] -= split
		cap[1] += s
		cap[3] += s
	if v_long > float(k["downforce_speed"]):
		var aero := 1.0 - float(damage.get("aero", 0.0)) * DAMAGE_SCALE * float(k["damage_grip"])
		for i in 4:
			cap[i] += aero * (downforce_front if i < 2 else downforce_rear) * v_long
	for i in 4:
		cap[i] = maxf(cap[i], 0.0)


## Force of one wheel (0x4A20D0, 0x4A1DC0, 0x4A1C70): lat_in / long_in are the wheel's
## velocity as acceleration (negative x velocity), cmd the drive and brake for it, angle the
## steering (angle units, positive left). Returns (lateral, longitudinal) in car axes, m/s2; the
## longitudinal one times the grip like the original's (the caller divides the sum).
func _wheel(i: int, lat_in: float, long_in: float, cmd: float, angle: float, throttle: float,
		throttle_byte: int, brake_byte: int, speed: float, v_long: float, handbrake: bool, damage: float) -> Vector2:
	var front := i < 2
	var c := cap[i]
	var turn := angle * float(k["steer_unit"]) * TAU
	var lat := lat_in
	var lon := long_in
	if turn != 0.0:
		# Into the wheel's axes: steered left, the wheel sees the car's motion to its right.
		lat = lat_in * cos(turn) + long_in * sin(turn)
		lon = long_in * cos(turn) - lat_in * sin(turn)
	var fx := cmd
	var braking := false
	var limit := float(k["drive_throttle_limit"])
	if fx < 0.0 and lon < 0.0 and (throttle <= limit or gear != 0):
		fx = maxf(fx, lon)  # a brake stops the wheel, never turns it backwards
		braking = true
	elif fx > 0.0 and lon > 0.0 and (throttle <= limit or gear < 2):
		fx = minf(fx, lon)
		braking = true
	fx *= grip
	var slide := false
	if (braking and absf(fx) > c) or (not front and handbrake and speed > float(k["handbrake_speed"])):
		if not front and handbrake:
			slide = true
		elif not abs_on and v_long <= 2.0 * (float(k["lock_capacity_margin"]) - c) and brake_byte > HARD_BRAKE \
				and (speed >= float(k["lock_speed"]) or spin_flag != 0):
			slide = true  # no ABS: hard braking locks the wheel
		else:
			fx = clampf(fx, -c, c)
			if abs_on and v_long < float(k["abs_pulse_speed"]) and braking and tick_count % ABS_PULSE_TICKS == 0:
				slide = true
	var cap_now := (1.0 - damage * DAMAGE_SCALE * float(k["damage_grip"])) * c
	if slide:
		return _slide(i, lat, lon, cap_now)

	# Side force from the slip angle: the rear reaches the full capacity at a small angle, the
	# front grows with the angle up to past the capacity.
	var force := 0.0
	if lat != 0.0:
		# Slip angle in angle units, from the side speed against half the forward one.
		var units := atan2(absf(lat), absf(lon) * 0.5) / TAU * float(k["angle_turn"]) if lon != 0.0 else 0.0
		if not front:
			force = clampf(units, 1.0, float(k["rear_angle_full"])) * c * 0.5
			force = minf(force, absf(lat))
		else:
			force = minf(units, float(k["front_angle_max"])) * c * float(k["front_angle_gain"])
			if absf(lat) + absf(lon) < float(k["slow_speed_sum"]):
				force = minf(force, absf(lat))
		force *= signf(lat)
	if simple and front:
		force *= float(k["simple_front_side"])
	# Friction circle: the larger force plus a quarter of the smaller one within the capacity.
	var long_part := absf(fx) * float(k["long_combine_simple" if simple else "long_combine"])
	var big := maxf(long_part, absf(force))
	var small := minf(long_part, absf(force))
	var combined := big + small * float(k["minor_combine"])
	var spinning := (absf(fx) > cap_now and throttle_byte > 0x80) \
		or (spin_flag == 2 and (not front or drive_front > 0.0))
	var divisor := SPIN_DIVISOR if (not front and spinning) else float(slide_divisor[clampi(tyre_type, 0, 2)])
	if combined <= cap_now:
		skid[i] = 0.0
	elif tc_on and not front and absf(_slip) < float(k["tc_slip"]):
		var s := cap_now / combined
		if gear > 2:
			force *= s
		fx *= s
		skid[i] = 0.0
	else:
		var loss := minf((combined - cap_now) / divisor, cap_now / divisor)
		var s := (cap_now - loss) / combined
		var mix := float(k["skid_front" if front else "skid_rear"])
		skid[i] = (skid[i] * float(k["skid_keep"]) + (combined - cap_now) * mix) * float(k["skid_mix"])
		force *= s
		fx *= s
	if not front and spinning and not tc_on:
		skid[i] = combined
	skid[i] = minf(skid[i], 1.0) * (0.5 if tc_on else 1.0)
	# Back into the car's axes.
	if turn != 0.0:
		var lat_car := force * cos(turn) - fx * sin(turn)
		var lon_car := fx * cos(turn) + force * sin(turn)
		return Vector2(lat_car, lon_car)
	return Vector2(force, fx)


## A locked (or handbrake held) wheel slides against its motion with the grip a sliding tyre keeps.
func _slide(i: int, lat: float, lon: float, cap_now: float) -> Vector2:
	var big := maxf(absf(lat), absf(lon))
	var small := minf(absf(lat), absf(lon))
	var combined := big + small * float(k["minor_combine"])
	var divisor := float(slide_divisor[clampi(tyre_type, 0, 2)])
	if combined > cap_now:
		skid[i] = (skid[i] * float(k["skid_keep"]) + combined - cap_now) * float(k["skid_mix"])
	else:
		skid[i] = 0.0
	skid[i] = minf(skid[i] * float(k["skid_lock"]), 1.0)
	if combined <= float(k["slide_min"]):
		return Vector2.ZERO
	var s := (cap_now - cap_now / divisor) / combined
	return Vector2(s * lat, s * lon)


## Engine and gearbox (0x49E440, 0x49DAF0): revs in fixed steps per tick; returns the drive
## acceleration (m/s2, positive forwards) minus the air drag.
func _engine(throttle: float, throttle_byte: int, brake_byte: int, v_long: float, speed: float,
		rear_on: bool, damage: Dictionary) -> float:
	_last_throttle = throttle
	var drag_now := drag * v_long * v_long * v_long
	var engine_dmg := float(damage.get("engine", 0.0)) * DAMAGE_SCALE
	var drive_dmg := float(damage.get("drive", 0.0)) * DAMAGE_SCALE
	var misfire := _rng.randf() < engine_dmg * float(k["engine_damage"])
	var free := gear == 1 or not rear_on
	var margin := float(k["rpm_rise"]) if free else float(k["rpm_target_margin"])
	var target := minf((redline + margin) * throttle, redline + margin)
	# Rev limiter: touching it cuts the throttle for a few ticks.
	if rpm >= redline and rpm < redline + float(k["rpm_rise"]):
		rpm = redline + float(k["limiter_bounce"])
		if gear >= 2 and rear_on:
			limiter_ticks = _rng.randi_range(0, 1) + gear * 3
		else:
			limiter_ticks = _rng.randi_range(2, 3)
	if limiter_ticks > 0:
		limiter_ticks -= 1
		throttle = 0.0
		target = 0.0
	spin_flag = 0
	if free or shift_ticks > 0:
		if misfire:
			rpm = maxf(rpm - float(k["rpm_target_margin"]), 0.0)
		elif target <= rpm or shift_ticks > 0:
			if shift_ticks < 1 or prev_gear == 1:
				if rpm >= target:
					rpm = maxf(rpm - float(k["rpm_fall"]), target)
			elif not downshift:
				rpm = maxf(rpm - float(k["shift_drop_high"] if gear > 3 else k["shift_drop_low"]), 0.0)
			else:
				var table: Array = blip_braking if brake_byte > SLOPE_BRAKE else blip_light
				rpm = minf(rpm + float(table[clampi(gear, 0, table.size() - 1)]), redline)
		else:
			rpm = minf(rpm + float(k["rpm_rise"]), target)
		return -drag_now
	var g := gear
	if automatic:
		_auto_shift(throttle, speed, v_long)
		if shift_ticks > 0 and not downshift:
			g = prev_gear  # this tick still in the gear the upshift came from
		else:
			g = gear
	var wheel_rpm := rpm_per_speed[g] * v_long
	var torque := _torque_at(rpm) * drive_factor[g] * (1.0 - engine_dmg * float(k["engine_damage"])) \
		* (1.0 - drive_dmg * float(k["damage_grip"]))
	var want := target - absf(wheel_rpm)
	if absf(want) < float(k["sync_window"]) and target <= redline - float(k["sync_redline_margin"]):
		want = 0.0
	var over := rpm - absf(wheel_rpm)
	var force := 0.0
	if (over > float(k["spin_rpm"]) and g != 1) or (g >= 2 and v_long < float(k["creep_back"])) \
			or (g == 0 and v_long > float(k["creep_forward"])):
		# The engine is ahead of the wheels: clutch slip or wheelspin, full torque, revs come down.
		var grip_room := absf(torque * float(k["traction_force"])) - (cap[2] + cap[3])
		var base := float(k["traction_base"])
		if drive_front > 0.0:
			grip_room -= cap[0] + cap[1]
			base = float(k["traction_base_awd"])
		var fall := (1.0 - throttle) * float(k["traction_base"]) + (base - grip_room) \
			/ maxf(throttle_byte * float(k["throttle_byte"]), float(k["throttle_floor"]))
		if shift_delay < SHIFT_FAST and g > 2:
			rpm -= over * float(k["spin_fall"])
		if throttle < 0.5 or misfire:
			rpm -= over * float(k["spin_fall"])
		else:
			if over > redline * float(k["spin_flag_share"]):
				spin_flag = 2
			rpm -= minf(over, fall)
		force = torque
	elif want >= 0.0:
		if want == 0.0:
			rpm = wheel_rpm
			return 0.0  # holding the speed it wants: drive and drag balance
		if misfire:
			rpm -= float(k["rpm_target_margin"])
		else:
			if over > float(k["sync_step"]):
				rpm -= float(k["sync_step"])
			elif over >= float(k["sync_band"]):
				rpm = absf(wheel_rpm)
			else:
				rpm += float(k["sync_step"])
			force = torque * throttle
		rpm = minf(rpm, target)
	else:
		# Off throttle: engine braking, the revs follow the wheels at most so fast.
		var step_max := speed_per_rpm[g] * float(k["rev_rate"])
		var catch_up := clampf(-over, -absf(step_max), absf(step_max))
		if absf(wheel_rpm) <= redline + float(k["over_rev"]):
			if limiter_ticks > 0:
				torque *= float(k["misfire_brake"])
			force = -torque * engine_brake * minf(1.0 + drive_dmg * float(k["engine_brake_damage"]),
				float(k["engine_brake_damage_cap"]))
			rpm += catch_up
			rpm = maxf(rpm, target)
		else:
			force = -torque
			rpm += catch_up
	rpm = clampf(rpm, 0.0, redline * float(k["rpm_cap"]))
	return force - drag_now


## Automatic gearbox (0x49DAF0): up near the redline under throttle, down when the lower gear
## stays under its share of the redline (kick-down under throttle, early off throttle).
func _auto_shift(throttle: float, speed: float, v_long: float) -> void:
	if gear < 2:
		return
	var v := speed if v_long >= 0.0 else -speed
	var now := v * rpm_per_speed[gear]
	if rpm < now * float(k["auto_engine_vs_wheel"]):
		now = rpm
	var down_gear := gear - 1 if gear > 2 else gear
	var down := v * rpm_per_speed[down_gear]
	if throttle <= 0.5 and absf(now) <= redline:
		if down < redline * float(k["auto_down"]) and down_gear >= 2 and down_gear != gear \
				and absf(_slip) < float(k["auto_slip"]):
			_shift_to(down_gear)
		return
	var up_at := redline * (float(k["auto_up"]) + _rng.randf() * float(k["auto_up_spread"]))
	if now > up_at and gear < top_gear():
		_shift_to(gear + 1)
	elif down < redline * float(k["auto_down"]) and down_gear != gear:
		_shift_to(down_gear)


## Body pitch and roll the original only draws (0x499A70): a share of the acceleration, kept
## from tick to tick by the damping values.
func _body_motion() -> void:
	var p := clampf(accel_long * pitch_per_accel, -pitch_limit, pitch_limit)
	var r := clampf(accel_lat * roll_per_accel, -roll_limit, roll_limit)
	pitch = pitch * pitch_keep + p * (1.0 - pitch_keep)
	roll = roll * roll_keep + r * (1.0 - roll_keep)


## Car.gear for the HUD and sound: -1 reverse, 0 neutral, 1.. forward.
func car_gear() -> int:
	if gear == 0:
		return -1
	return gear - 1
