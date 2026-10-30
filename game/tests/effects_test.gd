extends Node
## Test of the car effects (CarEffects: tyre marks, dust off the road, sparks):
##   godot --headless --path game res://tests/effects_test.tscn [-- --track=farmland --car=356Acoupe16]
##   godot --path game res://tests/effects_test.tscn -- --shot=<folder>   (window: saves screenshots)
##   --offroad=<m>: start that far right of the road centre (negative: left), facing away from the
##   road, and drive on the ground beside it with full throttle, weaving (dust).
##   --spark-demo: sparks at the front right corner every 0.3 s from 3 s on (to judge their look).
## From the start: full throttle along the road, then full steering with the brake (marks on the
## road), straight on with throttle off the road (dust), until something stops the car (sparks).
## Prints the ground under the wheels once a second and what each effect did.

const RUN_UP := 7.0  ## s of throttle along the road
const SKID := 1.6  ## s of full steering and brake
const DURATION := 22.0
const SHOT_TIMES := [7.6, 8.4, 8.9, 9.4, 9.9]

var main: Node3D
var car: Car
var effects: Node3D
var t := 0.0
var last_print := -1
var max_dust := 0
var max_marks := 0
var spark_time := 0.0
var groups := {}  ## ground group -> wheel ticks
var shot_dir := ""
var shot := 0
var offroad := 0.0
var spark_demo := false
var spark_shot := 0  ## frames since sparks started, for one screenshot of them


func _ready() -> void:
	var track := "farmland"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			track = arg.trim_prefix("--track=")
		elif arg.begins_with("--shot="):
			shot_dir = arg.trim_prefix("--shot=")
		elif arg == "--spark-demo":
			spark_demo = true
		elif arg.begins_with("--offroad="):
			offroad = arg.trim_prefix("--offroad=").to_float()
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = track
	add_child(main)
	car = main.get_node("Car") as Car
	effects = car.get_node("Effects")
	car.auto_drive = true
	if offroad != 0.0:
		var xf: Transform3D = main.road.transform_at(main.start_slice, offroad)
		car.reset_to(Transform3D(xf.basis.rotated(xf.basis.y, -signf(offroad) * PI / 2.0), xf.origin))
	if main.has_node("Camera"):
		(main.get_node("Camera") as FollowCamera).intro_duration = 0.0


func _physics_process(delta: float) -> void:
	t += delta
	if offroad != 0.0:
		car.auto_throttle = 1.0
		car.auto_steer = 0.6 * sin(t * 1.2) if t > 3.0 else 0.0
		car.auto_brake = 0.0
	elif t < RUN_UP:
		car.auto_throttle = 1.0
		car.auto_steer = _steer_to_road()
		car.auto_brake = 0.0
	elif t < RUN_UP + SKID:
		car.auto_throttle = 0.0
		car.auto_steer = 1.0
		car.auto_brake = 0.6
	else:
		car.auto_throttle = 0.7
		car.auto_steer = 0.3
		car.auto_brake = 0.0
	if spark_demo and t > 3.0 and fmod(t, 0.3) < delta:
		effects._on_impact(60.0, Vector3(0.7, 0.3, -1.8), 6000.0)
	for w in car.wheels:
		if w.contact and w.ray.is_colliding():
			var g: String = effects.ground_under(w.ray.get_collider(), w.ray.get_collision_face_index()).get("group", "")
			groups[g] = int(groups.get(g, 0)) + 1
	max_dust = maxi(max_dust, effects.dust_active())
	max_marks = maxi(max_marks, effects.mark_quads())
	if effects.sparks_active():
		spark_time += delta
	if int(t) != last_print:
		last_print = int(t)
		var w: Car.Wheel = car.wheels[0]
		var ground: Dictionary = effects.ground_under(w.ray.get_collider(), w.ray.get_collision_face_index()) if w.ray.is_colliding() else {}
		print("t=%2d %5.0f km/h  wheel 0 on %-8s colour %s  dust %d  marks %d  sparks %s" % [
			last_print, car.forward_speed * 3.6, ground.get("group", "-"),
			(ground.get("color", Color.BLACK) as Color).to_html(false), effects.dust_active(),
			effects.mark_quads(), effects.sparks_active()])
	if t >= DURATION:
		print("EFFECTS: marks %d quads, dust on %d wheels at most, sparks %.2f s, ground ticks %s" % [
			max_marks, max_dust, spark_time, groups])
		var ok := max_marks > 0 and max_dust > 0
		print("RESULT: %s" % ("OK" if ok else "FAIL (marks and dust expected)"))
		get_tree().quit(0 if ok else 1)


func _process(_delta: float) -> void:
	if not shot_dir.is_empty() and spark_shot < 3 and effects.sparks_active():
		spark_shot += 1
		if spark_shot == 3:
			var spark_path := shot_dir.path_join("effects_sparks.png")
			get_viewport().get_texture().get_image().save_png(spark_path)
			print("saved ", spark_path)
	if shot_dir.is_empty() or shot >= SHOT_TIMES.size() or t < SHOT_TIMES[shot]:
		return
	var path := shot_dir.path_join("effects_%d.png" % shot)
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	shot += 1


## Steering towards the road a few slices ahead (run-up only).
func _steer_to_road() -> float:
	var road: Road = main.road
	if road == null or road.size() == 0:
		return 0.0
	var i := road.nearest(car.global_position)
	var ahead: Dictionary = road.slices[road.ahead(i, 4)]
	var p: Array = ahead["position"]
	var to := car.to_local(Vector3(p[0], p[1], p[2]))
	return clampf(-to.x / maxf(-to.z, 5.0) * 3.0, -1.0, 1.0)
