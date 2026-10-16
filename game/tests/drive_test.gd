extends Node
## Headless drive test for the phase 2 prototype:
##   godot --headless --path game res://tests/drive_test.tscn
## Loads the main scene, lets the car settle, then drives flat out around the skidpad
## (steering towards road slices ahead), measures 0-100 km/h, speed after ACCEL_TIME and the
## braking distance from 100 km/h, prints a report and quits.

const SETTLE_TIME := 1.5
const ACCEL_TIME := 40.0
const LOOKAHEAD := 5  # road slices (~6 m each)

var main: Node3D
var car: Car
var phase := "settle"
var t := 0.0
var t_100 := -1.0
var top_speed := 0.0
var brake_start := Vector3.ZERO
var brake_distance := -1.0
var settle_report := ""
var max_lat_g := 0.0
var prev_speed := 0.0
var end_speed := 0.0
var collisions := PackedStringArray()


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	add_child(main)
	car = main.get_node("Car") as Car
	car.contact_monitor = true
	car.max_contacts_reported = 8


func _physics_process(delta: float) -> void:
	t += delta
	var speed := car.forward_speed * 3.6
	var last := prev_speed
	prev_speed = speed
	for body in car.get_colliding_bodies():
		var what := "%s/%s" % [body.get_parent().get_parent().name, body.get_parent().name]
		var entry := "%s at %.1f s (%s, %s), %.0f km/h" % [what, t, phase, car.global_position.snapped(Vector3.ONE * 0.1), speed]
		if collisions.size() < 10 and not collisions.has(entry) and not ",".join(collisions).contains(what):
			collisions.append(entry)
	match phase:
		"settle":
			if t >= SETTLE_TIME:
				settle_report = _settle_report()
				phase = "accelerate"
				t = 0.0
		"accelerate":
			_steer_along_road()
			Input.action_press("accelerate")
			if fmod(t, 2.0) < delta:
				print("  t %4.1f  %5.1f km/h  gear %d  %4d rpm  steer %5.1f°  lat %.2f g  off-road %.1f m  y %.2f" % [
					t, speed, car.gear, roundi(car.rpm), rad_to_deg(car.steer), float(car.telemetry.get("lat_g", 0.0)),
					_distance_from_road(), car.global_position.y])
				var forces := PackedStringArray()
				for w in car.wheels:
					forces.append("%s load %d long %d lat %d comp %.3f" % ["F" if w.front else "R", roundi(w.normal_load), roundi(w.force.x), roundi(w.force.y), w.compression])
				print("      ", " | ".join(forces), " | body contacts ", car.get_colliding_bodies().map(func(b): return b.get_parent().name))
			top_speed = maxf(top_speed, speed)
			max_lat_g = maxf(max_lat_g, absf(float(car.telemetry.get("lat_g", 0.0))))
			if t_100 < 0.0 and speed >= 100.0:
				t_100 = t
			if t >= ACCEL_TIME:
				end_speed = speed
				Input.action_release("accelerate")
				phase = "brake"
				t = 0.0
		"brake":
			_steer_along_road()
			Input.action_press("brake")
			if last > 100.0 and speed <= 100.0 and brake_start == Vector3.ZERO:
				brake_start = car.global_position
			if speed <= 0.5:
				if brake_start != Vector3.ZERO:
					brake_distance = brake_start.distance_to(car.global_position)
				Input.action_release("brake")
				_finish()
			elif t > 30.0:
				_finish()


func _steer_along_road() -> void:
	var slices: Array = main.road_slices
	if slices.is_empty():
		return
	var target_i: int = (main._nearest_slice() + LOOKAHEAD) % slices.size()
	var p: Array = slices[target_i]["position"]
	var to_target := car.to_local(Vector3(p[0], p[1], p[2]))
	var angle := atan2(-to_target.x, -to_target.z)  # positive = target on the left
	var steer := clampf(angle * 3.0, -1.0, 1.0)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if steer > 0.0:
		Input.action_press("steer_left", steer)
	elif steer < 0.0:
		Input.action_press("steer_right", -steer)


func _settle_report() -> String:
	var contacts := 0
	var loads := PackedStringArray()
	for w in car.wheels:
		if w.ray.is_colliding():
			contacts += 1
		loads.append("%d" % roundi(w.normal_load))
	return "wheels %d, in contact %d, loads N [%s] (weight/4 = %d), height %.3f m" % [
		car.wheels.size(), contacts, ", ".join(loads), roundi(car.mass * 9.81 / 4.0), car.global_position.y]


func _finish() -> void:
	var track_parts := 0
	for child in main.get_children():
		if child is Node3D and child != car and not (child is Camera3D) and not (child is DirectionalLight3D):
			track_parts += child.get_child_count()
	print("DRIVE TEST")
	print("  car: %s, %.0f kg, wheel radius %.3f m" % [car.params.get("name", "?"), car.mass, car.wheel_radius])
	print("  track groups loaded: %d, road slices: %d" % [track_parts, main.road_slices.size()])
	print("  settle: ", settle_report)
	print("  0-100 km/h: %s" % ("%.1f s" % t_100 if t_100 >= 0.0 else "not reached"))
	print("  speed after %.0f s: %.0f km/h (max %.0f), max lateral %.2f g" % [ACCEL_TIME, end_speed, top_speed, max_lat_g])
	print("  body collisions: ", collisions if not collisions.is_empty() else "none")
	print("  braking 100-0 km/h: %s" % ("%.1f m" % brake_distance if brake_distance >= 0.0 else "n/a"))
	print("  distance from road at end: %.1f m" % _distance_from_road())
	get_tree().quit()


func _distance_from_road() -> float:
	var slices: Array = main.road_slices
	if slices.is_empty():
		return -1.0
	var p: Array = slices[main._nearest_slice()]["position"]
	return Vector3(p[0], p[1], p[2]).distance_to(car.global_position)
