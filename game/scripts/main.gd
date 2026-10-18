extends Node3D
## Phase 2 prototype (D-009): an original car on an original track, both loaded at run time from
## decomposed/. Track: project setting stuttgart/track or --track=<name> (default farmland =
## Normandie); car: stuttgart/car or --car=<key in cars.json> (default 356Acoupe16; CARS maps it to
## the model and engine sound). --slice=<n> starts on road slice n instead of the start line;
## --windowed=1 keeps a window. F2 records telemetry to user://telemetry_*.csv, F5 repairs the car,
## F11 full screen, Esc goes back to the menu (scenes/menu.tscn, which sets GameSettings.car_key /
## track_name, time_of_day and the options: steering assist, ABS, traction control, sound,
## diagnostics). Time of day: GameSettings.time_of_day, else --time=day|night or project setting
## stuttgart/time (default day); the sky and sun come from SkyLighting, the car lamps from CarLights.
## Paint: GameSettings.car_color, else --color=<#rrggbb>; empty = the body texture untinted.

const DEFAULT_TRACK := "farmland"
const TrackProps := preload("res://scripts/track_props.gd")
const CarAudio := preload("res://scripts/car_audio.gd")
const Materials := preload("res://scripts/materials.gd")
const SkyLighting := preload("res://scripts/sky_lighting.gd")
const CarLights := preload("res://scripts/car_lights.gd")
const DEFAULT_TIME := "day"
## Times of day offered in the menu -> shown name.
const TIMES := {"day": "Den", "night": "Noc"}
const SFX_BANK := "GameData/Sounds/SND_coll"
const CAR_PHYSICS := "GameData/Simulation/cars.json"
## Original paint palettes (tools/car_colors.py from FEData/Data/nfs5.car).
const CAR_COLORS := "FEData/Data/car_colors.json"
const DEFAULT_CAR := "356Acoupe16"
const ODOMETER_FILE := "user://odometer.cfg"
const ODOMETER_SAVE_INTERVAL := 30.0  ## s
## Model (GameData/CarModel/<model>) -> engine sound set. The original assigns the sound sets in its
## executable: 356 A (sd1a, idle note 29) and 935 (sdxc, flat six to 8000 rpm) are chosen by ear,
## the others guessed from the order of the sets (sd1 356 ... sd9 Boxster, sdx race cars) and still
## to be tuned by ear.
const MODELS := {
	"356_1": {"engine_sound": "sd1a", "cylinders": 4},
	"356a": {"engine_sound": "sd1a", "cylinders": 4},
	"356b": {"engine_sound": "sd1a", "cylinders": 4},
	"550": {"engine_sound": "sd2", "cylinders": 4},
	"901": {"engine_sound": "sd3a", "cylinders": 6},
	"f901": {"engine_sound": "sd3a", "cylinders": 6},
	"914": {"engine_sound": "sd4a", "cylinders": 4},
	"928": {"engine_sound": "sd5", "cylinders": 8},
	"930": {"engine_sound": "sd6a", "cylinders": 6},
	"935": {"engine_sound": "sdxc", "cylinders": 6},
	"944": {"engine_sound": "sd7a", "cylinders": 4},
	"959": {"engine_sound": "sd6b", "cylinders": 6},
	"964": {"engine_sound": "sd8a", "cylinders": 6},
	"993": {"engine_sound": "sd8b", "cylinders": 6},
	"996": {"engine_sound": "sd8c", "cylinders": 6},
	"f996": {"engine_sound": "sd8c", "cylinders": 6},
	"boxster": {"engine_sound": "sd9", "cylinders": 6},
	"fboxster": {"engine_sound": "sd9", "cylinders": 6},
	"gt1": {"engine_sound": "sdxa", "cylinders": 6},
	"gt2": {"engine_sound": "sdxb", "cylinders": 6},
	"gt3": {"engine_sound": "sdxb", "cylinders": 6},
	"cop356": {"engine_sound": "sd1a", "cylinders": 4},
	"cop356_german": {"engine_sound": "sd1a", "cylinders": 4},
	"cop930": {"engine_sound": "sd6a", "cylinders": 6},
	"cop930_german": {"engine_sound": "sd6a", "cylinders": 6},
	"cop993": {"engine_sound": "sd8b", "cylinders": 6},
	"cop993_german": {"engine_sound": "sd8b", "cylinders": 6},
}
## Menu car -> shown name, model (key in MODELS) and physics (key in cars.json, default the menu
## key). Every .sim variant whose model exists; names and models from FEData/Data/nfs5.car
## (car_colors.json), which puts the Carrera RS 2.7 on f901, the 996 Turbo on f996 and the Boxster
## 2.5 on fboxster. Variants missing there (930 Turbo 3.0, 993 Turbo, 993 Carrera 4S, 944 Turbo S,
## Boxster S, 356 B Carrera 2) are named by hand; nfs5.car gives some of them a police model, here
## they use the road model. Police cars drive like their road car; traffic (eas, eden, postship)
## has no .sim of its own and uses "default".
const CARS := {
	"356coupe11": {"name": "'50 356 1100 Coupé Ferdinand", "model": "356_1"},
	"356cabrio11": {"name": "'50 356 1100 Cabriolet", "model": "356_1"},
	"356coupe13": {"name": "'51 356 1300 Coupé", "model": "356_1"},
	"356cabrio13": {"name": "'51 356 1300 Cabriolet", "model": "356_1"},
	"356coupe15": {"name": "'52 356 1500 Coupé", "model": "356_1"},
	"356cabrio15": {"name": "'52 356 1500 Cabriolet", "model": "356_1"},
	"356coupeS15": {"name": "'53 356 1500 Super Coupé", "model": "356_1"},
	"356cabrioS15": {"name": "'53 356 1500 Super Cabriolet", "model": "356_1"},
	"356coupeS13": {"name": "'54 356 1300 Super Coupé", "model": "356_1"},
	"356cabrioS13": {"name": "'54 356 1300 Super Cabriolet", "model": "356_1"},
	"356Acoupe13": {"name": "'56 356 A 1300 Coupé", "model": "356a"},
	"356Acabrio13": {"name": "'56 356 A 1300 Cabriolet", "model": "356a"},
	"356AcoupeS13": {"name": "'56 356 A 1300 Super Coupé", "model": "356a"},
	"356AcabrioS13": {"name": "'56 356 A 1300 Super Cabriolet", "model": "356a"},
	"356Acoupe16": {"name": "'56 356 A 1600 Coupé", "model": "356a"},
	"356Acabrio16": {"name": "'56 356 A 1600 Cabriolet", "model": "356a"},
	"356AcoupeS16": {"name": "'56 356 A 1600 Super Coupé", "model": "356a"},
	"356AcabrioS16": {"name": "'56 356 A 1600 Super Cabriolet", "model": "356a"},
	"356Aspeed16": {"name": "'56 356 A 1600 Speedster", "model": "356a"},
	"356AspeedS16": {"name": "'56 356 A 1600 Super Speedster", "model": "356a"},
	"356Aconv16": {"name": "'59 356 A 1600 Convertible D", "model": "356a"},
	"356AconvS16": {"name": "'59 356 A 1600 Super Convertible D", "model": "356a"},
	"356Bcoupe16": {"name": "'60 356 B 1600 Coupé", "model": "356b"},
	"356Bcabrio16": {"name": "'60 356 B 1600 Cabriolet", "model": "356b"},
	"356BcoupeS16": {"name": "'60 356 B 1600 Super Coupé", "model": "356b"},
	"356BcabrioS16": {"name": "'60 356 B 1600 Super Cabriolet", "model": "356b"},
	"356BcoupeS9016": {"name": "'60 356 B 1600 Super 90 Coupé", "model": "356b"},
	"356BcabrioS9016": {"name": "'60 356 B 1600 Super 90 Cabriolet", "model": "356b"},
	"356Broad16": {"name": "'60 356 B 1600 Roadster", "model": "356b"},
	"356BroadS16": {"name": "'60 356 B 1600 Super Roadster", "model": "356b"},
	"356BroadS9016": {"name": "'60 356 B 1600 Super 90 Roadster", "model": "356b"},
	"356Bhard16": {"name": "'60 356 B 1600 Hardtop", "model": "356b"},
	"356BhardS16": {"name": "'60 356 B 1600 Super Hardtop", "model": "356b"},
	"356BhardS9016": {"name": "'60 356 B 1600 Super 90 Hardtop", "model": "356b"},
	"356BcoupeGS20": {"name": "'62 356 B 2000 GS Carrera 2 Coupé", "model": "356b"},
	"550Arace": {"name": "'56 550 A Spyder", "model": "550"},
	"901coupe20": {"name": "'65 911 Coupé", "model": "901"},
	"901coupeS20": {"name": "'67 911 S Coupé", "model": "901"},
	"901targa20": {"name": "'67 911 Targa", "model": "901"},
	"901targaS20": {"name": "'67 911 S Targa", "model": "901"},
	"901coupe24": {"name": "'72 911 S 2.4 Coupé", "model": "901"},
	"901targaS24": {"name": "'72 911 S 2.4 Targa", "model": "901"},
	"901carreraRS27": {"name": "'73 911 Carrera RS 2.7 Coupé", "model": "f901"},
	"914coupe17": {"name": "'70 914/4 1.7", "model": "914"},
	"914coupe20": {"name": "'73 914/4 2.0", "model": "914"},
	"914coupe18": {"name": "'74 914/4 1.8", "model": "914"},
	"930Tcoupe30": {"name": "'75 911 Turbo 3.0 Coupé (930)", "model": "930"},
	"930Tcoupe33": {"name": "'78 911 Turbo 3.3 Coupé (930)", "model": "930"},
	"935race": {"name": "'78 935/78 Coupé \"Moby Dick\"", "model": "935"},
	"944coupe25": {"name": "'82 944 Coupé", "model": "944"},
	"944coupeS25": {"name": "'87 944 S Coupé", "model": "944"},
	"944Tcoupe25": {"name": "'85 944 Turbo Coupé", "model": "944"},
	"944TcoupeS25": {"name": "'88 944 Turbo S Coupé", "model": "944"},
	"944cabrioS230": {"name": "'89 944 S2 Cabriolet", "model": "944"},
	"944Tcabrio25": {"name": "'91 944 Turbo Cabriolet", "model": "944"},
	"959coupe29": {"name": "'87 959", "model": "959"},
	"964coupe436": {"name": "'89 911 Carrera 4 Coupé (964)", "model": "964"},
	"964cabrio436": {"name": "'90 911 Carrera 4 Cabriolet (964)", "model": "964"},
	"964targa436": {"name": "'90 911 Carrera 4 Targa (964)", "model": "964"},
	"964coupe36": {"name": "'90 911 Carrera 2 Coupé (964)", "model": "964"},
	"964cabrio36": {"name": "'90 911 Carrera 2 Cabriolet (964)", "model": "964"},
	"964targa36": {"name": "'90 911 Carrera 2 Targa (964)", "model": "964"},
	"965Tcoupe33": {"name": "'91 911 Turbo 3.3 Coupé (964)", "model": "964"},
	"965Tcoupe36": {"name": "'93 911 Turbo 3.6 Coupé (964)", "model": "964"},
	"928coupeGTS54": {"name": "'92 928 GTS", "model": "928"},
	"993coupe36": {"name": "'94 911 Carrera Coupé (993)", "model": "993"},
	"993cabrio36": {"name": "'94 911 Carrera Cabriolet (993)", "model": "993"},
	"993coupe436": {"name": "'95 911 Carrera 4 Coupé (993)", "model": "993"},
	"993cabrio436": {"name": "'95 911 Carrera 4 Cabriolet (993)", "model": "993"},
	"993Tcoupe36": {"name": "'96 911 Turbo Coupé (993)", "model": "993"},
	"993targa36": {"name": "'96 911 Carrera Targa (993)", "model": "993"},
	"9936coupe36": {"name": "'96 911 Carrera Coupé (993)", "model": "993"},
	"9936coupe436": {"name": "'96 911 Carrera 4 Coupé (993)", "model": "993"},
	"993coupe4S36": {"name": "'96 911 Carrera 4S Coupé (993)", "model": "993"},
	"993coupeS36": {"name": "'97 911 Carrera S 3.6 Coupé (993)", "model": "993"},
	"boxster25": {"name": "'97 Boxster", "model": "fboxster"},
	"996coupe34": {"name": "'98 911 Carrera 3.4 Coupé (996)", "model": "996"},
	"996cabrio34": {"name": "'98 911 Carrera 3.4 Cabriolet (996)", "model": "996"},
	"996coupe434": {"name": "'99 911 Carrera 4 Coupé (996)", "model": "996"},
	"996cabrio434": {"name": "'99 911 Carrera 4 Cabriolet (996)", "model": "996"},
	"996Tcoupe36": {"name": "'00 911 Turbo (996)", "model": "f996"},
	"boxsterS32": {"name": "'00 Boxster S", "model": "boxster"},
	"GT2race": {"name": "'97 911 GT2 race version", "model": "gt2"},
	"GT1race": {"name": "'98 911 GT1 race version", "model": "gt1"},
	"GT3race": {"name": "'98 911 GT3 Cup", "model": "gt3"},
	"cop356": {"name": "356 police", "model": "cop356", "physics": "356Acoupe16"},
	"cop356_german": {"name": "356 Polizei", "model": "cop356_german", "physics": "356Acoupe16"},
	"cop930": {"name": "911 Turbo (930) police", "model": "cop930", "physics": "930Tcoupe33"},
	"cop930_german": {"name": "911 Turbo (930) Polizei", "model": "cop930_german", "physics": "930Tcoupe33"},
	"cop993": {"name": "911 (993) police", "model": "cop993", "physics": "993coupe36"},
	"cop993_german": {"name": "911 (993) Polizei", "model": "cop993_german", "physics": "993coupe36"},
	"eas1": {"name": "Traffic eas1", "model": "eas1", "physics": "default"},
	"eas2": {"name": "Traffic eas2", "model": "eas2", "physics": "default"},
	"eas3": {"name": "Traffic eas3", "model": "eas3", "physics": "default"},
	"eas4": {"name": "Traffic eas4", "model": "eas4", "physics": "default"},
	"eas5": {"name": "Traffic eas5", "model": "eas5", "physics": "default"},
	"eas6": {"name": "Traffic eas6", "model": "eas6", "physics": "default"},
	"eas7": {"name": "Traffic eas7", "model": "eas7", "physics": "default"},
	"eas8": {"name": "Traffic eas8", "model": "eas8", "physics": "default"},
	"eas9": {"name": "Traffic eas9", "model": "eas9", "physics": "default"},
	"eas10": {"name": "Traffic eas10", "model": "eas10", "physics": "default"},
	"eas11": {"name": "Traffic eas11", "model": "eas11", "physics": "default"},
	"eden1": {"name": "Traffic eden1", "model": "eden1", "physics": "default"},
	"eden2": {"name": "Traffic eden2", "model": "eden2", "physics": "default"},
	"eden3": {"name": "Traffic eden3", "model": "eden3", "physics": "default"},
	"eden4": {"name": "Traffic eden4", "model": "eden4", "physics": "default"},
	"eden5": {"name": "Traffic eden5", "model": "eden5", "physics": "default"},
	"postship": {"name": "Traffic postship", "model": "postship", "physics": "default"},
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
## "day" or "night"; empty = --time argument or project setting stuttgart/time.
var time_of_day := ""
var hdri_sky := false  ## the sky is an HDRI (false: procedural fallback)
var lights: Node3D  ## CarLights
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
	if time_of_day.is_empty():
		time_of_day = GameSettings.time_of_day if not GameSettings.time_of_day.is_empty() else _time_from_args()
	_setup_lighting()
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
		var color := GameSettings.car_color if not GameSettings.car_color.is_empty() else _user_arg("color")
		Materials.setup_car(model, Color.from_string(color, Color(0, 0, 0, 0)) if not color.is_empty() else Color(0, 0, 0, 0))
		car.setup(model, cars[physics])
		Materials.add_car_reflections(car)
		lights = CarLights.new()
		car.add_child(lights)
		lights.setup(car, model, time_of_day == "night")
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


## Sky, sun or moon and exposure for the track and time of day. The scene's environment is
## shared by every instance of main.tscn (the tests load it repeatedly), so it is copied first.
func _setup_lighting() -> void:
	var world := $WorldEnvironment as WorldEnvironment
	world.environment = world.environment.duplicate(true) as Environment
	hdri_sky = SkyLighting.apply(world.environment, $Sun as DirectionalLight3D, track_name, time_of_day)


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
	var info: Dictionary = CARS.get(key, {"name": key, "model": key.to_lower()}).duplicate()
	info.merge(MODELS.get(info["model"], {"engine_sound": "sd1a", "cylinders": 4}))
	return info


## Paint colours of the car from CAR_COLORS (parsed, or null): {"colors": ["#rrggbb", ...],
## "default": factory colour or ""}. The palette is per model; the default per variant (key in
## nfs5.car = menu key), else the model's first colour. Empty when the data is missing.
static func car_palette(key: String, car_colors: Variant) -> Dictionary:
	var result := {"colors": [], "default": ""}
	if not car_colors is Dictionary:
		return result
	var model: Dictionary = car_colors["models"].get(str(car_info(key)["model"]), {})
	result["colors"] = model.get("exterior", [])
	var variant: Variant = car_colors["cars"].get(key)
	if variant is Dictionary and variant["default"] != null and variant["default"] in result["colors"]:
		result["default"] = variant["default"]
	elif not result["colors"].is_empty():
		result["default"] = result["colors"][0]
	return result


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


func _time_from_args() -> String:
	var arg := _user_arg("time")
	var time: String = arg if not arg.is_empty() else ProjectSettings.get_setting("stuttgart/time", DEFAULT_TIME)
	return time if TIMES.has(time) else DEFAULT_TIME


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
