extends Node
## Headless test of the race between the start and finish lines on farmland (RaceTimer):
##   godot --headless --path game res://tests/race_test.tscn
## 1. Countdown: the car stays on the start line with full throttle and the engine revs freely.
## 2. After GO the car drives off; a jump across the fields to the finish line does not count,
##    nor does crossing it backwards.
## 3. Passing every checkpoint (the car is moved from one to the next) and crossing the finish
##    line at 30 m/s stops the clock at the moment of the crossing.
## 4. After the finish the keys do nothing (full throttle and steering are held down): the car
##    brakes along the road to a stop and is held there; the clock does not change.
## 5. Restart (Backspace) puts the car back behind the start line with a new countdown.

const COUNTDOWN := 3.0
const CROSS_SPEED := 30.0  # m/s

var main: Node3D
var car: Car
var race: RaceTimer
var t := 0.0
var step := "countdown"
var step_t := 0.0
var start_pos := Vector3.ZERO
var max_countdown_move := 0.0
var max_countdown_rpm := 0.0
var go_time := -1.0
var finish_time := -1.0
var elapsed_at_finish_run := 0.0
var stop_time := -1.0
var stop_from_road := 0.0
var clock_after_stop := 0.0
var failures: Array[String] = []


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "farmland"
	add_child(main)
	car = main.get_node("Car") as Car
	race = main.race
	if race == null:
		print("RACE TEST: no race on farmland")
		get_tree().quit(1)
		return
	race.begin(COUNTDOWN)
	race.started.connect(func() -> void: go_time = t)
	race.finished.connect(func(time: float) -> void: finish_time = time)
	start_pos = car.global_position


func _physics_process(delta: float) -> void:
	if race == null:
		return
	t += delta
	step_t += delta
	match step:
		"countdown":
			Input.action_press("accelerate")
			if race.state == RaceTimer.State.COUNTDOWN:
				# Horizontal only: the car is put 0.4 m above the road and settles.
				var moved := car.global_position - start_pos
				max_countdown_move = maxf(max_countdown_move, Vector2(moved.x, moved.z).length())
				max_countdown_rpm = maxf(max_countdown_rpm, car.rpm)
			elif step_t > COUNTDOWN + 2.0:
				_expect(car.global_position.distance_to(start_pos) > 3.0, "car drives off after GO")
				Input.action_release("accelerate")
				_next("cut")
		"cut":
			if step_t < delta * 1.5:
				_cross_finish(1.0)  # straight to the finish line, no checkpoints
			elif step_t > 1.0:
				_expect(race.state == RaceTimer.State.RUNNING, "finish without checkpoints does not count")
				_next("backwards")
		"backwards":
			if step_t < delta * 1.5:
				_cross_finish(-1.0)
			elif step_t > 1.0:
				_expect(race.state == RaceTimer.State.RUNNING, "crossing the finish backwards does not count")
				_next("checkpoints")
		"checkpoints":
			# One checkpoint per tick: put the car on it and let the timer see it.
			if race.checkpoints_left > 0:
				var cp: Vector3 = race._checkpoints[race._checkpoints.size() - race.checkpoints_left]
				car.reset_to(Transform3D(car.global_basis, cp + Vector3.UP * 0.5))
			else:
				_next("finish")
		"finish":
			if step_t < delta * 1.5:
				elapsed_at_finish_run = race.elapsed
				_cross_finish(1.0)
			elif race.state == RaceTimer.State.FINISHED:
				_next("stopping")
			elif step_t > 1.0:
				_report()
		"stopping":
			# The player keeps full throttle and steering: they must not matter any more.
			Input.action_press("accelerate")
			Input.action_press("steer_left")
			if car.held and stop_time < 0.0:
				stop_time = step_t
			if stop_time >= 0.0 and step_t > stop_time + 1.0 or step_t > 15.0:
				Input.action_release("accelerate")
				Input.action_release("steer_left")
				var p: Array = main.road_slices[main._nearest_slice()]["position"]
				stop_from_road = car.global_position.distance_to(Vector3(p[0], p[1], p[2]))
				clock_after_stop = race.elapsed
				_report()


## Car 3 m before (dir 1) or after (dir -1) the finish line, moving across it at CROSS_SPEED.
func _cross_finish(dir: float) -> void:
	var finish: Dictionary = OriginalAssets.load_json("GameData/Track/farmland/farmland_road.json")["finish"]
	var fwd := Vector3(finish["forward"][0], 0.0, finish["forward"][2]).normalized()
	var p := Vector3(finish["position"][0], finish["position"][1] + 0.5, finish["position"][2]) - fwd * 3.0 * dir
	car.reset_to(Transform3D(Basis.looking_at(fwd, Vector3.UP), p))
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, fwd * CROSS_SPEED * dir)


func _next(name: String) -> void:
	step = name
	step_t = 0.0


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)


func _report() -> void:
	print("RACE TEST")
	print("  checkpoints: %d, countdown: car moved %.3f m, max %d rpm at full throttle" % [
		race._checkpoints.size(), max_countdown_move, roundi(max_countdown_rpm)])
	_expect(max_countdown_move < 0.1, "car held on the start line during the countdown")
	_expect(max_countdown_rpm > 3000.0, "engine revs during the countdown")
	_expect(absf(go_time - COUNTDOWN) < 0.02, "GO after %.1f s (%.3f s)" % [COUNTDOWN, go_time])
	_expect(race.state == RaceTimer.State.FINISHED, "finish counts after all checkpoints")
	# The crossing is ~3 m / 30 m/s = 0.1 s after the car was put before the line.
	var expected := elapsed_at_finish_run + 3.0 / CROSS_SPEED
	print("  finish time %s (%.3f s), expected about %.3f s" % [RaceTimer.format_time(finish_time), finish_time, expected])
	_expect(absf(finish_time - expected) < 0.05, "clock stopped at the crossing")
	print("  after the finish: stopped after %.1f s, %.1f m from the road centre, speed %.2f m/s" % [
		stop_time, stop_from_road, car.linear_velocity.length()])
	_expect(stop_time > 0.0 and car.linear_velocity.length() < 0.3, "car stops by itself after the finish")
	_expect(stop_from_road < 6.0, "car stops on the road")
	_expect(clock_after_stop == finish_time, "clock stays at the finish time")
	_expect(RaceTimer.format_time(372.35) == "6:12.35", "time format m:ss.cc (%s)" % RaceTimer.format_time(372.35))
	main._restart_race()
	_expect(race.state == RaceTimer.State.COUNTDOWN and car.held and race.elapsed == 0.0
		and not car.auto_drive and car.global_position.distance_to(start_pos) < 1.0, "restart: countdown again behind the start line")
	get_tree().quit(1 if not failures.is_empty() else 0)
