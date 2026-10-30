extends Node
## Headless test for the drive-through parts (bushes, glTF group "drivethrough" from
## tools/track2gltf.py, animdefs.txt drivethrough=1):
##   godot --headless --path game res://tests/bush_test.tscn
## On farmland the group must hold no collision. The car then drives flat out through every bush
## that used to be solid (the BUSH… and SHRABB articles once in the group "objects") from a run-up of
## RUN_UP m (from the first direction with a clear path) and must pass each one without an impact
## (speed change from the damage threshold up), damage or losing speed. Opponents are the same Car
## bodies, so what holds for the car holds for them.

const RUN_UP := 25.0  # m
const PASS_BEYOND := 6.0  # m past the bush centre that counts as through
const RUN_TIME := 5.0  # s per bush at most
const MAX_SPEED_LOSS := 10.0  # km/h lost while passing the bush
const NEAR := 4.0  # m around the bush centre where impacts count
const EYE := 0.7  # m above the ground for the clear-path check

var main: Node3D
var car: Car
var bushes: Array[AABB] = []
var bush_names: Array[String] = []
var index := -1
var t := 0.0
var target := Vector3.ZERO
var fwd := Vector3.FORWARD
var entry_speed := -1.0
var min_speed := INF
var closest := INF
var impacts: Array[String] = []
var contacts := {}
var results: Array[String] = []
var failed := false


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "farmland"
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = false
	car.contact_monitor = true
	car.max_contacts_reported = 8
	car.damage.impacted.connect(func(kmh: float, _point: Vector3, _impulse: float) -> void:
		var flat := Vector2(car.global_position.x - target.x, car.global_position.z - target.z)
		if index >= 0 and flat.length() < NEAR and car.damage.last_impact_dv >= car.damage.threshold_kmh:
			impacts.append("%.0f km/h (dv %.0f)" % [kmh, car.damage.last_impact_dv]))
	var group := main.find_child("drivethrough", true, false)
	if group == null:
		print("BUSH TEST: no drivethrough group (rerun tools/track2gltf.py)")
		get_tree().quit(1)
		return
	var bodies := group.find_children("*", "CollisionObject3D", true, false)
	var shapes := group.find_children("*", "CollisionShape3D", true, false)
	print("BUSH TEST: drivethrough parts %d, collision objects %d, shapes %d" % [
		group.get_child_count(), bodies.size(), shapes.size()])
	failed = not bodies.is_empty() or not shapes.is_empty()
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var name := str(mi.name).to_upper()
		if name.contains("BUSH") or name.contains("SHRABB"):
			bushes.append(mi.global_transform * mi.get_aabb())
			bush_names.append(str(mi.name))
	print("  formerly solid bushes: %d" % bushes.size())
	if bushes.is_empty():
		get_tree().quit(1)
		return
	_next_bush()


func _next_bush() -> void:
	index += 1
	t = 0.0
	entry_speed = -1.0
	min_speed = INF
	closest = INF
	impacts.clear()
	contacts.clear()
	car.repair()
	if index >= bushes.size():
		_finish()
		return
	var box := bushes[index]
	target = box.get_center()
	var slice: Dictionary = main.road_slices[_nearest_slice(target)]
	var road_fwd := Vector3(slice["forward"][0], 0.0, slice["forward"][2]).normalized()
	# Along the road first, then round in 30 degree steps: the first run-up with nothing solid
	# (fence, wall, cliff) from its start to PASS_BEYOND past the bush. The bush has no collision,
	# so the ray passes it.
	var ground := _ground_y(target)
	var start := Vector3.ZERO
	for k in 12:
		fwd = road_fwd.rotated(Vector3.UP, deg_to_rad(30.0 * k))
		start = target - fwd * RUN_UP
		start.y = _ground_y(start)
		var beyond := target + fwd * (PASS_BEYOND + 2.0)
		beyond.y = _ground_y(beyond)
		if absf(start.y - ground) < 3.0 and absf(beyond.y - ground) < 3.0 \
				and _clear(start + Vector3.UP * EYE, Vector3(target.x, ground + EYE, target.z)) \
				and _clear(Vector3(target.x, ground + EYE, target.z), beyond + Vector3.UP * EYE):
			break
	start.y += 0.4
	car.reset_to(Transform3D(Basis.looking_at(fwd, Vector3.UP), start))


func _ground_y(p: Vector3) -> float:
	var space := car.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 60.0, p + Vector3.DOWN * 60.0)
	query.exclude = [car.get_rid()]
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else p.y


func _clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [car.get_rid()]
	return car.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _nearest_slice(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in main.road_slices.size():
		var a: Array = main.road_slices[i]["position"]
		var d := Vector3(a[0], a[1], a[2]).distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


func _physics_process(delta: float) -> void:
	if index < 0 or index >= bushes.size():
		return
	t += delta
	if t < 0.3:
		return
	Input.action_press("accelerate")
	var to_bush := car.to_local(target)
	var steer := clampf(atan2(-to_bush.x, -to_bush.z) * 3.0, -1.0, 1.0)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if steer > 0.0:
		Input.action_press("steer_left", steer)
	elif steer < 0.0:
		Input.action_press("steer_right", -steer)
	var flat := Vector2(car.global_position.x - target.x, car.global_position.z - target.z)
	var along := Vector2(fwd.x, fwd.z).dot(flat)
	var speed := car.forward_speed * 3.6
	closest = minf(closest, flat.length())
	for body in car.get_colliding_bodies():
		if not str(body.get_path()).contains("/road/") and not str(body.get_path()).contains("/terrain/"):
			contacts[str(body.name)] = true
	if along > -4.0 and entry_speed < 0.0:
		entry_speed = speed
	if entry_speed >= 0.0:
		min_speed = minf(min_speed, speed)
	if along > PASS_BEYOND or t > RUN_TIME:
		var through := along > PASS_BEYOND and closest < 1.5
		var loss := entry_speed - min_speed if entry_speed >= 0.0 else INF
		var damage: float = Array(car.damage.zone_damage).max()
		var ok := through and loss <= MAX_SPEED_LOSS and damage == 0.0 and impacts.is_empty()
		failed = failed or not ok
		results.append("  %s %s: size %s, through %s (closest %.1f m), entry %.0f km/h, loss %.0f km/h, impacts %s, damage %.2f, contacts %s" % [
			"ok  " if ok else "FAIL", bush_names[index], bushes[index].size.snapped(Vector3.ONE * 0.1), through, closest,
			entry_speed, loss, impacts, damage, contacts.keys()])
		Input.action_release("accelerate")
		_next_bush()


func _finish() -> void:
	Input.action_release("accelerate")
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	for line in results:
		print(line)
	print("BUSH TEST %s" % ("FAILED" if failed else "OK"))
	get_tree().quit(1 if failed else 0)
