extends Node
## Headless drive test for the phase 2 prototype:
##   godot --headless --path game res://tests/drive_test.tscn [-- --track=farmland]
## Loads the main scene, lets the car settle, then drives flat out along the road (skidpad unless
## --track is given; steering towards road slices ahead, braking only for corners ahead that
## need more than CORNER_G at the current speed), measures 0-100 km/h, speed after ACCEL_TIME and the
## braking distance from 100 km/h, prints a report and quits.

const SETTLE_TIME := 1.5
const ACCEL_TIME := 40.0
const LOOKAHEAD := 5  # road slices (~6 m each)
const CORNER_G := 0.55  # lateral acceleration the driver plans corners for
const BRAKE_G := 0.45  # deceleration the driver plans with
const PLAN_SLICES := 40  # how far ahead the driver looks for corners (~240 m)

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
var corner_brakes := 0  ## physics ticks spent braking for corners
var bump_stop_ticks := 0  ## physics ticks with any wheel in the bump stop
var max_lift := -1.0  ## highest wheel position relative to the model's ride height, m
var prev_rpm := -1.0
var max_rpm_step := 0.0  ## largest engine speed change in one physics tick while accelerating, rpm
var shifts := 0
var prev_gear := 1


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = main._track_from_args() if _has_track_arg() else "skidpad"
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = false  # the scripted driver is analog; measure the car, not the key ramps
	car.contact_monitor = true
	car.max_contacts_reported = 8


func _physics_process(delta: float) -> void:
	t += delta
	var speed := car.forward_speed * 3.6
	var last := prev_speed
	prev_speed = speed
	for body in car.get_colliding_bodies():
		var what := "%s/%s" % [body.get_parent().get_parent().name, body.get_parent().name]
		if body.get_parent().name == "props":
			what = "props/%s" % body.name
		var entry := "%s at %.1f s (%s, %s), %.0f km/h" % [what, t, phase, car.global_position.snapped(Vector3.ONE * 0.1), speed]
		if collisions.size() < 10 and not collisions.has(entry) and not ",".join(collisions).contains(what):
			collisions.append(entry)
	if phase != "settle":
		var on_stop := false
		for w in car.wheels:
			var lift: float = w.compression - car.droop_travel
			max_lift = maxf(max_lift, lift)
			on_stop = on_stop or lift > car.bump_travel * 0.75
		if on_stop:
			bump_stop_ticks += 1
	match phase:
		"settle":
			if t >= SETTLE_TIME:
				settle_report = _settle_report()
				phase = "accelerate"
				t = 0.0
		"accelerate":
			_steer_along_road()
			if prev_rpm >= 0.0:
				max_rpm_step = maxf(max_rpm_step, absf(car.rpm - prev_rpm))
			prev_rpm = car.rpm
			if car.gear != prev_gear:
				shifts += 1
				prev_gear = car.gear
			var over := car.forward_speed - _safe_speed()
			if over > 0.5:
				Input.action_release("accelerate")
				Input.action_press("brake", clampf(over / 6.0, 0.2, 1.0))  # modulated, like a driver
				corner_brakes += 1
			else:
				Input.action_release("brake")
				Input.action_press("accelerate")
			if fmod(t, 2.0) < delta:
				print("  t %4.1f  %5.1f km/h  gear %d  %4d rpm  steer %5.1f° yaw %5.1f°/s brk %.2f thr %.2f  lat %.2f g  off-road %.1f m  y %.2f" % [
					t, speed, car.gear, roundi(car.rpm), rad_to_deg(car.steer), rad_to_deg(car.angular_velocity.y), car.brake, car.throttle, float(car.telemetry.get("lat_g", 0.0)),
					_distance_from_road(), car.global_position.y])
				var forces := PackedStringArray()
				for w in car.wheels:
					forces.append("%s load %d long %d lat %d slip %.3f/%.1f° lift %+.3f" % ["F" if w.front else "R", roundi(w.normal_load), roundi(w.force.x), roundi(w.force.y), w.slip_ratio, rad_to_deg(w.slip_angle), w.compression - car.droop_travel])
				print("      ", " | ".join(forces), " | body contacts ", car.get_colliding_bodies().map(func(b): return b.get_parent().name))
			top_speed = maxf(top_speed, speed)
			max_lat_g = maxf(max_lat_g, absf(float(car.telemetry.get("lat_g", 0.0))))
			if t_100 < 0.0 and speed >= 100.0:
				t_100 = t
			if t >= ACCEL_TIME:
				end_speed = speed
				Input.action_release("accelerate")
				Input.action_release("brake")
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


## Highest speed (m/s) from which every corner in the next PLAN_SLICES can still be taken at
## CORNER_G after braking at BRAKE_G.
func _safe_speed() -> float:
	var slices: Array = main.road_slices
	if slices.is_empty():
		return INF
	var i: int = main._nearest_slice()
	var dist := 0.0
	var best := INF
	for k in PLAN_SLICES:
		var j: int = main.slice_ahead(i, 1)
		if j == i:
			break
		var a: Dictionary = slices[i]
		var b: Dictionary = slices[j]
		var step := _v(a["position"]).distance_to(_v(b["position"]))
		var turn := _v(a["forward"]).angle_to(_v(b["forward"]))
		if step > 0.01 and turn > 1e-4:
			var corner := sqrt(CORNER_G * 9.81 * step / turn)  # v^2 = a * radius
			best = minf(best, sqrt(corner * corner + 2.0 * BRAKE_G * 9.81 * dist))
		dist += step
		i = j
	return best


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _has_track_arg() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			return true
	return false


func _steer_along_road() -> void:
	var slices: Array = main.road_slices
	if slices.is_empty():
		return
	var target_i: int = main.slice_ahead(main._nearest_slice(), LOOKAHEAD)
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
	var lifts := PackedStringArray()
	for w in car.wheels:
		lifts.append("%+.3f" % (w.compression - car.droop_travel))
	return "wheels %d, in contact %d, loads N [%s] (weight/4 = %d), wheel lift m [%s]" % [
		car.wheels.size(), contacts, ", ".join(loads), roundi(car.mass * 9.81 / 4.0), ", ".join(lifts)]


func _finish() -> void:
	var track_parts := 0
	for child in main.get_children():
		if child is Node3D and child != car and not (child is Camera3D) and not (child is DirectionalLight3D):
			track_parts += child.get_child_count()
	print("DRIVE TEST")
	print("  car: %s, %.0f kg, wheel radius %.3f m" % [car.params.get("name", "?"), car.mass, car.wheel_radius])
	print("  track %s: groups loaded %d, road slices %d, start slice %d, props %s" % [
		main.track_name, track_parts, main.road_slices.size(), main.start_slice, main.prop_counts])
	print("  settle: ", settle_report)
	print("  0-100 km/h: %s" % ("%.1f s" % t_100 if t_100 >= 0.0 else "not reached"))
	print("  speed after %.0f s: %.0f km/h (max %.0f), max lateral %.2f g" % [ACCEL_TIME, end_speed, top_speed, max_lat_g])
	print("  gear shifts: %d, max engine speed change per tick %.0f rpm" % [shifts, max_rpm_step])
	print("  braking for corners: %.1f s" % (corner_brakes / float(Engine.physics_ticks_per_second)))
	print("  suspension: max wheel lift %.3f m of %.2f, bump stop %.1f s" % [
		max_lift, car.bump_travel, bump_stop_ticks / float(Engine.physics_ticks_per_second)])
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
