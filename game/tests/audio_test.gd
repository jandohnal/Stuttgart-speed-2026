extends Node
## Headless test for the car sounds (CarAudio; the Dummy audio driver plays silently):
##   godot --headless --path game res://tests/audio_test.tscn
## On the skidpad: full throttle along the circle through the gears, printing the engine loops'
## volume and pitch at every 1000 rpm; then lifts off, then full steering and brake to make the
## tyres squeal. Checks: the equal power crossfade keeps the level steady, pitch stays within
## 0.5..2, no squeal when driving straight, squeal in the slide.

const LOOKAHEAD := 5

var main: Node3D
var car: Car
var audio: Node
var t := 0.0
var phase := "accelerate"
var next_rpm := 1000.0
var problems := PackedStringArray()
var squeal_straight := 0.0
var squeal_slide := 0.0
var levels := []  ## [rpm, load level, coast level]


func _ready() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = "skidpad"
	add_child(main)
	car = main.get_node("Car") as Car
	car.digital_input = false
	audio = car.get_node_or_null("Audio")
	if audio == null:
		print("AUDIO TEST: no CarAudio - run tools/snd2wav.py")
		get_tree().quit(1)


func _process(_delta: float) -> void:
	if audio == null or t < 1.0:
		return
	var lv: Dictionary = audio.engine_levels()
	var load_power := 0.0
	var coast_power := 0.0
	for row: Array in lv.get("load", []):
		load_power += row[1] * row[1]
	for row: Array in lv.get("coast", []):
		coast_power += row[1] * row[1]
	if phase == "accelerate":
		# Squeal is wanted when the driven wheels spin (the 935 in low gears) or the tyres near their
		# limit on the circle; check only calm driving.
		var spin := 0.0
		for w in car.wheels:
			spin = maxf(spin, absf(w.slip_ratio) / car.peak_slip_ratio)
		var lateral := absf(float(car.telemetry.get("lat_g", 0.0)))
		if spin < 0.8 and lateral < 0.3:
			squeal_straight = maxf(squeal_straight, audio.squeal_level())
		if car.rpm >= next_rpm:
			var active := PackedStringArray()
			for row: Array in lv.get("load", []):
				if row[1] > 0.05:
					active.append("%d rpm loop at %.2f vol, pitch %.2f" % [row[0], row[1], row[2]])
					if row[2] < 0.5 or row[2] > 2.0:
						problems.append("pitch %.2f at %d rpm" % [row[2], roundi(car.rpm)])
			print("  %4d rpm gear %d  load power %.2f coast power %.2f | %s" % [roundi(car.rpm), car.gear, load_power,
				coast_power, ", ".join(active)])
			levels.append([car.rpm, load_power, coast_power])
			next_rpm += 1000.0
	elif phase == "slide":
		squeal_slide = maxf(squeal_slide, audio.squeal_level())


func _physics_process(delta: float) -> void:
	t += delta
	if audio == null:
		return
	match phase:
		"accelerate":
			_follow_road()
			Input.action_press("accelerate")
			if t > 25.0:
				Input.action_release("accelerate")
				phase = "lift"
				t = 0.0
		"lift":
			_follow_road()
			if t > 1.0:
				var lv: Dictionary = audio.engine_levels()
				var coast := 0.0
				for row: Array in lv.get("coast", []):
					coast += row[1] * row[1]
				print("  lift-off at %d rpm: coast power %.2f" % [roundi(car.rpm), coast])
				if coast < 0.5:
					problems.append("coast loops silent after lifting off")
				phase = "slide"
				t = 0.0
		"slide":
			Input.action_release("steer_right")
			Input.action_press("steer_left")
			Input.action_press("handbrake")
			if t > 2.0:
				_finish()


func _finish() -> void:
	Input.action_release("steer_left")
	Input.action_release("handbrake")
	var load_levels := levels.map(func(r): return r[1])
	if not load_levels.is_empty() and load_levels.max() > 1.2 * load_levels.min():
		problems.append("load level not steady: %.2f..%.2f" % [load_levels.min(), load_levels.max()])
	if squeal_straight > 0.2:  # the 935's shifts chirp the tyres briefly
		problems.append("squeal %.2f while driving straight" % squeal_straight)
	if squeal_slide < 0.3:
		problems.append("only %.2f squeal in the slide" % squeal_slide)
	print("AUDIO TEST: squeal straight %.2f, in the slide %.2f" % [squeal_straight, squeal_slide])
	print("  ", "OK" if problems.is_empty() else "PROBLEMS: " + "; ".join(problems))
	get_tree().quit(0 if problems.is_empty() else 1)


func _follow_road() -> void:
	var slices: Array = main.road_slices
	var target_i: int = main.slice_ahead(main._nearest_slice(), LOOKAHEAD)
	var p: Array = slices[target_i]["position"]
	var to_target := car.to_local(Vector3(p[0], p[1], p[2]))
	var steer := clampf(atan2(-to_target.x, -to_target.z) * 3.0, -1.0, 1.0)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if steer > 0.0:
		Input.action_press("steer_left", steer)
	elif steer < 0.0:
		Input.action_press("steer_right", -steer)
