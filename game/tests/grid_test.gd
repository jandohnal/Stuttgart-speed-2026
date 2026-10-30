extends Node
## Headless test of the race grid with opponents (main.gd _add_opponents, D-026 step C):
##   godot --headless --fixed-fps 120 --path game res://tests/grid_test.tscn [-- --opponents=7 --track=farmland]
## The player's car is driven by AIDriver too, so the whole field races. The race is restarted with
## the 3 s countdown (the restart path of the game). Checks: every car is placed on its own slot,
## no car moves or touches another while the countdown runs, every car drives off at GO and covers
## MIN_DISTANCE within DRIVE_TIME. Prints each car's distance, contacts (with cars or anything else)
## and resets, and how long the DRIVE_TIME of simulation took in real time (headless, without
## rendering: physics and scripts of all cars; above DRIVE_TIME the field could not run in real time).

const DRIVE_TIME := 60.0  ## s after GO
const MIN_DISTANCE := 800.0  ## m every car must cover in DRIVE_TIME
const HOLD_TOLERANCE := 0.3  ## m a held car may move during the countdown (settling on its springs)

var main: Node3D
var cars: Array[Car] = []
var drivers: Array[AIDriver] = []
var start_pos: Array[Vector3] = []
var distance: Array[float] = []
var last_slice: Array[int] = []
var car_hits: Array[int] = []
var other_hits: Array[int] = []
var touching: Array[bool] = []
var after_go := -1.0  ## s since GO, -1 = countdown
var moved_in_countdown := 0.0
var countdown_hits := 0
var go_ticks_ms := 0
var failures: Array[String] = []


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = main._user_arg("track") if not main._user_arg("track").is_empty() else "farmland"
	var arg: String = main._user_arg("opponents")
	main.opponent_count = arg.to_int() if arg.is_valid_int() else 3
	add_child(main)
	main.drive_by_ai(0)
	main._restart_race()
	cars.append(main.get_node("Car") as Car)
	cars.append_array(main.opponents)
	for c in cars:
		drivers.append(c.get_node("AIDriver") as AIDriver)
		start_pos.append(c.global_position)
		distance.append(0.0)
		last_slice.append((c.get_node("AIDriver") as AIDriver).slice)
		car_hits.append(0)
		other_hits.append(0)
		touching.append(false)
	print("GRID TEST: %s, %s, %d opponents" % [main.track_name, main.car_key, main.opponents.size()])
	for k in cars.size():
		print("  %s at slice %d, %+.1f m from the centre" % [cars[k].name, drivers[k].slice,
			(cars[k].global_position - main.road.positions[drivers[k].slice]).dot(main.road.rights[drivers[k].slice])])
	_expect(main.opponents.size() == arg.to_int() if arg.is_valid_int() else main.opponents.size() == 3, "all opponents placed")
	for a in cars.size():
		for b in range(a + 1, cars.size()):
			_expect(cars[a].global_position.distance_to(cars[b].global_position) > 3.0, "slots %d and %d apart" % [a, b])
	main.race.started.connect(func() -> void:
		after_go = 0.0
		go_ticks_ms = Time.get_ticks_msec())


func _physics_process(delta: float) -> void:
	if after_go < 0.0:
		for k in cars.size():
			var moved := cars[k].global_position - start_pos[k]
			moved -= main.road.ups[drivers[k].slice] * moved.dot(main.road.ups[drivers[k].slice])  # settling on the springs
			moved_in_countdown = maxf(moved_in_countdown, moved.length())
			if cars[k].side_contacts > 0:
				countdown_hits += 1
		return
	after_go += delta
	for k in cars.size():
		var d := drivers[k]
		var i := last_slice[k]
		for n in AIDriver.TRACK_WINDOW + 1:
			if i == d.slice:
				break
			distance[k] += d.step_length[i]
			i = main.road.ahead(i, 1)
		last_slice[k] = d.slice
		var touch := cars[k].side_contacts > 0
		if touch and not touching[k]:
			var with_car := cars[k].get_colliding_bodies().any(func(b: Node) -> bool: return b is Car)
			if with_car:
				car_hits[k] += 1
			else:
				other_hits[k] += 1
		touching[k] = touch
	if after_go >= DRIVE_TIME:
		_report()


func _report() -> void:
	set_physics_process(false)
	print("GRID TEST RESULT after %.0f s" % DRIVE_TIME)
	print("  countdown: largest move %.2f m, contacts %d" % [moved_in_countdown, countdown_hits])
	for k in cars.size():
		print("  %-10s %5.0f m, hits with cars %d, with other %d, resets %d" % [cars[k].name, distance[k], car_hits[k], other_hits[k], drivers[k].resets])
	print("  %.0f s simulated in %.1f s real time (%d cars, headless)" % [DRIVE_TIME, (Time.get_ticks_msec() - go_ticks_ms) / 1000.0, cars.size()])
	_expect(moved_in_countdown <= HOLD_TOLERANCE, "cars held during the countdown (%.2f m)" % moved_in_countdown)
	_expect(countdown_hits == 0, "no contacts during the countdown")
	for k in cars.size():
		_expect(distance[k] >= MIN_DISTANCE, "%s covered %.0f >= %.0f m" % [cars[k].name, distance[k], MIN_DISTANCE])
	get_tree().quit(1 if not failures.is_empty() else 0)


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)
