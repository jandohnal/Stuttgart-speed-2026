extends Node
## Test of the track's water (TrackWater, D-033): waterfalls, rapids and fountains from the
## original's emitters, flowing textures, a car getting wet in the spray and drying off.
##   godot --headless --path game res://tests/water_test.tscn [-- --track=forest]
##   godot --path game res://tests/water_test.tscn -- --shot=<folder>   (window: saves screenshots)
##   --emitter=<n>: stand still FACING slices before the n-th water emitter (fountains, other falls).
##   --at=<slice>: stand still on that slice (forest 1616: the waterfall in view).
##   --look=x,y,z,tx,ty,tz: own camera at that point looking at the other (the foot of a fall).
##   --wet: keep the car soaked (to compare its look with a dry one).
## Forest by default: from slice START drive along the road through the spray of the waterfall by
## the bridge (slices 1630-1634) and on, printing wetness and the emitters running.

const START := 1606  ## forest: about 150 m before the waterfall
const FACING := 6  ## slices (~35 m) before an emitter where --emitter puts the car
const DURATION := 26.0
const STANDING_DURATION := 8.0
const THROTTLE := 0.45
const SHOT_TIMES := [8.0, 11.0, 13.0, 14.0, 15.0, 17.0]
const STANDING_SHOT_TIMES := [3.0, 3.1, 6.0]  ## two close ones show which way the water runs
const WATER_TAGS := ["WF01", "WF02", "WF03", "WF04", "WF05", "WF06", "WF07", "WF08", "RPD1", "RPD2",
	"RPD3", "RPD4", "CTM1", "CTD1", "CTD2", "CTD3", "CSF1", "CSF2"]

var main: Node3D
var car: Car
var water: Node
var t := 0.0
var last_print := -1
var max_wet := 0.0
var wet_at := -1.0  ## s when the car was wettest
var dry_by := -1.0  ## s when it fell below 0.1 after that
var max_active := 0
var standing := false
var soaked := false
var look := PackedFloat64Array()
var eye: Camera3D
var shot_dir := ""
var shot := 0
var shot_times: Array = SHOT_TIMES
var fps := []


func _ready() -> void:
	var track := "forest"
	var emitter := -1
	var at := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			track = arg.trim_prefix("--track=")
		elif arg.begins_with("--shot="):
			shot_dir = arg.trim_prefix("--shot=")
		elif arg.begins_with("--emitter="):
			emitter = arg.trim_prefix("--emitter=").to_int()
		elif arg.begins_with("--look="):
			look = arg.trim_prefix("--look=").split_floats(",")
		elif arg == "--wet":
			soaked = true
		elif arg.begins_with("--at="):
			at = arg.trim_prefix("--at=").to_int()
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = track
	add_child(main)
	car = main.get_node("Car") as Car
	water = main.get_node_or_null("TrackWater")
	car.auto_drive = true
	var road: Road = main.road
	var slice: int = START if track == "forest" else main.start_slice
	if emitter >= 0:
		var pos := _emitter_position(track, emitter)
		slice = road.nearest(pos)
		for k in FACING:
			slice = maxi(slice - 1, 0)
		standing = true
		shot_times = STANDING_SHOT_TIMES
		print("emitter %d at %s, slice %d" % [emitter, pos, slice])
	if at >= 0:
		slice = at
		standing = true
		shot_times = STANDING_SHOT_TIMES
	main._reset_car(slice)  # on the ground: the road is up to 2.5 m above the slice in places
	if main.has_node("Camera"):
		(main.get_node("Camera") as FollowCamera).intro_duration = 0.0


func _emitter_position(track: String, n: int) -> Vector3:
	var data: Variant = OriginalAssets.load_json("GameData/Track/%s/%s_emitters.json" % [track, track])
	var k := 0
	for e: Dictionary in data["emitters"]:
		if e["id"] in WATER_TAGS:
			if k == n:
				return Vector3(e["position"][0], e["position"][1], e["position"][2])
			k += 1
	return car.global_position


func _physics_process(delta: float) -> void:
	t += delta
	car.auto_throttle = 0.0 if standing else THROTTLE
	car.auto_brake = 1.0 if standing else 0.0
	car.auto_steer = 0.0 if standing else _steer_to_road()
	var effects := car.get_node("Effects")
	if soaked:
		effects.wet(1.0)
	var wet: float = effects.wetness()
	if wet > max_wet:
		max_wet = wet
		wet_at = t
		dry_by = -1.0
	if max_wet > 0.5 and dry_by < 0.0 and wet < 0.1:
		dry_by = t
	var c: Dictionary = water.counts() if water != null else {}
	max_active = maxi(max_active, int(c.get("active", 0)))
	if int(t) != last_print:
		last_print = int(t)
		fps.append(Engine.get_frames_per_second())
		print("t=%2d %5.0f km/h  slice %4d  wet %.2f  %3d FPS  water %s" % [last_print, car.forward_speed * 3.6,
			main.road.nearest(car.global_position), wet, Engine.get_frames_per_second(), c])
	if t >= (STANDING_DURATION if standing else DURATION):
		var ok: bool = water != null and int(c.get("emitters", 0)) > 0 and max_active > 0
		if not standing:
			ok = ok and int(c.get("flowing", 0)) > 0 and max_wet > 0.5 and (dry_by > 0.0 or wet < max_wet)
			ok = ok and bool(c.get("waterfall_sound", false))  # forest: the Waterfall pilot
		print("WATER: %s, active at most %d, wettest %.2f at %.1f s, dry (<0.1) at %.1f s, now %.2f" % [
			c, max_active, max_wet, wet_at, dry_by, wet])
		var settled: Array = fps.slice(2)  # the first seconds still load
		var total := 0.0
		for f: float in settled:
			total += f
		print("FPS %.1f average, %.1f lowest" % [total / maxf(settled.size(), 1.0), settled.min() if not settled.is_empty() else 0.0])
		print("RESULT: %s" % ("OK" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)


func _process(_delta: float) -> void:
	if look.size() == 6:
		if eye == null:
			eye = Camera3D.new()
			eye.fov = 60.0
			add_child(eye)
		eye.current = true  # the follow camera takes it back while it settles
		eye.global_position = Vector3(look[0], look[1], look[2])
		eye.look_at(Vector3(look[3], look[4], look[5]))
	if shot_dir.is_empty() or shot >= shot_times.size() or t < shot_times[shot]:
		return
	var path := shot_dir.path_join("water_%d.png" % shot)
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	shot += 1


## Steering towards the road a few slices ahead.
func _steer_to_road() -> float:
	var road: Road = main.road
	var i := road.nearest(car.global_position)
	var p := road.positions[road.ahead(i, 4)]
	var to := car.to_local(p)
	return clampf(-to.x / maxf(-to.z, 5.0) * 3.0, -1.0, 1.0)
