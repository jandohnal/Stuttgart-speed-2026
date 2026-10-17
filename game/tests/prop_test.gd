extends Node
## Headless test for the placed track objects (TrackProps):
##   godot --headless --path game res://tests/prop_test.tscn
## Puts the car 25 m in front of the first road sign on farmland, drives into it flat out and
## reports the impact speed and how far the sign was thrown.

const RUN_UP := 25.0  # m
const TEST_TIME := 6.0  # s

var main: Node3D
var car: Car
var sign_body: RigidBody3D
var sign_start := Vector3.ZERO
var t := 0.0
var impact_speed := -1.0


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "farmland"
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = false
	car.contact_monitor = true
	car.max_contacts_reported = 8
	for body in main.find_children("*", "RigidBody3D", true, false):
		if body != car and str(body.name).contains("_SGN"):
			sign_body = body as RigidBody3D
			break
	if sign_body == null:
		print("PROP TEST: no sign found")
		get_tree().quit(1)
		return
	sign_start = sign_body.global_position
	# Run-up along the nearest road slice, lined up with the sign.
	var slice: Dictionary = main.road_slices[_nearest_slice(sign_start)]
	var fwd := Vector3(slice["forward"][0], 0.0, slice["forward"][2]).normalized()
	var start := sign_start - fwd * RUN_UP
	var road_point: Array = main.road_slices[_nearest_slice(start)]["position"]
	start.y = float(road_point[1]) + 0.3
	car.reset_to(Transform3D(Basis.looking_at(fwd, Vector3.UP), start))


func _nearest_slice(p: Vector3) -> int:
	var best := 0
	for i in main.road_slices.size():
		var a: Array = main.road_slices[i]["position"]
		var b: Array = main.road_slices[best]["position"]
		if Vector3(a[0], a[1], a[2]).distance_to(p) < Vector3(b[0], b[1], b[2]).distance_to(p):
			best = i
	return best


func _physics_process(delta: float) -> void:
	if sign_body == null:
		return
	t += delta
	if t > 0.5:
		Input.action_press("accelerate")
		# Aim straight at the sign's starting position.
		var to_sign := car.to_local(sign_start)
		var steer := clampf(atan2(-to_sign.x, -to_sign.z) * 3.0, -1.0, 1.0)
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		if steer > 0.0:
			Input.action_press("steer_left", steer)
		elif steer < 0.0:
			Input.action_press("steer_right", -steer)
	if fmod(t, 0.5) < delta:
		print("  t %.1f car %s %.0f km/h contacts %s | sign %s %s" % [t, car.global_position.snapped(Vector3.ONE * 0.1),
			car.forward_speed * 3.6, car.get_colliding_bodies().map(func(b): return b.name),
			sign_body.global_position.snapped(Vector3.ONE * 0.1), "frozen" if sign_body.freeze else "free"])
	if impact_speed < 0.0 and car.get_colliding_bodies().has(sign_body):
		impact_speed = car.forward_speed * 3.6
	if t >= TEST_TIME:
		Input.action_release("accelerate")
		print("PROP TEST")
		print("  sign: %s, mass %.0f kg, props %s" % [sign_body.name, sign_body.mass, main.prop_counts])
		print("  impact: %s" % ("%.0f km/h" % impact_speed if impact_speed >= 0.0 else "none"))
		print("  sign moved %.1f m, now %s, car %.0f km/h" % [
			sign_body.global_position.distance_to(sign_start), "frozen" if sign_body.freeze else "free",
			car.forward_speed * 3.6])
		if car.damage != null:
			print("  car damage: %d impacts, max zone %.2f" % [car.damage.impacts, Array(car.damage.zone_damage).max()])
		get_tree().quit()
