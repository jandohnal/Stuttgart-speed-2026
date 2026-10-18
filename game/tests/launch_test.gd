extends Node
## Standing start with full throttle on a flat test ground 500 m below the skidpad:
##   godot --headless --path game res://tests/launch_test.tscn [-- --car=935race --keyboard=0 --set=prop:value]
## The throttle key is held like a player would (keyboard ramps, --keyboard=0 gives it directly).
## Prints the first seconds every 0.1 s (slip ratio and slip angle of each wheel, engine torque,
## axle loads, speed), how long the driven wheels spin past the tyres' peak slip, and 0-100 km/h.

const GROUND_Y := -500.0
const TABLE_TIME := 3.0
const RUN_TIME := 20.0

var main: Node3D
var car: Car
var t := 0.0
var phase := "settle"
var next_row := 0.0
var marks := {}
var spin_time := 0.0  ## s with a driven wheel past the peak slip ratio
var max_slip := 0.0
var max_angle := 0.0
var overrides := {}
var turn := 0.0  ## --turn=0..1: hold this much left steering instead of keeping the heading
var max_split := 0.0  ## largest slip ratio difference between the driven wheels (inner wheel spin)


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "skidpad"
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--keyboard="):
			car.digital_input = arg.trim_prefix("--keyboard=") != "0"
		elif arg.begins_with("--turn="):
			turn = float(arg.trim_prefix("--turn="))
		elif arg.begins_with("--set="):
			var kv := arg.trim_prefix("--set=").split(":")
			overrides[kv[0]] = kv[1]
			car.set(kv[0], type_convert(str_to_var(kv[1]), typeof(car.get(kv[0]))))
	var ground := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 2000.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	ground.add_child(col)
	main.add_child(ground)
	ground.global_position = Vector3(0.0, GROUND_Y - 1.0, -900.0)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, GROUND_Y + 0.05, 0.0)))  # facing -Z


func _physics_process(delta: float) -> void:
	t += delta
	# Hold the heading (-Z): steer against the yaw.
	var yaw := car.global_rotation.y
	var steer := clampf(-yaw * 4.0 - car.angular_velocity.y * 0.5, -1.0, 1.0)
	if turn > 0.0 and phase == "run":
		steer = turn
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if steer > 0.0:
		Input.action_press("steer_left", steer)
	elif steer < 0.0:
		Input.action_press("steer_right", -steer)
	match phase:
		"settle":
			if t > 1.0:
				phase = "run"
				t = 0.0
				next_row = 0.0
				print("LAUNCH TEST: %s (%s) keyboard=%s %s" % [car.params.get("name", "?"), main.car_key, car.digital_input, overrides])
				print("    t  km/h gear  rpm thr   eng_Nm  load_f load_r  slip rl/rr  (fl/fr)   angle rl/rr")
		"run":
			Input.action_press("accelerate")
			var tm := car.telemetry
			if tm.is_empty():
				return
			var kmh := car.forward_speed * 3.6
			var peak := 0.0
			for w in car.wheels:
				if car._drive_share(w) > 0.0:
					peak = maxf(peak, w.slip_ratio)
				max_angle = maxf(max_angle, absf(rad_to_deg(w.slip_angle)))
			max_slip = maxf(max_slip, peak)
			max_split = maxf(max_split, absf(tm["slip_rl"] - tm["slip_rr"]))
			if peak > car.peak_slip_ratio:
				spin_time += delta
			for mark in [50.0, 100.0, 150.0, 200.0]:
				if kmh >= mark and not marks.has(mark):
					marks[mark] = t
			if t >= next_row and t <= TABLE_TIME:
				next_row += 0.1
				print("  %4.1f %5.1f  %d  %5d %.2f %6d  %6d %6d   %5.2f %5.2f (%5.2f %5.2f)  %4.1f %4.1f" % [
					t, kmh, tm["gear"], tm["rpm"], tm["throttle"], tm["engine_nm"], tm["load_f"], tm["load_r"],
					tm["slip_rl"], tm["slip_rr"], tm["slip_fl"], tm["slip_fr"], tm["angle_rl"], tm["angle_rr"]])
			if marks.has(200.0) or t >= RUN_TIME:
				Input.action_release("accelerate")
				_report()


func _report() -> void:
	print("  0-50 %s, 0-100 %s, 0-150 %s, 0-200 %s" % [_s(50.0), _s(100.0), _s(150.0), _s(200.0)])
	print("  driven wheels past peak slip %.2f s, max slip ratio %.2f (peak %.2f), max slip angle %.1f deg, max rear slip split %.2f" % [
		spin_time, max_slip, car.peak_slip_ratio, max_angle, max_split])
	get_tree().quit()


func _s(mark: float) -> String:
	return "%.2f s" % marks[mark] if marks.has(mark) else "-"
