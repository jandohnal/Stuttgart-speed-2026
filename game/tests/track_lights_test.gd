extends Node
## Headless test of the track flares (D-021):
##   godot --headless --path game res://tests/track_lights_test.tscn
## On monaco1 at night: every flare of monaco1_lights.json is placed (world and on placed
## sawhorses), the sawhorse lights hang on their bodies about 1.1 m up and blink once a second,
## wrna and wrnb alternate, the arrow flashers chase, the light pool is lit near the camera and
## the lit windows glow. By day there is no light pool. Missing tracks skip their checks.

const Main := preload("res://scripts/main.gd")
const TrackLights := preload("res://scripts/track_lights.gd")

var failures := 0


func _ready() -> void:
	print("TRACK LIGHTS TEST")
	if not Main.track_available("monaco1") or not OriginalAssets.exists(TrackLights.FLARES):
		print("  skip: monaco1 or flares.json missing in decomposed/")
		_finish()
		return
	var data: Dictionary = OriginalAssets.load_json("GameData/Track/monaco1/monaco1_lights.json")
	var expected: int = data["world"].size()
	for v: Array in data["props"].values():
		expected += v.size()
	for time: String in ["night", "day"]:
		var main: Node3D = preload("res://scenes/main.tscn").instantiate()
		main.track_name = "monaco1"
		main.time_of_day = time
		add_child(main)
		await get_tree().process_frame
		var tl = main.track_lights
		_expect(tl != null and tl.flare_count == expected, "%s: %d flares placed (%d)" % [time, expected, tl.flare_count if tl else -1])
		if tl == null:
			main.queue_free()
			continue
		_expect((tl.lights.size() > 0) == (time == "night"), "%s: light pool %d" % [time, tl.lights.size()])
		if time == "night":
			_night_checks(main, tl)
		main.queue_free()
		await get_tree().process_frame
	_finish()


func _night_checks(main: Node3D, tl: Node3D) -> void:
	var anchors := main.find_children("flare_wrna*", "Node3D", true, false)
	_expect(anchors.size() == 24, "24 sawhorse lights on placed objects (%d)" % anchors.size())
	var on_body := 0
	for a: Node3D in anchors:
		if a.get_parent() is RigidBody3D and absf(a.position.y - 1.12) < 0.1:
			on_body += 1
	_expect(on_body == anchors.size(), "sawhorse lights on their bodies 1.1 m up (%d)" % on_body)
	_expect(tl.is_lit("wrna", 0.1) and not tl.is_lit("wrna", 0.6) and tl.is_lit("wrna", 1.1), "wrna blinks once a second")
	_expect(tl.is_lit("wrna", 0.1) != tl.is_lit("wrnb", 0.1) and tl.is_lit("wrna", 0.6) != tl.is_lit("wrnb", 0.6), "wrna and wrnb alternate")
	var first := []
	for id: String in ["arwa", "arwb", "arwc", "arwd", "arwe"]:
		var t := 0.0
		while not tl.is_lit(id, t) and t < 2.0:
			t += 1.0 / 60.0
		first.append(t)
	_expect(first[0] > first[1] and first[1] > first[2] and first[2] > first[3] and first[3] > first[4], "arrow flashers light in turn e..a %s" % [first])
	_expect(tl.is_lit("strg", 0.3) and tl.is_lit("strg", 0.8), "street lamps steady")
	tl._pick_lights()
	var lit := 0
	for l: OmniLight3D in tl.lights:
		lit += 1 if l.visible else 0
	_expect(lit == tl.lights.size(), "light pool all used near the camera (%d)" % lit)
	_expect(TrackLights.glow_textures(main, "monaco") > 0, "lit windows and neon glow")


func _finish() -> void:
	print("  %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", what)
