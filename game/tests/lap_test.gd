extends Node
## Headless test of the races on Monte Carlo's circuits (RaceTimer laps, own start / finish line
## from track2gltf, "source": "lap"), one track after the other:
##   godot --headless --path game res://tests/lap_test.tscn [-- --track=monaco2]
## For each: a two-lap race exists; the car stands on the road behind the line (not fallen
## through it); then it is moved along the road ROUTE_STEP slices per tick for two laps. Crossing
## the line right after GO must not count, the first lap must count once, the second must finish.

const TRACKS := ["monaco1", "monaco2", "monaco3", "monaco4", "monaco5"]
const LAPS := 2
const SETTLE := 1.0  ## s on the grid before the run (the car settles on its springs)
const MAX_DROP := 1.0  ## m the car may sink below its grid position while settling
const ROUTE_STEP := 3

var tracks: Array = []
var main: Node3D
var car: Car
var race: RaceTimer
var route := PackedInt32Array()
var at := 0
var t := 0.0
var laps_seen: Array[int] = []
var finished := false
var failures: Array[String] = []


func _ready() -> void:
	var arg := _arg("track")
	tracks = [arg] if not arg.is_empty() else TRACKS.duplicate()
	_load_next()


func _load_next() -> void:
	if main != null:
		main.queue_free()
		main = null
	if tracks.is_empty():
		print("LAP TEST " + ("ok" if failures.is_empty() else "FAILED: " + ", ".join(failures)))
		get_tree().quit(1 if not failures.is_empty() else 0)
		return
	var track: String = tracks.pop_front()
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = track
	main.race_laps = LAPS
	add_child(main)
	car = main.get_node("Car") as Car
	race = main.race
	t = 0.0
	at = 0
	laps_seen.clear()
	finished = false
	if race == null:
		_expect(false, "%s: race exists" % track)
		_load_next.call_deferred()
		return
	_expect(race.laps == LAPS, "%s: %d laps" % [track, LAPS])
	race.lap_completed.connect(func(lap: int, _time: float) -> void: laps_seen.append(lap))
	race.finished.connect(func(_time: float) -> void: finished = true)
	var start := int(race._finish["slice"])
	route = RaceTimer._route(main.road, start, start)


func _physics_process(delta: float) -> void:
	if main == null or race == null:
		return
	t += delta
	if t < SETTLE:
		return
	var track: String = main.track_name
	if at == 0:
		var drop: float = main._grid.origin.y - car.global_position.y
		print("%s: line at slice %d, %d slices a lap, %d checkpoints, car %.2f m below its grid point" % [
			track, int(race._finish["slice"]), route.size(), race._checkpoints.size(), drop])
		_expect(drop < MAX_DROP, "%s: car stands on the road at the start" % track)
	if at < route.size() * LAPS + ROUTE_STEP and not finished:
		var p: Vector3 = main.road.positions[route[at % route.size()]]
		car.reset_to(Transform3D(car.global_basis, p + Vector3.UP * 0.5))
		if at == ROUTE_STEP * 2:
			_expect(laps_seen.is_empty(), "%s: crossing the line after GO is no lap" % track)
		at += ROUTE_STEP
		return
	_expect(laps_seen == [1], "%s: first lap counted once (%s)" % [track, laps_seen])
	_expect(finished, "%s: finish after %d laps" % [track, LAPS])
	set_physics_process(false)
	_load_next()
	set_physics_process.call_deferred(true)


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)


func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return ""
