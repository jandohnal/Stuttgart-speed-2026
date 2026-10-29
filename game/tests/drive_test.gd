extends Node
## Headless drive test for the phase 2 prototype:
##   godot --headless --path game res://tests/drive_test.tscn [-- --track=farmland --car=935race --log-impacts --time=120 --corner-g=0.9 --set=damping_rebound:0.7]
## Loads the main scene, lets the car settle, then drives flat out along the road (skidpad unless
## --track is given; steering towards road slices ahead, braking only for corners ahead that
## need more than CORNER_G at the current speed), measures 0-100 km/h, speed after ACCEL_TIME and the
## braking distance from 100 km/h, prints a report and quits.
## Crests: every time all four wheels leave the road it logs the jump (speed, v^2/(R g) of the
## crest ahead, air time, height above the road, springs at full droop before take-off, bounces),
## where R is the vertical radius of the road from the slopes of the SimD slices. A ratio above 1
## means even a perfectly sprung car must leave the road there; below 1 the suspension threw it.

const SETTLE_TIME := 1.5
const ACCEL_TIME := 40.0
const LOOKAHEAD := 5  # road slices (~6 m each)
const CORNER_G := 0.55  # lateral acceleration the driver plans corners for
const BRAKE_G := 0.45  # deceleration the driver plans with
const PLAN_SLICES := 40  # how far ahead the driver looks for corners (~240 m)
const CREST_WINDOW := 0.5  # s before take-off searched for the crest and the spring extension

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
var odo_start := -1.0  ## car.odometer_m when accelerating starts
var path_m := 0.0  ## distance travelled by the body since then
var last_pos := Vector3.ZERO
var accel_time := ACCEL_TIME
var ride_height := 0.0  ## body origin above the road after settling, m
var recent: Array = []  ## [t, crest ratio, all springs at full droop] over the last CREST_WINDOW
var jump: Dictionary = {}  ## the jump in progress
var jumps: Array = []
var light_ticks := 0  ## ticks with under half the weight on the wheels (on the ground)
var corner_g := CORNER_G
var overrides := {}  ## car property -> value, from --set=name:value (tuning)
var crash_t := -1.0  ## first body collision while driving; the crest figures stop there
var clean_stop_ticks := 0  ## bump stop ticks before crash_t
var crest_ticks := 0  ## ticks on the ground over a crest (v^2/(R g) > 0.2)
var thrown_ticks := 0  ## of those, ticks with the load over 20 % of the weight below what the crest allows
var worst_deficit := {"deficit": 0.0}  ## largest (allowed - actual) load share and where
var max_crest := 0.0  ## highest v^2/(R g) met


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = main._track_from_args() if _has_track_arg() else "skidpad"
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = false  # the scripted driver is analog; measure the car, not the key ramps
	if car.damage != null and "--log-impacts" in OS.get_cmdline_user_args():
		car.damage.log_impacts = true
	car.contact_monitor = true
	car.max_contacts_reported = 8
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			accel_time = arg.trim_prefix("--time=").to_float()
		elif arg.begins_with("--corner-g="):
			corner_g = arg.trim_prefix("--corner-g=").to_float()
		elif arg.begins_with("--set="):
			var kv := arg.trim_prefix("--set=").split(":")
			overrides[kv[0]] = kv[1].to_float()
	for key: String in overrides:
		car.set(key, overrides[key])


func _physics_process(delta: float) -> void:
	t += delta
	var speed := car.forward_speed * 3.6
	var last := prev_speed
	prev_speed = speed
	if odo_start >= 0.0:
		path_m += car.global_position.distance_to(last_pos)
		last_pos = car.global_position
	for body in car.get_colliding_bodies():
		var what := "%s/%s" % [body.get_parent().get_parent().name, body.get_parent().name]
		if body.get_parent().name == "props":
			what = "props/%s" % body.name
		var entry := "%s at %.1f s (%s, %s), %.0f km/h" % [what, t, phase, car.global_position.snapped(Vector3.ONE * 0.1), speed]
		if collisions.size() < 10 and not collisions.has(entry) and not ",".join(collisions).contains(what):
			collisions.append(entry)
		if phase == "accelerate" and crash_t < 0.0 and not what.begins_with("road/"):
			crash_t = t  # off the road into terrain or objects; the body scraping the road does not count
	if phase != "settle":
		var on_stop := false
		for w in car.wheels:
			var lift: float = w.travel
			max_lift = maxf(max_lift, lift)
			on_stop = on_stop or lift > car.bump_travel * 0.75
		if on_stop:
			bump_stop_ticks += 1
			if phase == "accelerate" and crash_t < 0.0:
				clean_stop_ticks += 1
	match phase:
		"settle":
			if t >= SETTLE_TIME:
				settle_report = _settle_report()
				ride_height = _height_above_road()
				phase = "accelerate"
				t = 0.0
		"accelerate":
			if odo_start < 0.0:
				odo_start = car.odometer_m
				last_pos = car.global_position
			_steer_along_road()
			if crash_t < 0.0:
				_track_crests()
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
					forces.append("%s load %d long %d lat %d slip %.3f/%.1f° lift %+.3f" % ["F" if w.front else "R", roundi(w.normal_load), roundi(w.force.x), roundi(w.force.y), w.slip_ratio, rad_to_deg(w.slip_angle), w.travel])
				print("      ", " | ".join(forces), " | body contacts ", car.get_colliding_bodies().map(func(b): return b.get_parent().name))
			top_speed = maxf(top_speed, speed)
			max_lat_g = maxf(max_lat_g, absf(float(car.telemetry.get("lat_g", 0.0))))
			if t_100 < 0.0 and speed >= 100.0:
				t_100 = t
			if t >= accel_time:
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
			var corner := sqrt(corner_g * 9.81 * step / turn)  # v^2 = a * radius
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
		lifts.append("%+.3f" % (w.travel))
	return "wheels %d, in contact %d, loads N [%s] (weight/4 = %d), wheel lift m [%s]" % [
		car.wheels.size(), contacts, ", ".join(loads), roundi(car.mass * 9.81 / 4.0), ", ".join(lifts)]


func _finish() -> void:
	phase = "done"
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
	print("  speed after %.0f s: %.0f km/h (max %.0f), max lateral %.2f g" % [accel_time, end_speed, top_speed, max_lat_g])
	print("  odometer: %.0f m from the wheels, %.0f m travelled (%+.1f %%)" % [
		car.odometer_m - odo_start, path_m, ((car.odometer_m - odo_start) / maxf(path_m, 1.0) - 1.0) * 100.0])
	print("  gear shifts: %d, max engine speed change per tick %.0f rpm" % [shifts, max_rpm_step])
	print("  braking for corners: %.1f s" % (corner_brakes / float(Engine.physics_ticks_per_second)))
	print("  suspension: max wheel lift %.3f m of %.2f, bump stop %.1f s" % [
		max_lift, car.bump_travel, bump_stop_ticks / float(Engine.physics_ticks_per_second)])
	if car.damage != null:
		print("  damage: %d impacts, average %.2f, max zone %.2f" % [car.damage.impacts, car.damage.total(),
			Array(car.damage.zone_damage).max()])
	print("  body collisions: ", collisions if not collisions.is_empty() else "none")
	print("  braking 100-0 km/h: %s" % ("%.1f m" % brake_distance if brake_distance >= 0.0 else "n/a"))
	_crest_report()
	print("  distance from road at end: %.1f m" % _distance_from_road())
	get_tree().quit()


func _distance_from_road() -> float:
	var slices: Array = main.road_slices
	if slices.is_empty():
		return -1.0
	var p: Array = slices[main._nearest_slice()]["position"]
	return Vector3(p[0], p[1], p[2]).distance_to(car.global_position)


## Vertical curvature of the road at the car (1/m, positive over a crest) from the slopes of the
## slices around it.
func _crest_curvature() -> float:
	var slices: Array = main.road_slices
	if slices.size() < 5:
		return 0.0
	var a: int = main._nearest_slice()
	var b: int = main.slice_ahead(a, 2)
	var c: int = main.slice_ahead(b, 2)
	if a == b or b == c:
		return 0.0
	var pa := _v(slices[a]["position"])
	var pb := _v(slices[b]["position"])
	var pc := _v(slices[c]["position"])
	var d1 := pa.distance_to(pb)
	var d2 := pb.distance_to(pc)
	if d1 < 0.01 or d2 < 0.01:
		return 0.0
	var pitch1 := asin(clampf((pb.y - pa.y) / d1, -1.0, 1.0))
	var pitch2 := asin(clampf((pc.y - pb.y) / d2, -1.0, 1.0))
	return (pitch1 - pitch2) / (0.5 * (d1 + d2))


## Body origin height above the road surface below it (ray down, the car excluded), m.
func _height_above_road() -> float:
	var from := car.global_position + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0)
	query.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(query)
	return from.y - 2.0 - float(hit["position"].y) if not hit.is_empty() else -1.0


func _track_crests() -> void:
	var v := maxf(car.forward_speed, 0.0)
	var ratio := v * v * _crest_curvature() / 9.81
	max_crest = maxf(max_crest, ratio)
	var contacts := 0
	var load := 0.0
	var droop := true
	for w in car.wheels:
		if w.contact:
			contacts += 1
		load += w.normal_load
		droop = droop and (not w.contact or w.travel < -0.95 * car.droop_travel)
	recent.append([t, ratio, droop])
	while not recent.is_empty() and recent[0][0] < t - CREST_WINDOW:
		recent.pop_front()
	if contacts > 0 and load < 0.5 * car.mass * 9.81:
		light_ticks += 1
	# Load the crest geometry allows (highest ratio of the last CREST_WINDOW, the lenient side)
	# against the load the suspension actually puts on the road.
	var crest_now := 0.0
	for r: Array in recent:
		crest_now = maxf(crest_now, r[1])
	if contacts > 0 and crest_now > 0.2:
		crest_ticks += 1
		var share := load / (car.mass * 9.81)
		var deficit := maxf(1.0 - crest_now, 0.0) - share
		if deficit > 0.2:
			thrown_ticks += 1
		if deficit > float(worst_deficit["deficit"]):
			worst_deficit = {"deficit": deficit, "t": t, "kmh": v * 3.6, "crest": crest_now, "share": share}
	if contacts == 0:
		if jump.is_empty():
			var crest := 0.0
			var drooped := false
			for r: Array in recent:
				crest = maxf(crest, r[1])
				drooped = drooped or r[2]
			var bounce := not jumps.is_empty() and t - float(jumps[-1]["end"]) < 1.0
			jump = {"start": t, "kmh": v * 3.6, "crest": crest, "droop": drooped, "height": 0.0, "bounce": bounce}
		jump["height"] = maxf(jump["height"], _height_above_road() - ride_height)
	elif not jump.is_empty():
		jump["end"] = t
		jump["landing"] = car.linear_velocity.y
		jumps.append(jump)
		jump = {}


func _crest_report() -> void:
	var air := 0.0
	var thrown := 0
	var bounces := 0
	for j: Dictionary in jumps:
		air += float(j["end"]) - float(j["start"])
		if float(j["crest"]) < 1.0:
			thrown += 1
		if j["bounce"]:
			bounces += 1
	print("  crests: max v^2/(R g) %.2f, %d jumps (%d below 1, %d bounces), %.2f s in the air, %.2f s light (< 50 %% weight)" % [
		max_crest, jumps.size(), thrown, bounces, air, light_ticks / float(Engine.physics_ticks_per_second)])
	var tps := float(Engine.physics_ticks_per_second)
	var clean := crash_t if crash_t >= 0.0 else accel_time
	print("  crest figures cover %.0f s of driving%s, bump stop %.1f s of it, overrides %s" % [
		clean, " (until the first crash)" if crash_t >= 0.0 else "", clean_stop_ticks / tps, overrides])
	print("  load vs crest (driver %.2f g): %.2f s over crests, %.2f s with the load > 20 %% of the weight below 1 - v^2/(R g)" % [
		corner_g, crest_ticks / tps, thrown_ticks / tps])
	if worst_deficit.has("t"):
		print("    worst: t %.1f, %.0f km/h, v2/Rg %.2f, allowed %.2f of the weight, actual %.2f" % [
			worst_deficit["t"], worst_deficit["kmh"], worst_deficit["crest"], maxf(1.0 - float(worst_deficit["crest"]), 0.0), worst_deficit["share"]])
	for j: Dictionary in jumps.slice(0, 20):
		print("    t %5.1f  %4.0f km/h  v2/Rg %4.2f  air %.2f s  height %.2f m  droop before %s  landing %+.1f m/s%s" % [
			j["start"], j["kmh"], j["crest"], float(j["end"]) - float(j["start"]), j["height"],
			"yes" if j["droop"] else "no", j["landing"], "  (bounce)" if j["bounce"] else ""])
