class_name RaceTimer
extends Node
## Race from the start line to the finish line (<track>_road.json "start", "finish": the
## original's from _fstart.scn, on Monte Carlo's circuits our own line that is both): a 3-2-1
## countdown with the car held on the start line, the clock from GO to the finish line (on a circuit
## after the last of `laps` laps), and the best time per track, car and number of laps.
##
## The clock adds up physics ticks, so pause stops it and runs are repeatable. The finish time
## is interpolated to the moment the car's origin crossed the line within the tick. The finish
## only counts after passing every checkpoint (a road slice every CHECKPOINT_STEP slices between
## start and finish, along the road), so cutting across the fields to the finish line does not
## count. On a circuit each lap needs them all again; crossing the line right after GO does not
## count as a lap.

signal started
signal lap_completed(lap: int, time: float)  ## the lap just finished (1 = first) and its time
signal finished(time: float)

enum State { COUNTDOWN, RUNNING, FINISHED }

const CHECKPOINT_STEP := 50  ## road slices between checkpoints (~300 m on farmland)
const CHECKPOINT_RADIUS := 40.0  ## m from the checkpoint slice that counts as passing it
const LINE_HEIGHT := 10.0  ## m above or below the line that still counts (bridges over the road)
const LINE_MARGIN := 2.0  ## m past the line's end points that still counts
const GO_SHOW_TIME := 1.0  ## s the HUD keeps showing GO
const JOIN_DISTANCE := 20.0  ## m from the main road within which a side road's ends join it

var state := State.COUNTDOWN
var countdown := 0.0  ## s left until GO
var elapsed := 0.0  ## s since GO (the final time once finished)
var best := INF  ## best time so far for this track and car, INF = none
var previous_best := INF  ## best time before this run (HUD shows the difference)
var checkpoints_left := 0
var laps := 1
var lap := 1  ## the lap being driven
var lap_start := 0.0  ## elapsed when it began
var last_lap := INF  ## time of the previous lap, INF = none yet
var car: Car

var _finish := {}
var _checkpoints: Array[Vector3] = []
var _next_checkpoint := 0
var _last_finish_side := 0.0
var _records_file := ""  ## empty: best times are not saved (tests)
var _record_track := ""
var _record_car := ""


## start / finish: the road file's entries {position, forward, line, slice}; on a circuit they are
## the same line and the race is `race_laps` laps of it.
func setup(race_car: Car, start: Dictionary, finish: Dictionary, road: Road, race_laps := 1) -> void:
	car = race_car
	_finish = finish
	laps = maxi(race_laps, 1)
	_checkpoints.clear()
	var path := _route(road, int(start["slice"]), int(finish["slice"]))
	var bypassed := _bypassed(road, path)
	for k in range(CHECKPOINT_STEP, path.size() - CHECKPOINT_STEP / 2, CHECKPOINT_STEP):
		if not bypassed.any(func(r: Vector2i) -> bool: return k >= r.x and k <= r.y):
			_checkpoints.append(road.positions[path[k]])


## Slices along the road from `first` to `last` (once round the lap when they are the same).
static func _route(road: Road, first: int, last: int) -> PackedInt32Array:
	var path := PackedInt32Array([first])
	var i := first
	for n in road.size():
		var j := road.ahead(i, 1)
		if j == i or j == last:
			break
		path.append(j)
		i = j
	return path


## Stretches [from, to] of `path` (indices into it) that a side road bypasses: a chain of segments
## off the path, linked by "next", leaves the path near `from` and joins it again near `to` (both
## ends within JOIN_DISTANCE of it).
static func _bypassed(road: Road, path: PackedInt32Array) -> Array[Vector2i]:
	var ranges: Array[Vector2i] = []
	var segments := road.segments
	var on_path := {}
	for i in path:
		on_path[road.segment_index(i)] = true
	var linked := {}
	for seg: Dictionary in segments:
		if seg["next"] != null:
			linked[int(seg["next"])] = true
	for k in segments.size():
		if on_path.has(k) or linked.has(k):
			continue
		var tail := k
		var seen := {k: true}
		while segments[tail]["next"] != null:
			var next := int(segments[tail]["next"])
			if on_path.has(next) or seen.has(next):
				break
			tail = next
			seen[tail] = true
		var enter := road.positions[int(segments[k]["first"])]
		var leave := road.positions[int(segments[tail]["last"])]
		var a := _nearest(road, path, enter)
		var b := _nearest(road, path, leave)
		if enter.distance_to(road.positions[path[a]]) < JOIN_DISTANCE and leave.distance_to(road.positions[path[b]]) < JOIN_DISTANCE:
			ranges.append(Vector2i(mini(a, b), maxi(a, b)))
	return ranges


## Index into `path` of the slice nearest to `pos`.
static func _nearest(road: Road, path: PackedInt32Array, pos: Vector3) -> int:
	var best_k := 0
	var best_d := INF
	for k in path.size():
		var d := pos.distance_squared_to(road.positions[path[k]])
		if d < best_d:
			best_d = d
			best_k = k
	return best_k


## Best times are kept in `file` under [track] car = seconds; without a call nothing is saved.
func keep_records(file: String, track: String, car_key: String) -> void:
	_records_file = file
	_record_track = track
	_record_car = car_key
	var cfg := ConfigFile.new()
	cfg.load(file)
	best = float(cfg.get_value(track, car_key, INF))


## Starts a new run: the car is held for `seconds` of countdown (0 = the clock starts at once).
func begin(seconds: float) -> void:
	state = State.COUNTDOWN
	countdown = seconds
	elapsed = 0.0
	previous_best = best
	lap = 1
	lap_start = 0.0
	last_lap = INF
	_next_checkpoint = 0
	checkpoints_left = _checkpoints.size()
	_last_finish_side = _finish_side()
	if car != null:
		car.held = seconds > 0.0


func _physics_process(delta: float) -> void:
	if car == null:
		return
	match state:
		State.COUNTDOWN:
			countdown -= delta
			if countdown <= 0.0:
				elapsed = -countdown  # the part of the tick after GO
				countdown = 0.0
				state = State.RUNNING
				car.held = false
				started.emit()
		State.RUNNING:
			elapsed += delta
			_check_progress(delta)


## Seconds since GO while it is still shown on the HUD, otherwise a negative value.
func since_go() -> float:
	return elapsed if state == State.RUNNING and elapsed < GO_SHOW_TIME else -1.0


func _check_progress(delta: float) -> void:
	var pos := car.global_position
	if _next_checkpoint < _checkpoints.size() and pos.distance_to(_checkpoints[_next_checkpoint]) < CHECKPOINT_RADIUS:
		_next_checkpoint += 1
		checkpoints_left = _checkpoints.size() - _next_checkpoint
	var side := _finish_side()
	var prev := _last_finish_side
	_last_finish_side = side
	if not (prev < 0.0 and side >= 0.0 and _on_line(pos)) or checkpoints_left > 0:
		return
	# Back to the moment within the tick when the car was on the line.
	var at_line := maxf(elapsed - delta * side / maxf(side - prev, 0.0001), 0.0)
	if lap < laps:
		last_lap = at_line - lap_start
		lap_start = at_line
		lap += 1
		_next_checkpoint = 0
		checkpoints_left = _checkpoints.size()
		lap_completed.emit(lap - 1, last_lap)
		return
	last_lap = at_line - lap_start
	elapsed = at_line
	state = State.FINISHED
	if elapsed < best:
		best = elapsed
		_save_best()
	finished.emit(elapsed)


## Distance of the car in front of the finish line (negative before it), along the driving direction.
func _finish_side() -> float:
	if _finish.is_empty() or car == null:
		return 0.0
	var fwd := _vec(_finish["forward"])
	fwd.y = 0.0
	return (car.global_position - _vec(_finish["position"])).dot(fwd.normalized())


func _on_line(pos: Vector3) -> bool:
	var line: Array = _finish["line"]
	var a := _vec(line[0])
	var b := _vec(line[1])
	if absf(pos.y - (a.y + b.y) * 0.5) > LINE_HEIGHT:
		return false
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var length := ab.length()
	var along := Vector2(pos.x - a.x, pos.z - a.z).dot(ab / length)
	return along > -LINE_MARGIN and along < length + LINE_MARGIN


func _save_best() -> void:
	if _records_file.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(_records_file)
	cfg.set_value(_record_track, _record_car, best)
	cfg.save(_records_file)


## m:ss.cc
static func format_time(seconds: float) -> String:
	var cs := roundi(seconds * 100.0)
	return "%d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
