extends Node
## Checks the original's driving model (D-046) against its formulas on a flat test ground:
##   godot --headless --path game res://tests/original_handling_test.tscn [-- --car=993Tcoupe36 --handling=sim]
## Default --handling=original. Phases: full throttle (0-100, top speed in RUN_TIME), steering lock
## at 0 / 100 km/h and above (full key), full brake (deceleration against .sim 0x104), lift-off
## (engine braking, .sim 0x098), steady circle at CIRCLE_KMH with full lock (lateral g against
## .sim 0x0F4). Every phase has a time limit, so the test always ends.

const RUN_TIME := 40.0
const GROUND_Y := -500.0
const CIRCLE_KMH := 70.0
const LIMIT := 30.0  ## s per phase at most

var main: Node3D
var car: Car
var t := 0.0
var phase := "settle"
var marks := {}
var top := 0.0
var lock_at := {}  ## km/h -> steering angle (deg) with full lock
var decel := []  ## brake: [speed, time] samples
var lift := []
var circle := []  ## lateral g samples
var circle_angle := []
var log_t := 0.0


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "skidpad"
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = true
	var ground := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8000.0, 2.0, 8000.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	ground.add_child(col)
	main.add_child(ground)
	ground.global_position = Vector3(0.0, GROUND_Y - 1.0, -3800.0)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, GROUND_Y + 0.05, 0.0)))
	var mode := "original"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--handling="):
			mode = arg.trim_prefix("--handling=")
	if mode == "original" and not car.original_handling:
		car.set_original_handling(true)
	print("ORIGINAL HANDLING TEST: %s, model %s" % [main.car_key, "original" if car.original_handling else "physical"])


func _keys(accel: bool, brk: bool, steer: float) -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right"]:
		Input.action_release(a)
	if accel:
		Input.action_press("accelerate")
	if brk:
		Input.action_press("brake")
	if steer > 0.0:
		Input.action_press("steer_left", steer)
	elif steer < 0.0:
		Input.action_press("steer_right", -steer)


func _hold_heading() -> float:
	var yaw := wrapf(car.global_rotation.y - _heading, -PI, PI)
	return clampf(-yaw * 3.0 - car.angular_velocity.y * 0.6, -1.0, 1.0)


var _heading := 0.0


func _next(p: String) -> void:
	phase = p
	t = 0.0


func _physics_process(delta: float) -> void:
	t += delta
	var kmh := car.forward_speed * 3.6
	log_t += delta
	if log_t >= 2.0:
		log_t = 0.0
		print("  %-7s t %5.1f  %5.1f km/h  gear %d  %5d rpm  steer %5.1f deg  yaw %5.2f" % [
			phase, t, kmh, car.gear, roundi(car.rpm), rad_to_deg(car.steer), car.angular_velocity.y])
	match phase:
		"settle":
			_keys(false, false, 0.0)
			lock_at[0] = rad_to_deg(car.steer)
			if t > 1.0:
				_next("lock0")
		"lock0":
			_keys(false, false, 1.0)
			if t > 0.6:
				lock_at[0] = rad_to_deg(car.steer)
				_next("run")
		"run":
			_keys(true, false, 0.0 if car.original_handling and absf(car.angular_velocity.y) < 0.01 else 0.0)
			if absf(car.global_rotation.y) > 0.02 or absf(car.angular_velocity.y) > 0.02:
				_keys(true, false, _hold_heading())
			for mark in [100.0, 200.0]:
				if kmh >= mark and not marks.has(mark):
					marks[mark] = t
					if mark == 100.0:
						lock_at[100] = _full_lock_angle()
			top = maxf(top, kmh)
			if t >= RUN_TIME:
				_next("lift")
		"lift":
			_keys(false, false, _hold_heading())
			lift.append([car.forward_speed, t, car.gear])
			if t > 3.0:
				_next("brake")
		"brake":
			_keys(false, true, _hold_heading())
			decel.append([car.forward_speed, t])
			if kmh < 5.0 or t > LIMIT:
				_next("circle_up")
		"circle_up":
			var want := CIRCLE_KMH / 3.6
			_keys(car.forward_speed < want, false, 0.0)
			if absf(car.forward_speed - want) < 0.5 and t > 2.0 or t > LIMIT:
				_next("circle")
		"circle":
			# Full lock, throttle holding the speed.
			_keys(car.forward_speed < CIRCLE_KMH / 3.6, false, 1.0)
			if t > 3.0:
				circle.append(absf(car.linear_velocity.length() * car.angular_velocity.y) / Car.GRAVITY)
				circle_angle.append(rad_to_deg(car.steer))
			if t > 10.0:
				_report()


func _full_lock_angle() -> float:
	if car.original == null:
		return rad_to_deg(car.steer)
	# Angle full lock gives at this speed, from the model's own formula (no key ramp).
	var o := car.original
	var v := car.forward_speed
	var lock := o.steer_lock
	if v < float(o.k["steer_low_speed"]):
		lock *= float(o.k["steer_low_base"]) - v * float(o.k["steer_low_per_ms"])
	lock = minf(lock, float(o.k["steer_lock_cap"]))
	if v > float(o.k["steer_high_speed"]):
		lock /= v * float(o.k["steer_high_div"])
	return lock * float(o.k["steer_unit"]) * 360.0


func _mean(a: Array) -> float:
	var s := 0.0
	for x: float in a:
		s += x
	return s / maxf(a.size(), 1.0)


func _report() -> void:
	var u: Dictionary = car.params.get("unknown", {})
	print("  0-100 km/h %s, 0-200 %s, top in %.0f s %.0f km/h (data %.0f)" % [
		"%.1f s" % marks[100.0] if marks.has(100.0) else "-", "%.1f s" % marks[200.0] if marks.has(200.0) else "-",
		RUN_TIME, top, float(car.params.get("top_speed_mph", 0.0)) * 1.609])
	print("  full lock: standing %.1f deg, 100 km/h %.1f deg" % [lock_at.get(0, 0.0), lock_at.get(100, 0.0)])
	# Braking: mean deceleration from 100 to 30 km/h.
	var t0 := -1.0
	var t1 := -1.0
	for s: Array in decel:
		if t0 < 0.0 and s[0] * 3.6 <= 100.0:
			t0 = s[1]
		if t1 < 0.0 and s[0] * 3.6 <= 30.0:
			t1 = s[1]
	if t0 >= 0.0 and t1 > t0:
		print("  braking 100-30 km/h: %.2f m/s2 (.sim 0x104 %.2f)" % [(100.0 - 30.0) / 3.6 / (t1 - t0), float(u.get("0x104", 0.0))])
	if lift.size() > 10:
		var a: Array = lift[5]
		var b: Array = lift[-1]
		print("  lift-off: %.2f m/s2 from %.0f km/h in gear %d (.sim 0x098 %.0f %%)" % [
			(a[0] - b[0]) / (b[1] - a[1]), a[0] * 3.6, b[2], float(u.get("0x098", 0.0))])
	print("  circle %.0f km/h full lock: lateral %.2f g, steer %.1f deg (.sim 0x0F4 %.2f)" % [
		CIRCLE_KMH, _mean(circle), _mean(circle_angle), float(u.get("0x0F4", 0.0))])
	get_tree().quit()
