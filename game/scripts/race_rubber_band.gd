class_name RaceRubberBand
extends Node
## Keeps the opponents near the player (D-035). The original multiplied the speed of cars on rails
## by distance (GLUE.BIN: x1.25 .. x0.82 over 600 m); these cars have the player's physics and would
## crash, so each driver has an `effort` steered by its time gap to the player (RaceStandings).
## Within DEAD_GAP it is 0 and the drivers' styles decide; beyond it effort grows with the gap, full
## at FULL_GAP, small enough for the field to stay within reach of a slow player and not to drop
## a fast one. It rises at EFFORT_RATE and fades at FADE_RATE.
## Effort +1 (behind the player): pace up to the grip limit (MAX_GRIP_USE, a careful driver has more
## in reserve) for the corners and braking, engine power up to MAX_POWER for the straights (the one
## thing that is not the same physics as the player's, the same car could never catch up on a
## straight). Effort -1 (ahead of the player): pace down to MIN_PACE and throttle eased to
## MIN_THROTTLE. The slow change means no driver brakes or surges out of the blue. It ends at the
## driver's finish and at the player's.

const DEAD_GAP := 2.0  ## s around the player without any help
const FULL_GAP := 5.0  ## s with full effort
const MAX_GRIP_USE := 0.9  ## share of the tyres' friction a driver catching up plans for
const MAX_POWER := 1.1  ## engine power of a driver catching up
const MIN_PACE := 0.75
const MIN_THROTTLE := 0.5
const EFFORT_RATE := 0.05  ## per s
const FADE_RATE := 0.02  ## per s


## One opponent's state.
class Driver:
	var entry: RaceStandings.Entry
	var driver: AIDriver
	var max_pace := 1.0
	var effort := 0.0  ## -1 waiting for the player .. +1 catching up


var race: RaceTimer
var standings: RaceStandings
var drivers: Array[Driver] = []


func setup(race_timer: RaceTimer, race_standings: RaceStandings) -> void:
	race = race_timer
	standings = race_standings
	process_physics_priority = -2  # before AIDriver
	for k in range(1, standings.entries.size()):
		var d := Driver.new()
		d.entry = standings.entries[k]
		d.driver = d.entry.car.get_node("AIDriver") as AIDriver
		d.max_pace = maxf(sqrt(MAX_GRIP_USE / d.driver.grip_use), 1.0)
		drivers.append(d)
	race.started.connect(reset)


## All back to the drivers' own pace (GO, also after a restart).
func reset() -> void:
	for d in drivers:
		d.effort = 0.0
		_apply(d)


func _physics_process(delta: float) -> void:
	if race.state == RaceTimer.State.COUNTDOWN:
		return
	for d in drivers:
		if d.entry.finish_time >= 0.0:
			d.effort = move_toward(d.effort, 0.0, EFFORT_RATE * delta)
		else:
			d.effort = next_effort(d.effort, standings.gap_to_player(d.entry), delta)
		_apply(d)


## Effort after `delta` s at a gap to the player in s (positive = behind the player).
static func next_effort(effort: float, gap: float, delta: float) -> float:
	var share := clampf((absf(gap) - DEAD_GAP) / (FULL_GAP - DEAD_GAP), 0.0, 1.0)
	var target := share * signf(gap)
	var rate := EFFORT_RATE if absf(target) > absf(effort) or target * effort < 0.0 else FADE_RATE
	return move_toward(effort, target, rate * delta)


func _apply(d: Driver) -> void:
	var up := maxf(d.effort, 0.0)
	var down := maxf(-d.effort, 0.0)
	d.driver.pace = lerpf(1.0, d.max_pace, up) if d.effort >= 0.0 else lerpf(1.0, MIN_PACE, down)
	d.driver.throttle_share = lerpf(1.0, MIN_THROTTLE, down)
	d.entry.car.power_scale = lerpf(1.0, MAX_POWER, up)
