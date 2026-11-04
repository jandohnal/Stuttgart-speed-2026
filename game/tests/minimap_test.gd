extends Node
## Headless test of the HUD map:
##   godot --headless --path game res://tests/minimap_test.tscn
## Checks the heading-up transform (ahead is up, the car's right is right), the cut at the rim, the
## road lines (links between segments, closed loops), and prints the cost per frame on the largest
## road when the data is there.

const Minimap := preload("res://scripts/minimap.gd")
const LARGE_ROAD := "GameData/Track/farmland/farmland_road.json"

var failures := 0


func _ready() -> void:
	print("MINIMAP TEST")
	_test_transform()
	_test_clip()
	_test_lines()
	_test_cost()
	print("  all passed" if failures == 0 else "  %d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _test_transform() -> void:
	var at := Vector2(100.0, 50.0)
	# Heading +x: the road's own convention has +z on the right (Road.rights).
	var t: Transform2D = Minimap.map_transform(at, Vector2(1.0, 0.0), 0.5)
	_near(t * at, Vector2.ZERO, "the player is in the centre")
	_near(t * (at + Vector2(10.0, 0.0)), Vector2(0.0, -5.0), "ahead is up")
	_near(t * (at + Vector2(0.0, 10.0)), Vector2(5.0, 0.0), "right is right")
	# Heading -z (Godot's forward of an unturned car): +x on the right.
	t = Minimap.map_transform(at, Vector2(0.0, -1.0), 1.0)
	_near(t * (at + Vector2(0.0, -10.0)), Vector2(0.0, -10.0), "ahead is up, turned")
	_near(t * (at + Vector2(10.0, 0.0)), Vector2(10.0, 0.0), "right is right, turned")


func _test_clip() -> void:
	var runs: Array[PackedVector2Array] = Minimap.clip_to_circle(
		PackedVector2Array([Vector2(-20, 0), Vector2(-5, 0), Vector2(5, 0), Vector2(20, 0)]), 10.0)
	_expect(runs.size() == 1, "line across: one run, got %d" % runs.size())
	_near(runs[0][0], Vector2(-10, 0), "cut where it enters")
	_near(runs[0][-1], Vector2(10, 0), "cut where it leaves")
	runs = Minimap.clip_to_circle(PackedVector2Array([Vector2(20, 0), Vector2(20, 5)]), 10.0)
	_expect(runs.is_empty(), "line outside: nothing")
	runs = Minimap.clip_to_circle(PackedVector2Array([Vector2(1, 0), Vector2(2, 0)]), 10.0)
	_expect(runs.size() == 1 and runs[0].size() == 2, "line inside: unchanged")
	runs = Minimap.clip_to_circle(PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 5), Vector2(0, 5)]), 10.0)
	_expect(runs.size() == 2, "out and back in: two runs, got %d" % runs.size())


func _test_lines() -> void:
	var slices: Array = []
	for i in 12:
		slices.append({"position": [float(i), 0.0, float(i) * 2.0], "up": [0, 1, 0], "forward": [1, 0, 0], "right": [0, 0, 1]})
	var road := Road.new({"slices": slices, "segments": [
		{"first": 0, "last": 4, "closed": false, "next": 1},
		{"first": 5, "last": 8, "closed": true, "next": null},
		{"first": 9, "last": 11, "closed": false, "next": null}]})
	var lines: Array[PackedVector2Array] = Minimap.road_lines(road)
	_expect(lines.size() == 3, "one line per segment")
	_near(lines[0][-1], Vector2(5, 10), "a segment runs on to the next one")
	_near(lines[1][-1], lines[1][0], "a closed segment comes back to its start")
	_near(lines[2][-1], Vector2(11, 22), "an open segment ends on its last slice")


func _test_cost() -> void:
	if not OriginalAssets.exists(LARGE_ROAD):
		return
	var map: Control = Minimap.new()
	var player := Node3D.new()
	map.setup(Road.new(OriginalAssets.load_json(LARGE_ROAD)), player)
	var from := Time.get_ticks_usec()
	const ROUNDS := 200
	var count := 0
	for i in ROUNDS:
		count += map.visible_runs(Vector2(328.0, 155.0), Vector2.from_angle(float(i))).size()
	print("  farmland: %.0f us per frame, %d runs" % [float(Time.get_ticks_usec() - from) / ROUNDS, count / ROUNDS])
	_expect(count > 0, "the road is on the map at the start line")
	map.free()
	player.free()


func _near(a: Vector2, b: Vector2, what: String) -> void:
	_expect(a.distance_to(b) < 0.001, "%s: %s, wanted %s" % [what, a, b])


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", what)
