extends Node
## Headless test of the rubber band (RaceRubberBand): the player's car driven by AIDriver at a share
## of its speed profile, three opponents, from GO to the player's finish:
##   godot --headless --fixed-fps 120 --path game res://tests/rubber_test.tscn [-- --track=monaco1 --laps=2 --player=0.85 --rubber=1]
## --player: the player's pace; below 1 it also eases the throttle like a driver waiting (slow
## player: the opponents must wait), above 1 it is faster than the field (they must catch up).
## --rubber=0 runs the same race without the band, for comparison (nothing is checked but the driving).
## Checks after SETTLE_TIME: no opponent further than MAX_AHEAD s ahead of the player or MAX_BEHIND s
## behind it, and for all the time no resets, no damage beyond MAX_DAMAGE, no slide beyond MAX_SLIDE.
## Prints every slide beyond MAX_SLIDE with the driver's state.

const TIME_LIMIT := 1200.0
const REPORT_EVERY := 60.0
const SETTLE_TIME := 60.0
const MAX_AHEAD := 20.0  ## s
const MAX_BEHIND := 15.0  ## s
const MAX_DAMAGE := 0.03  ## a minor contact in the pack
const MAX_SLIDE := 12.0  ## deg, not counting TOUCH_TIME after a contact with another car
const TOUCH_TIME := 2.0  ## s

var main: Node3D
var standings: RaceStandings
var rubber := true
var t := 0.0
var next_report := 0.0
var max_ahead := {}  ## Entry -> s
var max_behind := {}
var max_slide := {}
var last_touch := {}  ## Entry -> t of the last contact with another car
var last_slide := {}  ## Entry -> t of the slide last seen beyond MAX_SLIDE
var failures: Array[String] = []


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = main._user_arg("track") if not main._user_arg("track").is_empty() else "farmland"
	main.opponent_count = 3
	var laps: String = main._user_arg("laps")
	if laps.is_valid_int():
		main.race_laps = laps.to_int()
	add_child(main)
	standings = main.standings
	rubber = main.rubber_band != null
	var line := 1 if main.track_name.begins_with("monaco") else 0
	var player: AIDriver = main.drive_by_ai(line)
	var pace: float = main._user_arg("player").to_float()
	if pace > 0.0:
		player.pace = pace
		if pace < 1.0:
			player.throttle_share = 0.7
	main._restart_race()
	for e in standings.entries:
		max_ahead[e] = 0.0
		max_behind[e] = 0.0
		max_slide[e] = 0.0
	print("RUBBER TEST: %s, %d laps, player's pace %.2f, rubber band %s" % [main.track_name, main.race.laps, player.pace, "on" if rubber else "off"])


func _physics_process(delta: float) -> void:
	t += delta
	if main.race.state == RaceTimer.State.COUNTDOWN:
		return
	var racing: bool = main.race.state == RaceTimer.State.RUNNING
	for k in range(1, standings.entries.size()):
		var e: RaceStandings.Entry = standings.entries[k]
		var d := e.car.get_node("AIDriver") as AIDriver
		if racing and e.finish_time < 0.0:
			for body in e.car.get_colliding_bodies():
				if body is Car:
					last_touch[e] = t
			if t - float(last_touch.get(e, -10.0)) > TOUCH_TIME:
				max_slide[e] = maxf(max_slide[e], d.slide_deg)
			if d.slide_deg > MAX_SLIDE and t - float(last_slide.get(e, -10.0)) > 2.0:
				var hits := PackedStringArray()
				for body in e.car.get_colliding_bodies():
					hits.append(str(body.name))
				print("    %.1f s %s slides %.0f deg at %.0f m/s on slice %d: pace %.2f, offset %+.1f, passing %s, following %s, touching [%s]" % [
					t, e.name, d.slide_deg, e.car.linear_velocity.length(), d.slice, d.pace, d.pass_offset,
					d.passing.name if d.passing != null else "-", d.following.name if d.following != null else "-", ", ".join(hits)])
			if d.slide_deg > MAX_SLIDE:
				last_slide[e] = t
			if t > SETTLE_TIME:
				var gap := standings.gap_to_player(e)
				max_ahead[e] = maxf(max_ahead[e], -gap)
				max_behind[e] = maxf(max_behind[e], gap)
	if t >= next_report:
		next_report += REPORT_EVERY
		var row := PackedStringArray()
		for k in range(1, standings.entries.size()):
			var e: RaceStandings.Entry = standings.entries[k]
			var d := e.car.get_node("AIDriver") as AIDriver
			row.append("%s %+.1f (pace %.2f, power %.2f)" % [e.name.get_slice(" ", 1), standings.gap_to_player(e), d.pace, e.car.power_scale])
		print("  %4.0f s: %s" % [t, ", ".join(row)])
	if not racing or t >= TIME_LIMIT:
		_report()


func _report() -> void:
	set_physics_process(false)
	print("RUBBER TEST RESULT at %.0f s" % t)
	for e: RaceStandings.Entry in standings.order():
		print("  %-14s %s%s" % [e.name, "~" if e.estimated else " ", RaceTimer.format_time(e.finish_time) if e.finish_time >= 0.0 else "racing"])
	_expect(main.race.state == RaceTimer.State.FINISHED, "the player finished")
	for k in range(1, standings.entries.size()):
		var e: RaceStandings.Entry = standings.entries[k]
		var d := e.car.get_node("AIDriver") as AIDriver
		var damage: float = e.car.damage.total() if e.car.damage != null else 0.0
		print("  %s: furthest ahead %.1f s, behind %.1f s, slide %.1f deg, damage %.3f, resets %d %s" % [e.name, max_ahead[e], max_behind[e], max_slide[e], damage, d.resets, d.reset_reason])
		if rubber:
			_expect(max_ahead[e] <= MAX_AHEAD, "%s at most %.0f s ahead" % [e.name, MAX_AHEAD])
			_expect(max_behind[e] <= MAX_BEHIND, "%s at most %.0f s behind" % [e.name, MAX_BEHIND])
		_expect(d.resets == 0, "%s no resets" % e.name)
		_expect(damage <= MAX_DAMAGE, "%s damage at most %.2f" % [e.name, MAX_DAMAGE])
		_expect(max_slide[e] <= MAX_SLIDE, "%s slide at most %.0f deg" % [e.name, MAX_SLIDE])
	get_tree().quit(1 if not failures.is_empty() else 0)


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)
