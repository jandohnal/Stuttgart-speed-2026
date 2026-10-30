class_name RaceTimer
extends Node
## Point-to-point race from the original's start / finish lines (<track>_road.json "start",
## "finish" from _fstart.scn): a 3-2-1 countdown with the car held on the start line, the clock
## from GO to the finish line, and the best time per track and car.
##
## The clock adds up physics ticks, so pause stops it and runs are repeatable. The finish time
## is interpolated to the moment the car's origin crossed the line within the tick. The finish
## only counts after passing every checkpoint (a road slice every CHECKPOINT_STEP slices between
## start and finish), so cutting across the fields to the finish line does not count.

signal started
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
var car: Car

var _finish := {}
var _checkpoints: Array[Vector3] = []
var _next_checkpoint := 0
var _last_finish_side := 0.0
var _records_file := ""  ## empty: best times are not saved (tests)
var _record_track := ""
var _record_car := ""


## start / finish: the road file's entries {position, forward, line, slice}; slices, segments:
## the road file's slices and segments {first, last, next}.
func setup(race_car: Car, start: Dictionary, finish: Dictionary, slices: Array, segments: Array = []) -> void:
	car = race_car
	_finish = finish
	_checkpoints.clear()
	var first := int(start["slice"])
	var last := int(finish["slice"])
	var bypassed := _bypassed(slices, segments, first)
	for i in range(first + CHECKPOINT_STEP, last - CHECKPOINT_STEP / 2, CHECKPOINT_STEP):
		if not bypassed.any(func(r: Vector2i) -> bool: return i >= r.x and i <= r.y):
			_checkpoints.append(_vec(slices[i]["position"]))


## Stretches [from, to] of the main road (the segment holding slice `main_slice`) that a side road
## bypasses: a chain of other segments linked by "next" leaves the main road near `from` and joins
## it again near `to` (both ends within JOIN_DISTANCE of it).
static func _bypassed(slices: Array, segments: Array, main_slice: int) -> Array[Vector2i]:
	var ranges: Array[Vector2i] = []
	var main := -1
	var linked := {}
	for k in segments.size():
		var seg: Dictionary = segments[k]
		if main_slice >= int(seg["first"]) and main_slice <= int(seg["last"]):
			main = k
		if seg["next"] != null:
			linked[int(seg["next"])] = true
	if main < 0:
		return ranges
	var main_first := int(segments[main]["first"])
	var main_last := int(segments[main]["last"])
	for k in segments.size():
		if k == main or linked.has(k):
			continue
		var tail := k
		var seen := {k: true}
		while segments[tail]["next"] != null and int(segments[tail]["next"]) != main and not seen.has(int(segments[tail]["next"])):
			tail = int(segments[tail]["next"])
			seen[tail] = true
		var enter := _vec(slices[int(segments[k]["first"])]["position"])
		var leave := _vec(slices[int(segments[tail]["last"])]["position"])
		var a := _nearest(slices, main_first, main_last, enter)
		var b := _nearest(slices, main_first, main_last, leave)
		if enter.distance_to(_vec(slices[a]["position"])) < JOIN_DISTANCE and leave.distance_to(_vec(slices[b]["position"])) < JOIN_DISTANCE:
			ranges.append(Vector2i(mini(a, b), maxi(a, b)))
	return ranges


static func _nearest(slices: Array, from: int, to: int, pos: Vector3) -> int:
	var best_i := from
	var best_d := INF
	for i in range(from, to + 1):
		var d := pos.distance_squared_to(_vec(slices[i]["position"]))
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


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
	elapsed = maxf(elapsed - delta * side / maxf(side - prev, 0.0001), 0.0)
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
