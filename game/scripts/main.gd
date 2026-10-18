extends Node3D
## Phase 2 prototype (D-009): an original car on an original track, both loaded at run time from
## decomposed/. Track: project setting stuttgart/track or --track=<name> (default farmland =
## Normandie); car: stuttgart/car or --car=<key in cars.json> (default 356Acoupe16; CARS maps it to
## the model and engine sound). --slice=<n> starts on road slice n instead of the start line;
## --windowed=1 keeps a window. F2 records telemetry to user://telemetry_*.csv, F5 repairs the car,
## F11 full screen, Esc goes back to the menu (scenes/menu.tscn, which sets GameSettings.car_key /
## track_name and the options: steering assist, ABS, traction control, sound, diagnostics).

const DEFAULT_TRACK := "farmland"
const TrackProps := preload("res://scripts/track_props.gd")
const CarAudio := preload("res://scripts/car_audio.gd")
const Materials := preload("res://scripts/materials.gd")
const SFX_BANK := "GameData/Sounds/SND_coll"
const CAR_PHYSICS := "GameData/Simulation/cars.json"
const DEFAULT_CAR := "356Acoupe16"
const ODOMETER_FILE := "user://odometer.cfg"
const ODOMETER_SAVE_INTERVAL := 30.0  ## s
## Menu car -> model (GameData/CarModel/<model>), engine sound set and physics (key in cars.json,
## default the menu key). The original assigns the sound sets in its executable: 356 A (sd1a, idle
## note 29) and 935 (sdxc, flat six to 8000 rpm) are chosen by ear, the others guessed from the
## order of the sets (sd1 356 ... sd9 Boxster, sdx race cars) and still to be tuned by ear. Police
## and "f" models drive like their road car; traffic (eas, eden, postship) has no .sim of its own
## and uses "default". "name" is shown in the menu.
const CARS := {
	"356coupe15": {"name": "356 coupe 1.5", "model": "356_1", "engine_sound": "sd1a", "cylinders": 4},
	"356Acoupe16": {"name": "356 A coupe 1.6", "model": "356a", "engine_sound": "sd1a", "cylinders": 4},
	"356Bcoupe16": {"name": "356 B coupe 1.6", "model": "356b", "engine_sound": "sd1a", "cylinders": 4},
	"550Arace": {"name": "550 A Spyder", "model": "550", "engine_sound": "sd2", "cylinders": 4},
	"901coupe20": {"name": "901 coupe 2.0", "model": "901", "engine_sound": "sd3a", "cylinders": 6},
	"914coupe20": {"name": "914/4 coupe 2.0", "model": "914", "engine_sound": "sd4a", "cylinders": 4},
	"928coupeGTS54": {"name": "928 GTS 5.4", "model": "928", "engine_sound": "sd5", "cylinders": 8},
	"930Tcoupe33": {"name": "930 Turbo 3.3", "model": "930", "engine_sound": "sd6a", "cylinders": 6},
	"935race": {"name": "935 Moby Dick", "model": "935", "engine_sound": "sdxc", "cylinders": 6},
	"944coupe25": {"name": "944 coupe 2.5", "model": "944", "engine_sound": "sd7a", "cylinders": 4},
	"959coupe29": {"name": "959 coupe 2.9", "model": "959", "engine_sound": "sd6b", "cylinders": 6},
	"964coupe36": {"name": "964 Carrera 3.6", "model": "964", "engine_sound": "sd8a", "cylinders": 6},
	"993coupe36": {"name": "993 Carrera 3.6", "model": "993", "engine_sound": "sd8b", "cylinders": 6},
	"996coupe34": {"name": "996 Carrera 3.4", "model": "996", "engine_sound": "sd8c", "cylinders": 6},
	"boxster25": {"name": "Boxster 2.5", "model": "boxster", "engine_sound": "sd9", "cylinders": 6},
	"GT1race": {"name": "GT1", "model": "gt1", "engine_sound": "sdxa", "cylinders": 6},
	"GT2race": {"name": "GT2", "model": "gt2", "engine_sound": "sdxb", "cylinders": 6},
	"GT3race": {"name": "GT3", "model": "gt3", "engine_sound": "sdxb", "cylinders": 6},
	"f901": {"name": "901 (f)", "model": "f901", "engine_sound": "sd3a", "cylinders": 6, "physics": "901coupe20"},
	"f996": {"name": "996 (f)", "model": "f996", "engine_sound": "sd8c", "cylinders": 6, "physics": "996coupe34"},
	"fboxster": {"name": "Boxster (f)", "model": "fboxster", "engine_sound": "sd9", "cylinders": 6, "physics": "boxster25"},
	"cop356": {"name": "356 police", "model": "cop356", "engine_sound": "sd1a", "cylinders": 4, "physics": "356Acoupe16"},
	"cop356_german": {"name": "356 Polizei", "model": "cop356_german", "engine_sound": "sd1a", "cylinders": 4, "physics": "356Acoupe16"},
	"cop930": {"name": "930 police", "model": "cop930", "engine_sound": "sd6a", "cylinders": 6, "physics": "930Tcoupe33"},
	"cop930_german": {"name": "930 Polizei", "model": "cop930_german", "engine_sound": "sd6a", "cylinders": 6, "physics": "930Tcoupe33"},
	"cop993": {"name": "993 police", "model": "cop993", "engine_sound": "sd8b", "cylinders": 6, "physics": "993coupe36"},
	"cop993_german": {"name": "993 Polizei", "model": "cop993_german", "engine_sound": "sd8b", "cylinders": 6, "physics": "993coupe36"},
	"eas1": {"name": "Traffic eas1", "model": "eas1", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas2": {"name": "Traffic eas2", "model": "eas2", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas3": {"name": "Traffic eas3", "model": "eas3", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas4": {"name": "Traffic eas4", "model": "eas4", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas5": {"name": "Traffic eas5", "model": "eas5", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas6": {"name": "Traffic eas6", "model": "eas6", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas7": {"name": "Traffic eas7", "model": "eas7", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas8": {"name": "Traffic eas8", "model": "eas8", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas9": {"name": "Traffic eas9", "model": "eas9", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas10": {"name": "Traffic eas10", "model": "eas10", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eas11": {"name": "Traffic eas11", "model": "eas11", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eden1": {"name": "Traffic eden1", "model": "eden1", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eden2": {"name": "Traffic eden2", "model": "eden2", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eden3": {"name": "Traffic eden3", "model": "eden3", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eden4": {"name": "Traffic eden4", "model": "eden4", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"eden5": {"name": "Traffic eden5", "model": "eden5", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
	"postship": {"name": "Traffic postship", "model": "postship", "engine_sound": "sd1a", "cylinders": 4, "physics": "default"},
}
## Tracks offered in the menu: name in GameData/Track/ -> shown name.
const TRACKS := {
	"farmland": "Farmland (Normandie)",
	"monaco1": "Monaco",
	"monaco2": "Monaco 2",
	"monaco3": "Monaco 3",
	"monaco4": "Monaco 4",
	"monaco5": "Monaco 5",
	"alps": "Alps",
	"autobahn": "Autobahn",
	"canyon": "Canyon",
	"castle": "Castle",
	"coastal": "Coastal",
	"foothills": "Foothills",
	"forest": "Forest",
	"industrial": "Industrial",
}
const MENU_SCENE := "res://scenes/menu.tscn"
const SOLID_GROUPS := ["road", "terrain", "objects"]
const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"reset_car": [KEY_R],
	"telemetry": [KEY_F2],
	"repair": [KEY_F5],
	"trip_reset": [KEY_T],
	"fullscreen": [KEY_F11],
	"menu": [KEY_ESCAPE],
}
const LOG_FIELDS := ["time", "speed_kmh", "rpm", "gear", "throttle", "brake", "steer_deg", "lat_g", "long_g",
	"engine_nm", "load_f", "load_r", "slip_fl", "slip_fr", "slip_rl", "slip_rr",
	"angle_fl", "angle_fr", "angle_rl", "angle_rr", "tc_cut", "boost", "clutch_slip"]

@onready var car: Car = $Car

## Track name in decomposed/GameData/Track/; empty = --track argument or project setting.
var track_name := ""
## Car key in cars.json; empty = --car argument or project setting stuttgart/car.
var car_key := ""
var road_slices: Array = []
var road_segments: Array = []
var start_slice := 0
var prop_counts := {}  ## placed objects per collision type (TrackProps)
var _log: FileAccess
var _log_time := 0.0


func _ready() -> void:
	_setup_input()
	_apply_options()
	# The HUD scales with the window: project setting display/window/stretch (canvas_items).
	GameSettings.go_fullscreen()
	if track_name.is_empty():
		track_name = GameSettings.track_name if not GameSettings.track_name.is_empty() else _track_from_args()
	var folder := "GameData/Track/%s/" % track_name
	var track := OriginalAssets.load_gltf(folder + track_name + ".gltf")
	if track != null:
		Materials.setup_track(track)
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
	if car_key.is_empty():
		car_key = GameSettings.car_key
	if car_key.is_empty():
		car_key = _user_arg("car") if not _user_arg("car").is_empty() else ProjectSettings.get_setting("stuttgart/car", DEFAULT_CAR)
	var info := car_info(car_key)
	var model_path := car_model_path(car_key)
	var engine_sound := "GameData/Sounds/" + str(info["engine_sound"])
	var cars: Variant = OriginalAssets.load_json(CAR_PHYSICS)
	var physics := car_physics_key(car_key)
	if cars is Dictionary and cars.has(physics):
		var model := OriginalAssets.load_gltf(model_path)
		Materials.setup_car(model)
		car.setup(model, cars[physics])
		_load_mileage()
		var damage: Variant = OriginalAssets.load_json(model_path.get_basename() + "_damage.json")
		if damage is Dictionary:
			car.setup_damage(damage)
		var engine: Variant = OriginalAssets.load_json(engine_sound.path_join("engine.json"))
		if engine is Dictionary:
			var audio := CarAudio.new()
			audio.name = "Audio"
			car.add_child(audio)
			audio.rpm_scale = 4.0 / float(info["cylinders"])  # engine.json assumes a four
			audio.setup(car, engine, engine_sound, SFX_BANK)
	else:
		push_error("Car %s (physics %s) not found in %s" % [car_key, physics, CAR_PHYSICS])
	_reset_car(start_slice)


## Options from the menu (GameSettings): driver aids, sound and the HUD diagnostics.
func _apply_options() -> void:
	var options: Dictionary = GameSettings.options
	car.steering_assist = options["steering_assist"]
	car.brake_assist = options["brake_assist"]
	car.traction_control = options["traction_control"]
	AudioServer.set_bus_mute(0, not options["sound"])
	$HUD.diagnostics = options["diagnostics"]


## Mileage is kept per car between runs, but only when the game itself runs: the tests load this
## scene inside their own and must neither read nor change it.
func _keeps_mileage() -> bool:
	return get_parent() == get_tree().root


func _load_mileage() -> void:
	if not _keeps_mileage():
		return
	var cfg := ConfigFile.new()
	cfg.load(ODOMETER_FILE)
	# A car seen for the first time comes with a used car's mileage.
	car.odometer_m = float(cfg.get_value("mileage_m", car_key, randf_range(40000.0, 120000.0) * 1000.0))
	var timer := Timer.new()
	timer.wait_time = ODOMETER_SAVE_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_save_mileage)
	add_child(timer)


func _save_mileage() -> void:
	if not _keeps_mileage():
		return
	var cfg := ConfigFile.new()
	cfg.load(ODOMETER_FILE)
	cfg.set_value("mileage_m", car_key, car.odometer_m)
	cfg.save(ODOMETER_FILE)


func _exit_tree() -> void:
	_save_mileage()
	if _log != null:
		_log.close()
		_log = null


static func car_info(key: String) -> Dictionary:
	return CARS.get(key, {"name": key, "model": key.to_lower(), "engine_sound": "sd1a", "cylinders": 4})


## Key of the car's physics in cars.json.
static func car_physics_key(key: String) -> String:
	return str(car_info(key).get("physics", key))


static func car_model_path(key: String) -> String:
	var model: String = car_info(key)["model"]
	return "GameData/CarModel/%s/%s.gltf" % [model, model]


## True when decomposed/ holds the car's model and physics (cars.json, already parsed).
static func car_available(key: String, cars: Variant) -> bool:
	return cars is Dictionary and cars.has(car_physics_key(key)) and OriginalAssets.exists(car_model_path(key))


static func track_available(name: String) -> bool:
	return OriginalAssets.exists("GameData/Track/%s/%s.gltf" % [name, name])


## Back to the menu, only when this scene is the game itself (not inside a test scene). Freeing
## the scene stops the engine sound; stop it first so no loop is left ringing for a frame.
func _back_to_menu() -> void:
	if get_tree().current_scene != self:
		return
	for player in find_children("*", "AudioStreamPlayer3D", true, false):
		(player as AudioStreamPlayer3D).stop()
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


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


## Index of the slice `ahead` slices after `index` along the road: within its segment, then into
## the segment it continues into ("next", e.g. the laps of Monte Carlo), wrapping closed segments
## and stopping at the end of a road that goes nowhere.
func slice_ahead(index: int, ahead: int) -> int:
	var seg := _segment_of(index)
	if seg.is_empty():
		return (index + ahead) % road_slices.size()
	var i := index
	var left := ahead
	while left > 0:
		var last := int(seg["last"])
		if i < last:
			var step := mini(left, last - i)
			i += step
			left -= step
		elif seg["closed"]:
			i = int(seg["first"])
			left -= 1
		elif seg.get("next") != null:
			seg = road_segments[int(seg["next"])]
			i = int(seg["first"])
			left -= 1
		else:
			break
	return i


func _segment_of(index: int) -> Dictionary:
	for seg: Dictionary in road_segments:
		if index >= int(seg["first"]) and index <= int(seg["last"]):
			return seg
	return {}


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_back_to_menu()
	elif event.is_action_pressed("reset_car"):
		_reset_car(_nearest_slice())
	elif event.is_action_pressed("telemetry"):
		_toggle_log()
	elif event.is_action_pressed("repair"):
		car.repair()
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
