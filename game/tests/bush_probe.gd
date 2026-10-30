extends Node
## Temporary probe: drives at the triangles of given textures in the solid groups near the road.
##   godot --headless --path game res://tests/bush_probe.tscn -- --track=coastal --textures=shrb,fhb1

const RUN_UP := 25.0
const MAX_ROAD := 16.0
const MAX_TARGETS := 10

var main: Node3D
var car: Car
var targets: Array[Vector3] = []
var labels: Array[String] = []
var index := -1
var t := 0.0
var target := Vector3.ZERO
var closest := INF
var hits: Array[String] = []
var entry := -1.0
var minv := INF
var touched := {}


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return default


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = _arg("track", "coastal")
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = false
	car.contact_monitor = true
	car.max_contacts_reported = 8
	car.damage.impacted.connect(func(kmh: float, _p: Vector3, _i: float) -> void:
		if index >= 0 and Vector2(car.global_position.x - target.x, car.global_position.z - target.z).length() < 5.0:
			hits.append("%.0f (dv %.0f)" % [kmh, car.damage.last_impact_dv]))
	for item in _arg("targets", "").split(";", false):
		var xyz := item.split(",")
		targets.append(Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2])))
		labels.append(item)
	print("PROBE %s: %d targets" % [main.track_name, targets.size()])
	_next()


func _nearest_slice(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in main.road_slices.size():
		var a: Array = main.road_slices[i]["position"]
		var d := Vector2(a[0] - p.x, a[2] - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


func _next() -> void:
	index += 1
	t = 0.0
	closest = INF
	hits.clear()
	touched.clear()
	entry = -1.0
	minv = INF
	car.repair()
	if index >= targets.size():
		Input.action_release("accelerate")
		get_tree().quit()
		return
	target = targets[index]
	var sl: Dictionary = main.road_slices[_nearest_slice(target)]
	var f := Vector3(sl["forward"][0], 0.0, sl["forward"][2]).normalized()
	var p := Vector3(sl["position"][0], sl["position"][1], sl["position"][2])
	var start := p - f * RUN_UP
	start.y = float(main.road_slices[_nearest_slice(start)]["position"][1]) + 0.4
	car.reset_to(Transform3D(Basis.looking_at((target - start) * Vector3(1, 0, 1), Vector3.UP), start))


func _physics_process(delta: float) -> void:
	if index < 0 or index >= targets.size():
		return
	t += delta
	if t < 0.3:
		return
	Input.action_press("accelerate")
	var to := car.to_local(target)
	var steer := clampf(atan2(-to.x, -to.z) * 3.0, -1.0, 1.0)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if steer > 0.0:
		Input.action_press("steer_left", steer)
	elif steer < 0.0:
		Input.action_press("steer_right", -steer)
	var flat := Vector2(car.global_position.x - target.x, car.global_position.z - target.z).length()
	closest = minf(closest, flat)
	var v := car.forward_speed * 3.6
	if flat < 6.0 and entry < 0.0:
		entry = v
	if entry >= 0.0:
		minv = minf(minv, v)
	for b in car.get_colliding_bodies():
		var path := str(b.get_path())
		if not path.contains("/road/"):
			touched[path.get_slice("/", path.get_slice_count("/") - 2) + "/" + path.get_slice("/", path.get_slice_count("/") - 1)] = true
	if t > 5.0 or (closest < 1.0 and flat > 6.0):
		print("  %s: closest %.1f m, entry %.0f, min %.0f km/h, impacts %s, damage %.2f, touched %s" % [
			labels[index], closest, entry, minv, hits, Array(car.damage.zone_damage).max(), touched.keys()])
		_next()
