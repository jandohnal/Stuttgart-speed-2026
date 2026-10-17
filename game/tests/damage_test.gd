extends Node
## Crash test for the car damage (CarDamage):
##   godot --headless --path game res://tests/damage_test.tscn [-- --speed=50 --rear]
##   godot --path game res://tests/damage_test.tscn -- --shot=<folder>   (window: saves damage.png)
## On a flat test ground 500 m below the skidpad (away from its tyre walls) a static wall stands
## ahead (or behind with --rear), far enough to reach the speed; the car
## drives (or reverses) into it holding --speed km/h. One second after the impact it
## reports the zone damage, blend shape values and the mechanical consequences.

const WALL_SIZE := Vector3(10.0, 1.5, 0.6)
const GROUND_Y := -500.0

var main: Node3D
var car: Car
var target_kmh := 50.0
var rear := false
var shot_dir := ""
var t := 0.0
var hit_time := -1.0
var hit_kmh := 0.0
var wall: StaticBody3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="):
			target_kmh = arg.trim_prefix("--speed=").to_float()
		elif arg == "--rear":
			rear = true
		elif arg.begins_with("--shot="):
			shot_dir = arg.trim_prefix("--shot=")
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "skidpad"
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = false
	if car.damage != null:
		car.damage.log_impacts = true
	var ground := StaticBody3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(200.0, 2.0, 1200.0)
	var ground_col := CollisionShape3D.new()
	ground_col.shape = ground_shape
	ground.add_child(ground_col)
	main.add_child(ground)
	ground.global_position = Vector3(0.0, GROUND_Y - 1.0, 0.0)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, GROUND_Y + 0.05, 0.0)))  # facing -Z
	wall = StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = WALL_SIZE
	var col := CollisionShape3D.new()
	col.shape = shape
	wall.add_child(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = WALL_SIZE
	mesh.mesh = box
	wall.add_child(mesh)
	main.add_child(wall)
	var fwd := -car.global_basis.z
	wall.global_transform = Transform3D(car.global_basis, car.global_position
		+ fwd * (-1.0 if rear else 1.0) * maxf(60.0, target_kmh * target_kmh / 30.0) + Vector3.UP * WALL_SIZE.y / 2.0)


func _physics_process(delta: float) -> void:
	t += delta
	var speed := car.forward_speed * 3.6
	if hit_time < 0.0:
		if car.get_colliding_bodies().has(wall):
			hit_time = t
			hit_kmh = absf(speed)
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			Input.action_release("accelerate")
			Input.action_release("brake")
		elif t > 0.5:
			# Hold the speed up to the wall (reverse: the brake key drives backwards at a standstill).
			# Aim at the wall centre (reversing: steer the other way).
			var to_wall := car.to_local(wall.global_position)
			var angle := atan2(-to_wall.x, -to_wall.z) if not rear else -atan2(to_wall.x, to_wall.z)
			var steer := clampf(angle * 3.0, -1.0, 1.0)
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			if steer > 0.0:
				Input.action_press("steer_left", steer)
			elif steer < 0.0:
				Input.action_press("steer_right", -steer)
			var key := "brake" if rear else "accelerate"
			if absf(speed) < target_kmh or (rear and car.gear != -1):
				Input.action_press(key)
			else:
				Input.action_release(key)
		if fmod(t, 2.0) < delta:
			print("  t %.0f  %.0f km/h  gear %d  pos %s" % [t, speed, car.gear, car.global_position.snapped(Vector3.ONE * 0.1)])
		if t > 30.0:
			print("DAMAGE TEST: no impact")
			get_tree().quit(1)
		return
	if t - hit_time >= 1.0:
		_report()


func _report() -> void:
	var d = car.damage
	print("DAMAGE TEST: %s into a wall at %.0f km/h, impact %.0f N*s (threshold %.0f)" % [
		"reversing" if rear else "driving", hit_kmh, d.last_impact, d.threshold])
	var zones := PackedStringArray()
	for z in d.ZONE_COUNT:
		zones.append("%s %.2f" % [d.names[z], d.zone_damage[z]])
	print("  zones: ", ", ".join(zones))
	var shapes := PackedStringArray()
	for mi in car.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D)
		if m.mesh != null and m.mesh.get_blend_shape_count() > 0 and str(m.name).begins_with("Body_"):
			for i in m.mesh.get_blend_shape_count():
				shapes.append("%s %.2f" % [m.mesh.get_blend_shape_name(i), m.get_blend_shape_value(i)])
	print("  blend shapes on Body: ", ", ".join(shapes))
	var wheels := PackedStringArray()
	for w in car.wheels:
		wheels.append("%s%s zone %d toe %+.1f° grip %.2f" % ["F" if w.front else "R", "L" if w.center.x < 0.0 else "R",
			w.zone, rad_to_deg(w.toe), w.grip_factor])
	print("  wheels: ", " | ".join(wheels))
	print("  engine torque %.0f %%, total damage %.2f" % [car.engine_health() * 100.0, d.total()])
	if not shot_dir.is_empty() and DisplayServer.get_name() != "headless":
		wall.visible = false  # the camera looks at the dented side from where the wall stands
		var cam := main.get_node("Camera") as Camera3D
		cam.set_physics_process(false)
		var look := -car.global_basis.z * (-1.0 if rear else 1.0)
		cam.global_position = car.global_position + look * 4.5 + car.global_basis.x * 2.0 + Vector3.UP * 1.6
		cam.look_at(car.global_position + Vector3.UP * 0.5)
		await get_tree().process_frame
		await get_tree().process_frame
		var path := shot_dir.path_join("damage_%s.png" % ("rear" if rear else "front"))
		get_viewport().get_texture().get_image().save_png(path)
		print("  saved ", path)
	get_tree().quit()
