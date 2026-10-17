extends Node3D
## Phase 2 prototype (D-009): the original 356 A on an original track (farmland = Normandie by
## default, or skidpad), both loaded at run time from decomposed/. Track: project setting
## stuttgart/track, overridden by the user argument --track=<name>; --slice=<n> starts on road
## slice n instead of the start line; --windowed=1 keeps a window. F3 toggles the steering assist, F4 the ABS,
## F11 full screen. F2 records telemetry to
## user://telemetry_*.csv for comparing with the original game.

const DEFAULT_TRACK := "farmland"
const TrackProps := preload("res://scripts/track_props.gd")
const CAR_MODEL := "GameData/CarModel/356a/356a.gltf"
const CAR_PHYSICS := "GameData/Simulation/cars.json"
const CAR_KEY := "356Acoupe16"
const SOLID_GROUPS := ["road", "terrain", "objects"]
const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"reset_car": [KEY_R],
	"telemetry": [KEY_F2],
	"steering_assist": [KEY_F3],
	"brake_assist": [KEY_F4],
	"fullscreen": [KEY_F11],
}
const LOG_FIELDS := ["time", "speed_kmh", "rpm", "gear", "throttle", "brake", "steer_deg", "lat_g", "long_g"]

@onready var car: Car = $Car

## Track name in decomposed/GameData/Track/; empty = --track argument or project setting.
var track_name := ""
var road_slices: Array = []
var road_segments: Array = []
var start_slice := 0
var prop_counts := {}  ## placed objects per collision type (TrackProps)
var _log: FileAccess
var _log_time := 0.0


func _ready() -> void:
	_setup_input()
	# HUD scales with the window (2D only; 3D renders at full resolution).
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	get_window().content_scale_size = Vector2i(1152, 648)
	# Full screen when run on its own (not in the editor's embedded view, not headless tests).
	if DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor() and _user_arg("windowed").is_empty():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if track_name.is_empty():
		track_name = _track_from_args()
	var folder := "GameData/Track/%s/" % track_name
	var track := OriginalAssets.load_gltf(folder + track_name + ".gltf")
	if track != null:
		add_child(track)
		_add_track_collision(track)
		var objects: Variant = OriginalAssets.load_json(folder + track_name + "_objects.json")
		if objects is Dictionary:
			prop_counts = TrackProps.build(track, objects["objects"])
		var simd := track.find_child("simd", true, false) as Node3D
		if simd != null:
			simd.visible = false  # road data overlay from track2gltf, only for checking
	var road: Variant = OriginalAssets.load_json(folder + track_name + "_road.json")
	if road is Dictionary:
		road_slices = road["slices"]
		road_segments = road.get("segments", [])
		if road.has("start"):
			start_slice = int(road["start"]["slice"])
		var arg := _user_arg("slice")
		if arg.is_valid_int():
			start_slice = clampi(arg.to_int(), 0, road_slices.size() - 1)
	var cars: Variant = OriginalAssets.load_json(CAR_PHYSICS)
	if cars is Dictionary and cars.has(CAR_KEY):
		car.setup(OriginalAssets.load_gltf(CAR_MODEL), cars[CAR_KEY])
	else:
		push_error("Car %s not found in %s" % [CAR_KEY, CAR_PHYSICS])
	_reset_car(start_slice)


func _track_from_args() -> String:
	var arg := _user_arg("track")
	return arg if not arg.is_empty() else ProjectSettings.get_setting("stuttgart/track", DEFAULT_TRACK)


## Value of the user argument --<name>=<value> (after "--" on the command line), or "".
func _user_arg(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.trim_prefix("--%s=" % name)
	return ""


func _setup_input() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			InputMap.action_add_event(action, event)


func _add_track_collision(track: Node3D) -> void:
	for group: String in SOLID_GROUPS:
		var node := track.find_child(group, true, false)
		if node == null:
			continue
		for child in node.find_children("*", "MeshInstance3D", true, false):
			(child as MeshInstance3D).create_trimesh_collision()
		# Two-sided: objects resting on the thin terrain must not drop through its back.
		for shape in node.find_children("*", "CollisionShape3D", true, false):
			var concave := (shape as CollisionShape3D).shape as ConcavePolygonShape3D
			if concave != null:
				concave.backface_collision = true


func _reset_car(slice_index: int) -> void:
	if road_slices.is_empty():
		car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
		return
	var s: Dictionary = road_slices[slice_index]
	var pos := _vec(s["position"])
	var up := _vec(s["up"])
	var rot := Basis.looking_at(_vec(s["forward"]), up)  # car front is -Z, as in the original
	car.reset_to(Transform3D(rot, pos + up * 0.4))


func _nearest_slice() -> int:
	var best := 0
	var best_dist := INF
	for i in road_slices.size():
		var d := _vec(road_slices[i]["position"]).distance_squared_to(car.global_position)
		if d < best_dist:
			best_dist = d
			best = i
	return best


## Index of the slice `ahead` slices after `index`, staying on the same road segment (alternative
## routes are separate segments): wraps on closed segments, stops at the end of open ones.
func slice_ahead(index: int, ahead: int) -> int:
	for seg: Dictionary in road_segments:
		var first := int(seg["first"])
		var last := int(seg["last"])
		if index < first or index > last:
			continue
		if seg["closed"]:
			return first + (index - first + ahead) % (last - first + 1)
		return mini(index + ahead, last)
	return (index + ahead) % road_slices.size()


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_car"):
		_reset_car(_nearest_slice())
	elif event.is_action_pressed("telemetry"):
		_toggle_log()
	elif event.is_action_pressed("steering_assist"):
		car.steering_assist = not car.steering_assist
	elif event.is_action_pressed("brake_assist"):
		car.brake_assist = not car.brake_assist
	elif event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _toggle_log() -> void:
	if _log != null:
		_log.close()
		_log = null
		print("Telemetry stopped")
		return
	var file := "user://telemetry_%s.csv" % Time.get_datetime_string_from_system().replace(":", "-")
	_log = FileAccess.open(file, FileAccess.WRITE)
	if _log == null:
		push_error("Cannot write %s" % file)
		return
	_log.store_line(",".join(LOG_FIELDS))
	_log_time = 0.0
	print("Telemetry -> ", ProjectSettings.globalize_path(file))


func _physics_process(delta: float) -> void:
	if _log == null or car.telemetry.is_empty():
		return
	_log_time += delta
	var row := PackedStringArray()
	for field: String in LOG_FIELDS:
		row.append(str(snappedf(_log_time, 0.001)) if field == "time" else str(car.telemetry.get(field, "")))
	_log.store_line(",".join(row))
