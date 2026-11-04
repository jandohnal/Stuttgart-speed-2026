extends Node
## Headless test of passing (AIDriver pass_offset): the player's car stands on the road with the
## brakes on, the opponents start from the grid and must get round it.
##   godot --headless --fixed-fps 120 --path game res://tests/pass_test.tscn [-- --at=150 --park=0 --yaw=0 --opponents=3]
## --at: road slice the car is parked on (farmland), --park: m sideways from racing line 0, --yaw:
## degrees the parked car is turned from the road's direction (90 = across the road),
## --opponents: how many come (default 3, they arrive in a queue). --lead=1: the car starts in front
## of the grid driven by AIDriver, the opponents queue behind it, and it brakes to a stop on the
## slice (the player stopping in front of the field). --pace=0.85 (with --lead=1): the car does not
## stop, it drives the whole way at that share of its speed profile (a slower player); the opponents
## must pass it in motion, where the road gives them room.
## Passes when every opponent is PAST_SLICES beyond the parked car within TIME_LIMIT without a reset
## and no car is damaged beyond MAX_DAMAGE: the opponents may touch or push the car (aggressive but
## careful), not ram it. Prints for each opponent how long it was held up near the parked car
## (within NEAR m and slower than half the speed it came with), and the state of a driver that
## never got past.

const TIME_LIMIT := 240.0
const MAX_DAMAGE := 0.02  ## CarDamage.total() of any car
const PAST_SLICES := 10
const NEAR := 30.0  ## m
const MAX_HELD := 8.0  ## s an opponent may be held up near the parked car

var main: Node3D
var parked: Car
var park_slice := 150
var lead: AIDriver  ## drives the car to its slice (--lead=1), null = parked from the start
var pace := 0.0  ## share of the profile the lead car drives at without stopping (--pace), 0 = it stops
var t := 0.0
var opponents: Array[Car] = []
var drivers: Array[AIDriver] = []
var arrival_speed: Array[float] = []  ## m/s when first within NEAR
var held: Array[float] = []  ## s held up near the parked car
var passed_at: Array[float] = []  ## s, -1 = not yet
var contact: Array[float] = []  ## s touching the parked car
var failures: Array[String] = []


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "farmland"
	var count: String = main._user_arg("opponents")
	main.opponent_count = count.to_int() if count.is_valid_int() else 3
	add_child(main)
	var arg: String = main._user_arg("at")
	park_slice = arg.to_int() if arg.is_valid_int() else park_slice
	var park: String = main._user_arg("park")
	var yaw: String = main._user_arg("yaw")
	opponents = main.opponents
	for o in opponents:
		drivers.append(o.get_node("AIDriver") as AIDriver)
		arrival_speed.append(-1.0)
		held.append(0.0)
		passed_at.append(-1.0)
		contact.append(0.0)
	parked = main.get_node("Car") as Car
	if main._user_arg("lead") == "1":
		var front: int = main.road.ahead(int(main.road_slices.size() > 0) * main.start_slice, 4)
		parked.reset_to(main.road.transform_at(front, drivers[0].line_offsets[front]))
		lead = main.drive_by_ai(0)
		lead.slice = front
		pace = main._user_arg("pace").to_float()
		if pace > 0.0:
			for i in lead.speed_limit.size():
				lead.speed_limit[i] *= pace
			lead.pass_speed_margin = INF  # it only drives slowly, it does not pass
			print("PASS TEST: %d opponents behind a car driving at %.0f %% of the profile" % [opponents.size(), pace * 100.0])
			return
		print("PASS TEST: %d opponents queue behind the car, it stops on slice %d" % [opponents.size(), park_slice])
		return
	var xf: Transform3D = main.road.transform_at(park_slice, drivers[0].line_offsets[park_slice] + park.to_float())
	xf.basis = xf.basis.rotated(main.road.ups[park_slice], deg_to_rad(yaw.to_float()))
	parked.reset_to(xf)
	parked.auto_drive = true
	parked.auto_brake = 1.0
	print("PASS TEST: %d opponents, car parked on slice %d, %+.1f m from line 0, turned %.0f deg (road half width %.1f m, line %+.1f m from the centre)" % [
		opponents.size(), park_slice, park.to_float(), yaw.to_float(), drivers[0]._half_width(park_slice), drivers[0].line_offsets[park_slice]])


func _physics_process(delta: float) -> void:
	t += delta
	if lead != null and pace == 0.0 and lead.enabled and lead.slice >= park_slice:
		lead.enabled = false
		parked.auto_throttle = 0.0
		parked.auto_steer = 0.0
		parked.auto_brake = 1.0
	var all_passed := true
	if main._user_arg("trace") == "1" and fmod(t, 0.25) < delta:
		for k in opponents.size():
			var d := drivers[k]
			var dist := opponents[k].global_position.distance_to(parked.global_position)
			if dist < NEAR * 3.0 and passed_at[k] < 0.0:
				var at: int = main.road.nearest(parked.global_position)
				print("    %.2f %s %.1f m, %.1f m/s (target %.1f, profile %.1f), offset %+.1f (parked at %+.1f, own %+.1f), following %s, passing %s, pushing %s, contacts %d" % [
					t, opponents[k].name, dist, opponents[k].linear_velocity.length(), d.target_speed, d.speed_limit[d.slice], d.pass_offset,
					d._lateral(parked.global_position, at), d._lateral(opponents[k].global_position, d.slice),
					_name(d.following), _name(d.passing), _name(d.pushing), opponents[k].side_contacts])
	for k in opponents.size():
		var o := opponents[k]
		if passed_at[k] >= 0.0:
			continue
		var d := o.global_position.distance_to(parked.global_position)
		var speed := o.linear_velocity.length()
		if d < NEAR and pace == 0.0:
			if arrival_speed[k] < 0.0:
				arrival_speed[k] = speed
			if speed < arrival_speed[k] * 0.5:
				held[k] += delta
		if o.side_contacts > 0 and o.get_colliding_bodies().has(parked):
			contact[k] += delta
		# Past: PAST_SLICES beyond the parked car's slice (it may have been pushed along).
		var parked_slice: int = lead.slice if pace > 0.0 else main.road.nearest(parked.global_position)
		if drivers[k].slice >= parked_slice + PAST_SLICES and drivers[k].slice < parked_slice + 100:
			passed_at[k] = t
		else:
			all_passed = false
	if all_passed or t >= TIME_LIMIT:
		_report()


func _report() -> void:
	set_physics_process(false)
	print("PASS TEST RESULT at %.1f s" % t)
	var damage := parked.damage.total() if parked.damage != null else 0.0
	print("  parked car damage %.3f" % damage)
	_expect(damage <= MAX_DAMAGE, "parked car damage at most %.2f" % MAX_DAMAGE)
	for k in opponents.size():
		var d := drivers[k]
		var o_damage := opponents[k].damage.total() if opponents[k].damage != null else 0.0
		print("  %s: %s, held up %.1f s, contact %.2f s, damage %.3f, resets %d" % [opponents[k].name,
			"past at %.1f s" % passed_at[k] if passed_at[k] >= 0.0 else "NOT past", held[k], contact[k], o_damage, d.resets])
		if passed_at[k] < 0.0:
			print("    slice %d, %.1f m/s, offset %+.1f m, following %s, passing %s, pushing %s, %.1f m from the parked car" % [
				d.slice, opponents[k].linear_velocity.length(), d.pass_offset, _name(d.following), _name(d.passing),
				_name(d.pushing), opponents[k].global_position.distance_to(parked.global_position)])
		_expect(passed_at[k] >= 0.0, "%s got past" % opponents[k].name)
		_expect(held[k] <= MAX_HELD, "%s held up %.1f <= %.0f s" % [opponents[k].name, held[k], MAX_HELD])
		_expect(o_damage <= MAX_DAMAGE and d.resets == 0, "%s undamaged, no resets" % opponents[k].name)
	get_tree().quit(1 if not failures.is_empty() else 0)


static func _name(c: Node) -> String:
	return str(c.name) if c != null else "-"


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)
