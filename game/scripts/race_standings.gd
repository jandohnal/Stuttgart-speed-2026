class_name RaceStandings
extends Node
## Order of every car in the race and its gap to the player (D-026 step C2), beside RaceTimer
## (which times the player). Each car is followed along the race route (RaceTimer._route: the
## road slices from the start to the finish slice, on a circuit once round) and the moment it
## first reaches each route slice is kept, lap after lap. The gap between two cars is how much
## later the one behind reached the place where the one ahead is now (or was when it finished):
## the usual gap of a timing screen, without guessing speeds.
##
## Progress counts route slices from the start, a lap adding the route's length (a car whose slice
## jumps from the last quarter of the route to the first quarter has begun a new lap). A car on a
## side road keeps the progress it had where it left the route. The order: finished cars by their
## time, then the others by progress, a tie by who got there first, then by who is further along
## the start's direction (the grid before the first route slice). The player finishes with
## RaceTimer (its checkpoints); an opponent when it crosses the finish line with at most
## FINISH_MARGIN route slices of the race left (its line follows the road). The clock is
## RaceTimer.elapsed while the player races.
##
## The race ends with the player's finish: the cars still racing get an estimated time, the
## player's time plus their gap at that moment (they would drive the rest as fast as the player
## did). They keep driving and crossed_line tells when they are over the line, as for the others.

signal car_finished(car: Car, time: float)  ## the player included, not the estimated times
signal crossed_line(car: Car)  ## an opponent over the finish line (finished or with an estimated time)

const TRACK_WINDOW := 12  ## road slices searched ahead for a car every tick
const LOST_DISTANCE := 30.0  ## m from the tracked slice: search the whole road again
const FINISH_MARGIN := 10  ## route slices before the end of the race an opponent must have reached


## One car in the standings.
class Entry:
	var car: Car
	var name := ""
	var slice := 0  ## road slice the car is on
	var lap := 0  ## laps begun before the current one
	var at := 0  ## index in the route of the car's slice (last one on the route)
	var progress := 0  ## route slices reached since the start, laps included
	var times := PackedFloat32Array()  ## clock when each progress step was first reached, -1 = not yet
	var finish_time := -1.0  ## clock at the finish line, -1 = still racing
	var estimated := false  ## finish_time estimated at the player's finish
	var crossed := false  ## over the finish line
	var last_side := 0.0


var race: RaceTimer
var road: Road
var route := PackedInt32Array()
var entries: Array[Entry] = []  ## [0] = the player
var clock := 0.0  ## s since GO
var _route_index := {}  ## road slice -> index in route
var _total := 0  ## progress at the finish: route length x laps
var _start_pos := Vector3.ZERO
var _start_dir := Vector3.FORWARD


func setup(race_timer: RaceTimer, track_road: Road, start: Dictionary, finish: Dictionary) -> void:
	race = race_timer
	road = track_road
	route = RaceTimer._route(road, int(start["slice"]), int(finish["slice"]))
	_route_index.clear()
	for k in route.size():
		_route_index[route[k]] = k
	_total = route.size() * race.laps
	_start_pos = RaceTimer._vec(start["position"])
	_start_dir = RaceTimer._vec(start["forward"]).normalized()
	entries.clear()
	add_car(race.car, "You")
	race.started.connect(reset)
	race.finished.connect(_on_player_finished)


## Adds a car to the standings under `display_name`.
func add_car(car: Car, display_name: String) -> void:
	var e := Entry.new()
	e.car = car
	e.name = display_name
	entries.append(e)
	_reset_entry(e)


## Everyone back to the start of the race (GO, also after a restart).
func reset() -> void:
	clock = race.elapsed
	for e in entries:
		_reset_entry(e)


func _reset_entry(e: Entry) -> void:
	e.times.resize(_total + 1)
	e.times.fill(-1.0)
	e.lap = 0
	e.finish_time = -1.0
	e.estimated = false
	e.crossed = false
	e.slice = road.nearest(e.car.global_position)
	e.at = 0  # the grid is behind the start line
	e.progress = 0
	e.times[0] = clock
	e.last_side = _side_of(e.car)


func _physics_process(delta: float) -> void:
	if race == null or race.state == RaceTimer.State.COUNTDOWN:
		return
	if race.state == RaceTimer.State.RUNNING:
		clock = race.elapsed
	for k in entries.size():
		var e := entries[k]
		if e.crossed:
			continue
		_follow(e)
		if k == 0:
			continue  # the player finishes with RaceTimer
		var side := _side_of(e.car)
		var prev := e.last_side
		e.last_side = side
		if prev < 0.0 and side >= 0.0 and race._on_line(e.car.global_position) and e.progress >= _total - FINISH_MARGIN:
			_finish(e, clock - delta * side / maxf(side - prev, 0.0001))
			e.crossed = true
			crossed_line.emit(e.car)


func _follow(e: Entry) -> void:
	var pos := e.car.global_position
	e.slice = road.nearest_ahead(pos, e.slice, TRACK_WINDOW)
	if road.positions[e.slice].distance_to(pos) > LOST_DISTANCE:
		e.slice = road.nearest(pos)
	var at: int = _route_index.get(e.slice, -1)
	if at < 0:
		return  # off the route (a side road)
	var n := route.size()
	if e.lap == 0 and e.progress < n / 2 and at > n * 3 / 4:
		return  # on a circuit the grid is at the end of the lap, behind the start line
	if at < n / 4 and e.at > n * 3 / 4 and e.progress > n / 2:
		e.lap += 1  # over the start / finish line of a circuit
	elif at > n * 3 / 4 and e.at < n / 4 and e.lap > 0:
		e.lap -= 1  # back over it (reversing, or a reset behind it)
	e.at = at
	var progress := mini(e.lap * n + at, _total - 1)
	if progress > e.progress:
		for i in range(e.progress + 1, progress + 1):
			e.times[i] = clock
		e.progress = progress


## The race is over: every car still racing gets the player's time plus its gap.
func _on_player_finished(time: float) -> void:
	clock = time
	_finish(entries[0], time)
	entries[0].crossed = true
	for e in entries:
		if e.finish_time < 0.0:
			e.finish_time = time + gap_to_player(e)
			e.estimated = true


func _finish(e: Entry, time: float) -> void:
	if e.finish_time >= 0.0:
		return
	e.finish_time = time
	for i in range(e.progress + 1, _total + 1):
		e.times[i] = time
	e.progress = _total
	car_finished.emit(e.car, time)


func _side_of(c: Car) -> float:
	if race._finish.is_empty():
		return 0.0
	var fwd := RaceTimer._vec(race._finish["forward"])
	fwd.y = 0.0
	return (c.global_position - RaceTimer._vec(race._finish["position"])).dot(fwd.normalized())


## Seconds `e` is behind the player (negative: ahead of the player): how much later the car behind
## reached the place the car ahead is on now (or finished on). 0 when level.
func gap_to_player(e: Entry) -> float:
	var p := entries[0]
	if e == p:
		return 0.0
	if e.finish_time >= 0.0 and p.finish_time >= 0.0:
		return e.finish_time - p.finish_time
	if e.progress > p.progress:
		var now := p.finish_time if p.finish_time >= 0.0 else clock
		return -(now - e.times[p.progress])
	if e.progress < p.progress:
		var now_e := e.finish_time if e.finish_time >= 0.0 else clock
		return now_e - p.times[e.progress]
	return e.times[e.progress] - p.times[p.progress]


## The entries in race order.
func order() -> Array[Entry]:
	var sorted: Array[Entry] = entries.duplicate()
	sorted.sort_custom(func(a: Entry, b: Entry) -> bool:
		if (a.finish_time >= 0.0) != (b.finish_time >= 0.0):
			return a.finish_time >= 0.0
		if a.finish_time >= 0.0:
			return a.finish_time < b.finish_time
		if a.progress != b.progress:
			return a.progress > b.progress
		if absf(a.times[a.progress] - b.times[b.progress]) > 0.0001:
			return a.times[a.progress] < b.times[b.progress]
		return (a.car.global_position - _start_pos).dot(_start_dir) > (b.car.global_position - _start_pos).dot(_start_dir))
	return sorted


## 1-based place of the player.
func player_position() -> int:
	return order().find(entries[0]) + 1


## True when every car has finished.
func all_finished() -> bool:
	return entries.all(func(e: Entry) -> bool: return e.finish_time >= 0.0)
