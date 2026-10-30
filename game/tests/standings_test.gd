extends Node
## Headless test of the race standings (RaceStandings) with opponents, the player's car driven by
## AIDriver too, from GO until every car has finished:
##   godot --headless --fixed-fps 120 --path game res://tests/standings_test.tscn [-- --track=monaco1 --laps=2 --opponents=3 --front=1]
## --front=1: the player's car starts in front of the grid (it finishes ahead of some opponents:
## their times are estimated).
## Checks: the gaps of the cars ahead are negative and of those behind positive, the order never
## puts a car with less progress ahead, every car has a time at the player's finish (estimated
## behind the player, not before its time), every opponent gets over the finish line and stops
## at least OPPONENT_STOP_AFTER m past it, and the final order and gaps match the finish times.
## Prints the order every REPORT_EVERY s and the results.

const TIME_LIMIT := 1200.0
const REPORT_EVERY := 60.0
const STOP_TIME := 20.0  ## s after crossing the line an opponent must stand

var main: Node3D
var standings: RaceStandings
var t := 0.0
var next_report := 0.0
var order_errors := 0
var sign_errors := 0
var crossed := {}  ## opponent -> [t, position] when it crossed the finish line
var failures: Array[String] = []


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = main._user_arg("track") if not main._user_arg("track").is_empty() else "farmland"
	var count: String = main._user_arg("opponents")
	main.opponent_count = count.to_int() if count.is_valid_int() else 3
	var laps: String = main._user_arg("laps")
	if laps.is_valid_int():
		main.race_laps = laps.to_int()
	add_child(main)
	standings = main.standings
	if standings == null:
		print("STANDINGS TEST: no race on ", main.track_name)
		get_tree().quit(1)
		return
	main.drive_by_ai(1 if main.track_name.begins_with("monaco") else 0)
	main._restart_race()
	if main._user_arg("front") == "1":
		var d := main.opponents[0].get_node("AIDriver") as AIDriver
		var front: int = main.road.ahead(main.start_slice, 2)
		main.car.reset_to(main.road.transform_at(front, d.line_offsets[front]))
		main.ai_driver.slice = front
	standings.car_finished.connect(func(c: Car, time: float) -> void:
		print("  %.1f s: %s finished, %s" % [t, _entry(c).name, RaceTimer.format_time(time)])
		if c == main.car:
			for e: RaceStandings.Entry in standings.entries:
				if e.estimated:
					print("    %s estimated %s" % [e.name, RaceTimer.format_time(e.finish_time)]))
	standings.crossed_line.connect(func(c: Car) -> void:
		crossed[c] = [t, c.global_position]
		print("  %.1f s: %s over the line" % [t, _entry(c).name]))
	print("STANDINGS TEST: %s, %d laps, %d cars, route %d slices" % [main.track_name, main.race.laps, standings.entries.size(), standings.route.size()])


func _entry(c: Car) -> RaceStandings.Entry:
	for e in standings.entries:
		if e.car == c:
			return e
	return null


func _physics_process(delta: float) -> void:
	t += delta
	if main.race.state == RaceTimer.State.COUNTDOWN:
		return
	var order := standings.order()
	var player_place := standings.player_position()
	for k in order.size():
		var e: RaceStandings.Entry = order[k]
		if k > 0 and order[k - 1].finish_time < 0.0 and e.finish_time < 0.0 and e.progress > order[k - 1].progress:
			order_errors += 1
		var gap := standings.gap_to_player(e)
		if (k + 1 < player_place and gap > 0.01) or (k + 1 > player_place and gap < -0.01):
			sign_errors += 1
	if t >= next_report:
		next_report += REPORT_EVERY
		var row := PackedStringArray()
		for e: RaceStandings.Entry in order:
			row.append("%s %+.2f" % [e.name, standings.gap_to_player(e)] if e != standings.entries[0] else "You")
		print("  %4.0f s P%d/%d: %s" % [t, player_place, order.size(), ", ".join(row)])
	var done: bool = main.race.state == RaceTimer.State.FINISHED and crossed.size() == main.opponents.size() \
		and crossed.values().all(func(c: Array) -> bool: return t - float(c[0]) >= STOP_TIME)
	if done or t >= TIME_LIMIT:
		_report()


func _report() -> void:
	set_physics_process(false)
	print("STANDINGS TEST RESULT at %.0f s" % t)
	var order := standings.order()
	for k in order.size():
		var e: RaceStandings.Entry = order[k]
		print("  %d. %-11s %s%s  %+.2f  progress %d/%d%s" % [k + 1, e.name, "~" if e.estimated else " ",
			RaceTimer.format_time(e.finish_time) if e.finish_time >= 0.0 else "  racing", standings.gap_to_player(e),
			e.progress, standings.route.size() * main.race.laps, ", stands" if e.car.held or e.car.linear_velocity.length() < 0.5 else ""])
	_expect(standings.all_finished(), "every car finished")
	_expect(order_errors == 0, "order follows progress (%d ticks wrong)" % order_errors)
	_expect(sign_errors == 0, "gaps negative ahead of the player, positive behind (%d wrong)" % sign_errors)
	var p := standings.entries[0]
	for k in order.size():
		var e: RaceStandings.Entry = order[k]
		if k > 0:
			_expect(e.finish_time >= order[k - 1].finish_time, "%s after %s by finish time" % [e.name, order[k - 1].name])
		if e != p and e.finish_time >= 0.0 and p.finish_time >= 0.0:
			_expect(absf(standings.gap_to_player(e) - (e.finish_time - p.finish_time)) < 0.01, "%s gap = difference of finish times" % e.name)
		if e != p:
			_expect(crossed.has(e.car), "%s over the finish line" % e.name)
			var past: float = e.car.global_position.distance_to(crossed[e.car][1]) if crossed.has(e.car) else 0.0
			_expect(e.car.linear_velocity.length() < 0.5 and past >= main.OPPONENT_STOP_AFTER,
				"%s stopped %.0f m past the line" % [e.name, past])
		if e.estimated:
			_expect(e.finish_time >= p.finish_time, "%s estimated after the player" % e.name)
	get_tree().quit(1 if not failures.is_empty() else 0)


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)
