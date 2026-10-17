extends Node
## Headless test for braking in a corner (comparison with the original, where the rear-engined
## car steps out):
##   godot --headless --path game res://tests/brake_turn_test.tscn [-- --brake=1.0 --steer=1.0 --abs=0 --keyboard=0 --set=rear_grip:1.1]
## The brake and steering are held like keys (ramped by the car's keyboard input) unless --keyboard=0.
## On the skidpad: follows the circle up to ENTRY_KMH, then holds full steering into the corner
## and the brake for HOLD_TIME. Reports the yaw response and the body slip angle (beta).

const ENTRY_KMH := 100.0
const HOLD_TIME := 3.0
const LOOKAHEAD := 5

var main: Node3D
var car: Car
var phase := "run_up"
var t := 0.0
var brake := 1.0
var abs_on := true
var steer_input := 1.0  ## share of full steering held into the corner
var overrides := {}  ## car property -> value, from --set=name:value (tuning)
var turn_sign := 1.0  # +1 corner to the left
var heading_start := 0.0
var max_beta := 0.0
var max_yaw := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--brake="):
			brake = arg.trim_prefix("--brake=").to_float()
		elif arg.begins_with("--set="):
			var kv := arg.trim_prefix("--set=").split(":")
			overrides[kv[0]] = kv[1].to_float()
		elif arg.begins_with("--steer="):
			steer_input = arg.trim_prefix("--steer=").to_float()
		elif arg.begins_with("--keyboard="):
			overrides["digital_input"] = float(arg.trim_prefix("--keyboard=") != "0")
		elif arg.begins_with("--abs="):
			abs_on = arg.trim_prefix("--abs=") != "0"
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "skidpad"
	add_child(main)
	car = main.get_node("Car") as Car
	car.brake_assist = abs_on
	car.digital_input = false  # run-up: analog path following
	for key: String in overrides:
		if key != "digital_input":
			car.set(key, overrides[key])


func _physics_process(delta: float) -> void:
	t += delta
	var speed := car.forward_speed * 3.6
	match phase:
		"run_up":
			_follow_road()
			Input.action_press("accelerate")
			if speed >= ENTRY_KMH:
				turn_sign = signf(car.steer) if car.steer != 0.0 else 1.0
				car.digital_input = bool(overrides.get("digital_input", 1.0))
				Input.action_release("steer_left")
				Input.action_release("steer_right")
				heading_start = car.global_rotation.y
				phase = "brake_turn"
				t = 0.0
				Input.action_release("accelerate")
				print("BRAKE IN CORNER: %.0f km/h, brake %.2f, steering %s %.2f, keyboard %s, assist %s, ABS %s, overrides %s" % [
					speed, brake, "left" if turn_sign > 0.0 else "right", steer_input, car.digital_input, car.steering_assist, car.brake_assist, overrides])
		"brake_turn":
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			if steer_input > 0.0:
				Input.action_press("steer_left" if turn_sign > 0.0 else "steer_right", steer_input)
			Input.action_press("brake", brake)
			var beta := _beta()
			var yaw := rad_to_deg(car.angular_velocity.y) * turn_sign
			max_beta = maxf(max_beta, absf(beta))
			max_yaw = maxf(max_yaw, yaw)
			if fmod(t, 0.25) < delta:
				var axles := PackedStringArray()
				for front in [true, false]:
					var slip := 0.0
					var angle := 0.0
					var lat := 0.0
					for w in car.wheels:
						if w.front == front:
							slip += w.slip_ratio / 2.0
							angle += rad_to_deg(w.slip_angle) / 2.0
							lat += w.force.y
					axles.append("%s slip %+.2f angle %+5.1f° lat %+5d N" % ["F" if front else "R", slip, angle, roundi(lat)])
				print("  t %.2f  %5.1f km/h  steer %+5.1f°  yaw %+6.1f°/s  beta %+6.1f°  %s" % [
					t, speed, rad_to_deg(car.steer), yaw, beta, " | ".join(axles)])
			if t >= HOLD_TIME or (t > 0.5 and absf(car.linear_velocity.length()) < 1.0):
				var turned := rad_to_deg(wrapf(car.global_rotation.y - heading_start, -PI, PI)) * turn_sign
				print("  result: heading change %.0f°, max beta %.1f°, max yaw rate %.1f°/s, speed %.0f km/h" % [
					turned, max_beta, max_yaw, speed])
				get_tree().quit()


## Body slip angle: between where the car points and where it goes (deg, + = sliding outwards).
func _beta() -> float:
	var v := car.global_basis.inverse() * car.linear_velocity
	if v.length() < 1.0:
		return 0.0
	return rad_to_deg(atan2(-v.x, -v.z)) * -turn_sign


func _follow_road() -> void:
	var slices: Array = main.road_slices
	var target_i: int = main.slice_ahead(main._nearest_slice(), LOOKAHEAD)
	var p: Array = slices[target_i]["position"]
	var to_target := car.to_local(Vector3(p[0], p[1], p[2]))
	var steer := clampf(atan2(-to_target.x, -to_target.z) * 3.0, -1.0, 1.0)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if steer > 0.0:
		Input.action_press("steer_left", steer)
	elif steer < 0.0:
		Input.action_press("steer_right", -steer)
