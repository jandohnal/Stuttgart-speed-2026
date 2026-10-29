extends Node
## Headless test of the opponent driver (AIDriver, D-026) alone on the track:
##   godot --headless --fixed-fps 120 --path game res://tests/ai_drive_test.tscn [-- --track=monaco1 --car=935race --line=1 --laps=2 --trace=60:80]
## --trace=from:to prints the driver's state every 0.25 s between those simulated seconds.
## On a track with start and finish lines (farmland by default) the AI drives the race from the
## start line and must cross the finish after every checkpoint; on a lap track without them
## (Monte Carlo) it must drive one lap (--laps=n: n laps) ("lap" length_m in _road.json) along the road. Passes when
## it gets there within TIME_LIMIT and without being put back on the line (resets). Prints the
## time, average and top speed, how far it went over its target speed, the damage, and how often the
## body touched anything (barriers, walls: scrapes stay below the damage threshold) and the largest
## slide (angle between heading and travel). Both must stay under MAX_HITS and MAX_SLIDE_DEG.

const TIME_LIMIT := 900.0  ## s of simulated time
const REPORT_EVERY := 30.0  ## s between progress lines
const MAX_HITS := 0  ## body contacts allowed with walls, barriers or cars (not the ground)
const MAX_SLIDE_DEG := 12.0  ## largest slide allowed above SLIDE_SPEED
const SLIDE_SPEED := 10.0  ## m/s

var main: Node3D
var car: Car
var ai: AIDriver
var race: RaceTimer
var t := 0.0
var next_report := REPORT_EVERY
var distance := 0.0  ## m driven along the line (slices passed)
var goal_distance := 0.0  ## m, lap tracks
var last_slice := 0
var finish_time := -1.0
var max_speed := 0.0
var over_target := 0.0  ## largest speed above the target speed, m/s
var resets_seen := 0
var hits := 0  ## separate body contacts
var hit_time := 0.0  ## s with the body touching something
var touching := false
var max_slide := 0.0  ## deg
var max_slide_at := ""
var trace_from := INF
var trace_to := -INF
var next_trace := 0.0
var failures: Array[String] = []


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = main._user_arg("track") if not main._user_arg("track").is_empty() else "farmland"
	add_child(main)
	car = main.get_node("Car") as Car
	var line: String = main._user_arg("line")
	ai = main.drive_by_ai(line.to_int() if line.is_valid_int() else 0)
	race = main.race
	if race != null:
		race.finished.connect(func(time: float) -> void: finish_time = time)
	else:
		var road_data: Variant = OriginalAssets.load_json("GameData/Track/%s/%s_road.json" % [main.track_name, main.track_name])
		var lap: Variant = road_data.get("lap") if road_data is Dictionary else null
		var laps: String = main._user_arg("laps")
		goal_distance = (float(lap["length_m"]) if lap is Dictionary else 2000.0) * (laps.to_int() if laps.is_valid_int() else 1)
	last_slice = ai.slice
	var trace: String = main._user_arg("trace")
	if trace.contains(":"):
		trace_from = trace.get_slice(":", 0).to_float()
		trace_to = trace.get_slice(":", 1).to_float()
		next_trace = trace_from
	print("AI DRIVE TEST: %s, %s, line %s, %s" % [main.track_name, main.car_key, line if not line.is_empty() else "0",
		"race to the finish" if race != null else "%.0f m along the road" % goal_distance])


func _physics_process(delta: float) -> void:
	t += delta
	if ai.slice != last_slice:
		# Slices passed since the last tick (the tracker only moves forwards; a jump by a reset
		# or a lost car is not counted).
		var i := last_slice
		for n in AIDriver.TRACK_WINDOW + 1:
			if i == ai.slice:
				break
			distance += ai.step_length[i]
			i = main.road.ahead(i, 1)
		last_slice = ai.slice
	var speed := car.linear_velocity.length()
	max_speed = maxf(max_speed, speed)
	if ai.resets != resets_seen:
		resets_seen = ai.resets
		print("  reset %d at %.1f s, slice %d: %s" % [ai.resets, t, ai.slice, ai.reset_reason])
	if not car.held:
		over_target = maxf(over_target, car.forward_speed - ai.target_speed)
	var touch := car.side_contacts > 0
	if touch:
		hit_time += delta
		if not touching:
			hits += 1
			var what := car.get_colliding_bodies().map(func(b: Node) -> String: return str(b.get_parent().name) + "/" + str(b.name))
			print("  hit %d at %.1f s, slice %d, %.0f km/h: %s" % [hits, t, ai.slice, speed * 3.6, ", ".join(what)])
	touching = touch
	if speed > SLIDE_SPEED:
		var flat := car.linear_velocity - car.global_basis.y * car.linear_velocity.dot(car.global_basis.y)
		var slide := rad_to_deg(flat.angle_to(-car.global_basis.z))
		if slide > max_slide:
			max_slide = slide
			max_slide_at = "%.1f s, slice %d, %.0f km/h" % [t, ai.slice, speed * 3.6]
	if t >= next_trace and t <= trace_to:
		next_trace += 0.25
		var off := (car.global_position - ai.line[ai.slice]).dot(main.road.rights[ai.slice])
		print("    %.2f s slice %d v %.1f target %.1f thr %.2f brk %.2f steer %+.2f wheel %+.1f deg off %+.1f m yaw %+.2f lat %+.2f g gear %d damage %.2f wheels off %d rpm %d" % [
			t, ai.slice, car.forward_speed, ai.target_speed, car.auto_throttle, car.auto_brake, car.auto_steer,
			rad_to_deg(car.steer), off, car.angular_velocity.dot(car.global_basis.y), float(car.telemetry.get("lat_g", 0.0)),
			car.gear, car.damage.total() if car.damage != null else 0.0, car.wheels.filter(func(w: Car.Wheel) -> bool: return w.detached).size(), roundi(car.rpm)])
	if t >= next_report:
		next_report += REPORT_EVERY
		print("  %3.0f s: slice %d, %.0f m, %.0f km/h (target %.0f), resets %d" % [
			t, ai.slice, distance, speed * 3.6, ai.target_speed * 3.6, ai.resets])
	var done := finish_time >= 0.0 if race != null else distance >= goal_distance
	if done or t >= TIME_LIMIT:
		_report(done)


func _report(done: bool) -> void:
	set_physics_process(false)
	var time := finish_time if finish_time >= 0.0 else t
	print("AI DRIVE TEST RESULT")
	print("  time %s, %.0f m, average %.0f km/h, top %.0f km/h, max %.1f m/s over the target, damage %.2f" % [
		RaceTimer.format_time(time), distance, distance / maxf(time, 0.01) * 3.6, max_speed * 3.6, over_target,
		car.damage.total() if car.damage != null else 0.0])
	print("  body contacts %d (%.1f s), largest slide %.1f deg (%s)" % [hits, hit_time, max_slide, max_slide_at])
	_expect(done, "reached the %s within %.0f s" % ["finish" if race != null else "end of the lap", TIME_LIMIT])
	_expect(ai.resets == 0, "no resets (%d)" % ai.resets)
	_expect(hits <= MAX_HITS, "body contacts %d <= %d" % [hits, MAX_HITS])
	_expect(max_slide <= MAX_SLIDE_DEG, "largest slide %.1f <= %.0f deg" % [max_slide, MAX_SLIDE_DEG])
	get_tree().quit(1 if not failures.is_empty() else 0)


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)
