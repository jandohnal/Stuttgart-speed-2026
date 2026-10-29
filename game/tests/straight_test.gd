extends Node
## Straight-line test of a car on a flat 8 km test ground 500 m below the skidpad:
##   godot --headless --path game res://tests/straight_test.tscn [-- --car=935race --set=prop:value]
## Full throttle for RUN_TIME (holding the heading), then full brake. Reports the settings derived
## from the car data, 0-100 and 0-200 km/h, the top speed and the braking distances, to compare
## with the car's real figures.

const RUN_TIME := 60.0
const GROUND_Y := -500.0

var main: Node3D
var car: Car
var t := 0.0
var phase := "settle"
var marks := {}  ## km/h -> s
var top := 0.0
var top_at := 0.0
var top_gear := 0
var top_rpm := 0.0
var brake_from := {}  ## km/h -> position where the speed passed it while braking
var brake_dist := {}


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "skidpad"
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):  # car property, e.g. --set=unsprung_model:0
			var kv := arg.trim_prefix("--set=").split(":")
			car.set(kv[0], kv[1].to_float())
	var ground := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 8000.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	ground.add_child(col)
	main.add_child(ground)
	ground.global_position = Vector3(0.0, GROUND_Y - 1.0, -3800.0)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, GROUND_Y + 0.05, 0.0)))  # facing -Z


func _physics_process(delta: float) -> void:
	t += delta
	var kmh := car.forward_speed * 3.6
	# Hold the heading (-Z): steer against the yaw.
	var yaw := car.global_rotation.y
	var steer := clampf(-yaw * 4.0 - car.angular_velocity.y * 0.5, -1.0, 1.0)
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
		"run":
			Input.action_press("accelerate")
			for mark in [100.0, 200.0, 300.0]:
				if kmh >= mark and not marks.has(mark):
					marks[mark] = t
			if kmh > top + 0.5:
				top = kmh
				top_at = t
				top_gear = car.gear
				top_rpm = car.rpm
			if t >= RUN_TIME or car.global_position.z < -7400.0:
				Input.action_release("accelerate")
				phase = "brake"
				t = 0.0
		"brake":
			Input.action_press("brake")
			for mark in [200.0, 100.0]:
				if kmh <= mark and not brake_from.has(mark) and top > mark:
					brake_from[mark] = car.global_position
			if kmh <= 0.5:
				for mark in brake_from:
					brake_dist[mark] = (brake_from[mark] as Vector3).distance_to(car.global_position)
				Input.action_release("brake")
				_report()


func _report() -> void:
	print("STRAIGHT TEST: %s (%s)" % [car.params.get("name", "?"), main.car_key])
	print("  derived: drag area %.2f m2, brakes %.2f g (front %.2f), drivetrain %.2f, engine brake %.2f, shift %.2f s, downforce front %.1f rear %.1f m2, springs %.1f Hz, wheel inertia %.1f kg m2, mu %.2f, rear grip %.2f" % [
		car.drag_area, car.brake_decel_g, car.brake_front_bias, car.drivetrain_efficiency, car.engine_brake,
		car.shift_time, car.downforce_front, car.downforce_rear,
		car.ride_frequency, car.wheel_inertia, car.mu, car.rear_grip])
	var top_gear_kmh := car.redline / (car.gear_ratios[-1] * car.final_drive) * TAU / 60.0 * car.wheel_radius * 3.6
	print("  data top speed %.0f km/h, top gear at the limiter %.0f km/h" % [
		float(car.params.get("top_speed_mph", 0.0)) * 1.609, top_gear_kmh])
	print("  0-100 km/h %s, 0-200 %s, 0-300 %s" % [_s(100.0), _s(200.0), _s(300.0)])
	print("  top speed %.0f km/h (reached at %.0f s, gear %d, %d rpm)" % [top, top_at, top_gear, roundi(top_rpm)])
	print("  braking 200-0 %s, 100-0 %s" % [_m(200.0), _m(100.0)])
	get_tree().quit()


func _s(mark: float) -> String:
	return "%.1f s" % marks[mark] if marks.has(mark) else "-"


func _m(mark: float) -> String:
	return "%.0f m" % brake_dist[mark] if brake_dist.has(mark) else "-"
