extends Node3D
## Phase 2 prototype (D-009): an original car on an original track, both loaded at run time from
## decomposed/. Track: project setting stuttgart/track or --track=<name> (default farmland =
## Normandie); car: stuttgart/car or --car=<key in cars.json> (default 356Acoupe16; CARS maps it to
## the model and engine sound). --slice=<n> starts on road slice n instead of the start line;
## --windowed=1 keeps a window. F2 records telemetry to user://telemetry_*.csv, F5 repairs the car,
## F11 full screen, Esc goes back to the menu (scenes/menu.tscn, which sets GameSettings.car_key /
## track_name, time_of_day and the options: steering assist, ABS, traction control, sound).
## Time of day: GameSettings.time_of_day, else --time=day|night or project setting
## stuttgart/time (default day); the sky and sun come from SkyLighting, the car lamps from CarLights,
## the track's lamps and warning lights from TrackLights.
## Paint: GameSettings.car_color, else --color=<#rrggbb>; empty = the body texture untinted.
## --ai=0|1: the car is driven by AIDriver along the original's racing line 0 or 1 (D-026).
## Parts (CarParts): GameSettings.car_tune (stock / sport) and tyres (stock / slick / rain), else
## --tune= / --tyres=; default stock.
## Opponents (D-026, step C): on a track with a start line --opponents=<n> (0..MAX_OPPONENTS) puts n
## AIDriver cars of the player's model on a staggered grid ahead of the player, each with its
## driver's name, style and colour (OpponentProfiles); the game itself starts with project setting
## stuttgart/opponents (default DEFAULT_OPPONENTS) when the menu's Opponents option is on, the
## tests with none unless they ask. They are held by the countdown
## like the player and set back on the grid on restart. Rubber band (RaceRubberBand, D-035): the
## menu's option in the game, --rubber=0|1 else, off in the tests unless they ask.
## Laps: on Monte Carlo's circuits (start = finish line, "source": "lap") the race is --laps=<n>
## laps, in the game project setting stuttgart/laps (default DEFAULT_LAPS), in the tests one.

const DEFAULT_TRACK := "farmland"
const TrackProps := preload("res://scripts/track_props.gd")
const CarAudio := preload("res://scripts/car_audio.gd")
const CarEffects := preload("res://scripts/car_effects.gd")
const FallingLeaves := preload("res://scripts/falling_leaves.gd")
const TrackWater := preload("res://scripts/track_water.gd")
const Materials := preload("res://scripts/materials.gd")
const SkyLighting := preload("res://scripts/sky_lighting.gd")
const CarLights := preload("res://scripts/car_lights.gd")
const CarParts := preload("res://scripts/car_parts.gd")
const TrackLights := preload("res://scripts/track_lights.gd")
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
const RECORDS_FILE := "user://records.cfg"  ## best race times, [track] car = seconds
const COUNTDOWN := 3.0  ## s of 3-2-1 before GO
const RaceLines := preload("res://scripts/race_lines.gd")
const GRID_BEHIND := 3.0  ## m from the start line back to the car's centre (standing start)
const GRID_STEP := 5.0  ## m between grid slots along the road (left and right column alternate)
const GRID_SIDE := 2.0  ## m from the road centre to a grid column
const MAX_OPPONENTS := 7
const GROUND_PROBE_UP := 3.5  ## m above a reset point the ground search starts (road above the slice: castle courtyard 2.5 m)
const GROUND_PROBE_DOWN := 3.0  ## m below it the search ends
const RESET_HEIGHT := 0.4  ## m of the car's origin above the road after a reset (as Road.transform_at)
const DEFAULT_LAPS := 3  ## laps of a circuit (Monte Carlo) in the game; the tests drive one
const DEFAULT_OPPONENTS := 3
const STOP_BRAKE := 0.6  ## brake after the finish (~0.5 g: firm, the wheels do not lock)
const STOP_LOOKAHEAD := 4  ## road slices ahead the car steers to after the finish
const STOP_SPEED := 0.3  ## m/s below which the stopped car is held
const OPPONENT_STOP_AFTER := 50.0  ## m past the finish line an opponent drives on before braking
const STOP_ASIDE := 1.2  ## m from the road's edge (AIDriver._edges) a stopping opponent's centre ends up
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
## has no .sim of its own and uses "default". style: [styleN] of the model (parts and textures of
## the variant, CarStyle) where nfs5.car has no record of the variant on that model (car_style_of).
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
	"944TcoupeS25": {"name": "'88 944 Turbo S Coupé", "model": "944", "style": 6},
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
	"993coupe4S36": {"name": "'96 911 Carrera 4S Coupé (993)", "model": "993", "style": 5},
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
	"skidpad": "Test Track (skidpad)",
}
const MENU_SCENE := "res://scenes/menu.tscn"
## Track glTF groups that get trimesh collision. Not "drivethrough" (bushes, animdefs.txt
## drivethrough=1: cars pass through them), "vegetation" (trees by name) and the helpers.
const SOLID_GROUPS := ["road", "terrain", "objects"]
const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"reset_car": [KEY_R],
	"restart_race": [KEY_BACKSPACE],
	"telemetry": [KEY_F2],
	"repair": [KEY_F5],
	"fullscreen": [KEY_F11],
	"menu": [KEY_ESCAPE],
	"pause": [KEY_P],
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
var track_lights: Node3D  ## TrackLights
var road := Road.new()
var road_slices: Array = []  ## road.slices (the tests read them)
var start_slice := 0
var race: RaceTimer  ## null on tracks without start / finish lines (free driving)
var ai_driver: AIDriver  ## null: the player drives
var race_laps := -1  ## -1: --laps, else project setting stuttgart/laps in the game, 1 in tests
var opponent_count := -1  ## -1: --opponents, else project setting stuttgart/opponents in the game, 0 in tests
var opponents: Array[Car] = []  ## AI cars on the grid (their AIDriver is the child "AIDriver")
var _opponent_grid: Array[Transform3D] = []
var _stopping := false  ## past the finish: the car brakes along the road (_drive_to_stop)
var standings: RaceStandings  ## order and gaps of all cars in the race, null without a race
var rubber_band: RaceRubberBand  ## keeps the opponents near the player, null = off
var _stopping_opponents: Array[Car] = []  ## opponents past the finish, braking along the road
var _crossed := {}  ## opponent over the finish line, still racing on -> where it crossed it
var _grid := Transform3D.IDENTITY  ## where the race starts (behind the start line)
var prop_counts := {}  ## placed objects per collision type (TrackProps)
var car_style := 0  ## [styleN] of the car's model in use (CarStyle), 0 = model without styles
var _log: FileAccess
var _log_time := 0.0
var _pause_label := Label.new()


func _ready() -> void:
	# Main handles the pause key while the tree is paused; everything under it pauses except the
	# camera (orbits the car) and the pause label.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in get_children():
		_make_pausable(child)
	child_entered_tree.connect(_make_pausable)
	_setup_input()
	_setup_pause_label()
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
		Materials.setup_track(track, folder + track_name + ".gltf")
		add_child(track)
		_add_track_collision(track)
		var objects: Variant = OriginalAssets.load_json(folder + track_name + "_objects.json")
		if objects is Dictionary:
			prop_counts = TrackProps.build(track, objects["objects"])
		var flares: Variant = OriginalAssets.load_json(folder + track_name + "_lights.json")
		if flares is Dictionary:
			track_lights = TrackLights.new()
			add_child(track_lights)
			track_lights.setup(track, flares, SkyLighting.entry(track_name), time_of_day == "night")
		var simd := track.find_child("simd", true, false) as Node3D
		if simd != null:
			simd.visible = false  # road data overlay from track2gltf, only for checking
	var road_data: Variant = OriginalAssets.load_json(folder + track_name + "_road.json")
	if road_data is Dictionary:
		road = Road.new(road_data)
		road_slices = road.slices
		if road_data.has("start"):
			start_slice = int(road_data["start"]["slice"])
		var arg := _user_arg("slice")
		if arg.is_valid_int():
			start_slice = clampi(arg.to_int(), 0, road_slices.size() - 1)
	if car_key.is_empty():
		car_key = GameSettings.car_key
	if car_key.is_empty():
		car_key = _user_arg("car") if not _user_arg("car").is_empty() else ProjectSettings.get_setting("stuttgart/car", DEFAULT_CAR)
	var cars: Variant = OriginalAssets.load_json(CAR_PHYSICS)
	var color := GameSettings.car_color if not GameSettings.car_color.is_empty() else _user_arg("color")
	if _build_car(car, car_key, color, cars, true):
		_load_mileage()
	_reset_car(start_slice)
	if road_data is Dictionary and road_data.has("start") and road_data.has("finish") and _user_arg("slice").is_empty():
		_setup_race(road_data)
	if race != null and cars is Dictionary:
		_add_opponents(road_data, cars, color)
	if _user_arg("ai").is_valid_int():
		drive_by_ai(_user_arg("ai").to_int())
	if track != null and _user_arg("effects") != "0" and _user_arg("leaves") != "0":  # --leaves=0: no leaves from crowns
		var leaves := FallingLeaves.new()
		leaves.name = "FallingLeaves"
		add_child(leaves)
		var field: Array[Car] = [car]
		field.append_array(opponents)
		leaves.setup(road, track, car, field)
	if track != null and _user_arg("effects") != "0" and _user_arg("water") != "0":  # --water=0: no waterfalls, fountains, spray
		var water := TrackWater.new()
		water.name = "TrackWater"
		add_child(water)
		var wet_cars: Array[Car] = [car]
		wet_cars.append_array(opponents)
		water.setup(track_name, track, wet_cars)
	if track != null:
		RaceLines.gate_decals(track)
		if road_data is Dictionary and road_data.has("start"):
			var start: Dictionary = road_data["start"]
			var line := RaceLines.start_line(start, road_slices[int(start["slice"])], start.get("source") == "lap")
			var lift := line.basis.y * RESET_HEIGHT
			line.position = _on_ground(Transform3D(line.basis, line.position + lift)).origin - lift
			track.add_child(line)


## Countdown, clock and best time between the original's start and finish lines. The tests load
## this scene inside their own: there the clock starts at once and no record is written.
func _setup_race(road_data: Dictionary) -> void:
	race = RaceTimer.new()
	race.name = "Race"
	add_child(race)
	var laps := 1
	if road_data["start"].get("source") == "lap":
		var arg := _user_arg("laps")
		laps = race_laps if race_laps > 0 else (arg.to_int() if arg.is_valid_int() else
			(int(ProjectSettings.get_setting("stuttgart/laps", DEFAULT_LAPS)) if _is_game() else 1))
	race.setup(car, road_data["start"], road_data["finish"], road, laps)
	race.finished.connect(_on_race_finished)
	_grid = _grid_transform(road_data["start"])
	car.reset_to(_grid)
	if _is_game():
		race.keep_records(RECORDS_FILE, track_name, car_key if race.laps == 1 else "%s %d laps" % [car_key, race.laps])
	race.begin(COUNTDOWN if _is_game() else 0.0)
	standings = RaceStandings.new()
	standings.name = "Standings"
	add_child(standings)
	standings.setup(race, road, road_data["start"], road_data["finish"])
	standings.crossed_line.connect(_on_opponent_crossed)
	($HUD as Hud).race = race
	($HUD as Hud).standings = standings


## Builds `target` as car `key` (cars.json parsed in `cars`): model in `color` ("" = untinted),
## physics with the chosen parts, lamps, damage and engine sound. The player's car also gets the
## reflection probe (it follows the camera; one moving probe per car would be re-captured all the
## time) and sets car_style / lights. False when the car's physics are missing.
func _build_car(target: Car, key: String, color: String, cars: Variant, player: bool) -> bool:
	var info := car_info(key)
	var model_path := car_model_path(key)
	var engine_sound := "GameData/Sounds/" + str(info["engine_sound"])
	var physics := car_physics_key(key)
	if not (cars is Dictionary and cars.has(physics)):
		push_error("Car %s (physics %s) not found in %s" % [key, physics, CAR_PHYSICS])
		return false
	var model := OriginalAssets.load_gltf(model_path)
	var car_colors: Variant = OriginalAssets.load_json(CAR_COLORS) if OriginalAssets.exists(CAR_COLORS) else null
	var style := CarStyle.apply(model, model_path, car_style_of(key, car_colors))
	Materials.setup_car(model, Color.from_string(color, Color(0, 0, 0, 0)) if not color.is_empty() else Color(0, 0, 0, 0))
	target.setup(model, _fitted_parts(cars[physics], physics))
	var car_lights := CarLights.new()
	target.add_child(car_lights)
	car_lights.setup(target, model, time_of_day == "night")
	if player:
		car_style = style
		lights = car_lights
		Materials.add_car_reflections(target)
	var damage: Variant = OriginalAssets.load_json(model_path.get_basename() + "_damage.json")
	if damage is Dictionary:
		target.setup_damage(damage)
	var engine: Variant = OriginalAssets.load_json(engine_sound.path_join("engine.json"))
	if engine is Dictionary:
		var audio := CarAudio.new()
		audio.name = "Audio"
		target.add_child(audio)
		audio.rpm_scale = 4.0 / float(info["cylinders"])  # engine.json assumes a four
		audio.setup(target, engine, engine_sound, SFX_BANK)
	if _user_arg("effects") != "0":  # --effects=0: without tyre marks, dust and sparks (FPS comparison)
		var effects := CarEffects.new()
		effects.name = "Effects"
		target.add_child(effects)
		effects.setup(target)
	return true


## Opponents on the grid ahead of the player (slots 0..n-1, the player in slot n), each driven by
## an AIDriver on racing line 0 in the style of its OpponentProfiles profile, painted in the
## palette colour nearest to the profile's.
func _add_opponents(road_data: Dictionary, cars: Variant, player_color: String) -> void:
	var arg := _user_arg("opponents")
	var count := opponent_count
	if count < 0:
		if arg.is_valid_int():
			count = arg.to_int()
		elif _is_game() and GameSettings.options["opponents"]:
			count = int(ProjectSettings.get_setting("stuttgart/opponents", DEFAULT_OPPONENTS))
		else:
			count = 0
	count = clampi(count, 0, MAX_OPPONENTS)
	if count == 0:
		return
	var ai_data: Variant = OriginalAssets.load_json("GameData/Track/%s/%s_ai.json" % [track_name, track_name])
	var car_colors: Variant = OriginalAssets.load_json(CAR_COLORS) if OriginalAssets.exists(CAR_COLORS) else null
	var palette: Array = car_palette(car_key, car_colors)["colors"]
	var taken: Array = [player_color if not player_color.is_empty() else car_palette(car_key, car_colors)["default"]]
	for k in count:
		var profile := OpponentProfiles.profile(k)
		var opponent := Car.new()
		opponent.name = "Opponent%d" % (k + 1)
		add_child(opponent)
		var color := OpponentProfiles.nearest_color(profile["color"], palette, taken)
		taken.append(color)
		if not _build_car(opponent, car_key, color, cars, false):
			opponent.queue_free()
			break
		var driver := AIDriver.new()
		driver.name = "AIDriver"
		opponent.add_child(driver)
		OpponentProfiles.apply(driver, profile)
		driver.setup(opponent, road, ai_data, 0)
		opponents.append(opponent)
		standings.add_car(opponent, profile["name"])
		_opponent_grid.append(_grid_slot(road_data["start"], k))
	var field: Array[Car] = [car]
	field.append_array(opponents)
	for opponent in opponents:
		(opponent.get_node("AIDriver") as AIDriver).others = field
	var rubber := _user_arg("rubber")
	if rubber == "1" or (rubber.is_empty() and _is_game() and GameSettings.options["rubber_band"]):
		rubber_band = RaceRubberBand.new()
		rubber_band.name = "RubberBand"
		add_child(rubber_band)
		rubber_band.setup(race, standings)
	_grid = _grid_slot(road_data["start"], opponents.size())
	_place_on_grid()
	race.started.connect(func() -> void:
		for opponent in opponents:
			opponent.held = false)


## Grid slot k: GRID_BEHIND + k GRID_STEP behind the start line along the road, alternately left
## and right of the centre (k = 0 is pole position, on the left).
func _grid_slot(start: Dictionary, k: int) -> Transform3D:
	var line := _grid_transform(start)
	var behind := line.origin - (-line.basis.z) * (k * GRID_STEP)
	var i := road.nearest(behind)
	var along := (behind - road.positions[i]).dot(road.forwards[i])
	var side := GRID_SIDE * (-1.0 if k % 2 == 0 else 1.0)
	var xf := road.transform_at(i, side)
	xf.origin += road.forwards[i] * along
	return _on_ground(xf)


## Every car back on its grid slot, repaired, held while the countdown runs.
func _place_on_grid() -> void:
	car.reset_to(_grid)
	_set_damage_enabled(car, true)
	_stopping_opponents.clear()
	_crossed.clear()
	for k in opponents.size():
		var opponent := opponents[k]
		opponent.repair()
		_set_damage_enabled(opponent, true)
		opponent.reset_to(_opponent_grid[k])
		opponent.held = race.state == RaceTimer.State.COUNTDOWN and race.countdown > 0.0
		var driver := opponent.get_node("AIDriver") as AIDriver
		driver.enabled = true
		driver.slice = road.nearest(opponent.global_position)


## Standing start: the car's centre GRID_BEHIND behind the start line, on the road.
func _grid_transform(start: Dictionary) -> Transform3D:
	var s: Dictionary = road_slices[int(start["slice"])]
	var up := _vec(s["up"])
	var fwd := _vec(start["forward"]).normalized()
	return _on_ground(Transform3D(Basis.looking_at(fwd, up), _vec(start["position"]) - fwd * GRID_BEHIND + up * RESET_HEIGHT))


## `xf` moved onto the road surface below or a little above it: the original's slices do not
## always lie on the road mesh (Monte Carlo's monaco2 start: 1.2 m below the tunnel entrance, so a
## car put there fell through it). Rays skip back faces, so a tunnel roof above does not count.
func _on_ground(xf: Transform3D) -> Transform3D:
	if not is_inside_tree():
		return xf
	var up := xf.basis.y.normalized()
	var query := PhysicsRayQueryParameters3D.create(xf.origin + up * GROUND_PROBE_UP, xf.origin - up * GROUND_PROBE_DOWN)
	query.hit_back_faces = false
	query.exclude = [car.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).dot(up) < 0.7:
		return xf
	xf.origin = (hit["position"] as Vector3) + up * RESET_HEIGHT
	return xf


## Past the finish line the player's keys stop working: the car brakes firmly along the road
## until it stands, then it is held. The clock has stopped (RaceTimer). Like in the original, a
## car past the finish line takes no more damage.
func _on_race_finished(_time: float) -> void:
	_set_damage_enabled(car, false)
	if ai_driver != null:
		ai_driver.enabled = false
	_stopping = true
	car.auto_drive = true
	car.auto_throttle = 0.0
	car.auto_brake = STOP_BRAKE


## Hands the car to AIDriver on the original's racing line `line_index` (<track>_ai.json).
func drive_by_ai(line_index := 0) -> AIDriver:
	if ai_driver == null:
		ai_driver = AIDriver.new()
		ai_driver.name = "AIDriver"
		car.add_child(ai_driver)
	var ai_data: Variant = OriginalAssets.load_json("GameData/Track/%s/%s_ai.json" % [track_name, track_name])
	ai_driver.setup(car, road, ai_data, line_index)
	ai_driver.passes_waiting = true
	ai_driver.others = opponents
	return ai_driver


## An opponent over the finish line races on for OPPONENT_STOP_AFTER m (out of the way of the
## cars still coming), then its driver lets go and it stops at the side of the road.
func _on_opponent_crossed(crossed_car: Car) -> void:
	_set_damage_enabled(crossed_car, false)
	_crossed[crossed_car] = crossed_car.global_position


func _set_damage_enabled(c: Car, on: bool) -> void:
	if c.damage != null:
		c.damage.enabled = on


func _start_stopping(c: Car) -> void:
	_crossed.erase(c)
	(c.get_node("AIDriver") as AIDriver).enabled = false
	c.auto_throttle = 0.0
	c.auto_brake = STOP_BRAKE
	_stopping_opponents.append(c)


## Brakes `c` along the road until it stands: the player's car to the road's centre, an opponent
## to the edge of the road on the side it is on.
func _drive_to_stop(c: Car) -> void:
	if c.held:
		return
	var ahead := slice_ahead(road.nearest(c.global_position), STOP_LOOKAHEAD)
	var target_pos := _vec(road_slices[ahead]["position"])
	var driver := c.get_node_or_null("AIDriver") as AIDriver
	if driver != null:
		var edges := driver._edges(ahead)
		var lat := driver._lateral(c.global_position, ahead)
		var aside := edges.x + STOP_ASIDE if lat < (edges.x + edges.y) * 0.5 else edges.y - STOP_ASIDE
		target_pos = driver.line[ahead] + road.rights[ahead] * aside
	var to_target := c.to_local(target_pos)
	var angle := atan2(-to_target.x, -to_target.z)  # positive = target on the left
	c.auto_steer = clampf(angle * 3.0, -1.0, 1.0)
	if absf(c.forward_speed) < STOP_SPEED:
		c.held = true


func _restart_race() -> void:
	car.repair()
	_stopping = false
	car.auto_drive = ai_driver != null
	car.auto_steer = 0.0
	if ai_driver != null:
		ai_driver.enabled = true
	race.begin(COUNTDOWN)
	_place_on_grid()
	($Camera as FollowCamera).play_intro()


## Sky, sun or moon and exposure for the track and time of day. The scene's environment is
## shared by every instance of main.tscn (the tests load it repeatedly), so it is copied first.
func _setup_lighting() -> void:
	var world := $WorldEnvironment as WorldEnvironment
	world.environment = world.environment.duplicate(true) as Environment
	hdri_sky = SkyLighting.apply(world.environment, $Sun as DirectionalLight3D, track_name, time_of_day)


## Options from the menu (GameSettings): driver aids and sound.
func _apply_options() -> void:
	var options: Dictionary = GameSettings.options
	car.steering_assist = options["steering_assist"]
	car.brake_assist = options["brake_assist"]
	car.traction_control = options["traction_control"]
	AudioServer.set_bus_mute(0, not options["sound"])


## The game itself runs (not a test that loads this scene inside its own).
func _is_game() -> bool:
	return get_parent() == get_tree().root


## Mileage is kept per car between runs, but only when the game itself runs: the tests
## must neither read nor change it.
func _keeps_mileage() -> bool:
	return _is_game()


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


## The car's .sim values with the chosen parts and tyres fitted (CarParts).
func _fitted_parts(params: Dictionary, physics: String) -> Dictionary:
	var tune := GameSettings.car_tune if not GameSettings.car_tune.is_empty() else _user_arg("tune")
	var tyres := GameSettings.tyres if not GameSettings.tyres.is_empty() else _user_arg("tyres")
	if (tune.is_empty() or tune == "stock") and (tyres.is_empty() or tyres == "stock"):
		return params
	var parts: Variant = OriginalAssets.load_json(CarParts.FILE) if OriginalAssets.exists(CarParts.FILE) else null
	return CarParts.apply(params, parts, physics, tune, tyres if not tyres.is_empty() else "stock")


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


## [styleN] of the car's model .tpg (CarStyle, D-022): CARS "style", else the variant's style on
## that model from CAR_COLORS (nfs5.car, key matched ignoring case), else 0 = the model's default.
static func car_style_of(key: String, car_colors: Variant) -> int:
	var info := car_info(key)
	if info.has("style"):
		return int(info["style"])
	if car_colors is Dictionary:
		for variant: String in car_colors["cars"]:
			if variant.to_lower() == key.to_lower():
				var styles: Dictionary = car_colors["cars"][variant].get("styles", {})
				if styles.has(str(info["model"])):
					return int(styles[str(info["model"])])
	return 0


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


func _make_pausable(child: Node) -> void:
	if child.process_mode == Node.PROCESS_MODE_INHERIT:
		child.process_mode = Node.PROCESS_MODE_PAUSABLE


func _setup_pause_label() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 10
	add_child(layer)
	_pause_label.text = "PAUSE\nP: continue  ·  left mouse button: rotate camera  ·  wheel: zoom"
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	_pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_label.add_theme_font_size_override("font_size", 22)
	_pause_label.add_theme_constant_override("outline_size", 6)
	_pause_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_pause_label.visible = false
	layer.add_child(_pause_label)


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
	if road.size() == 0:
		car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
		return
	car.reset_to(_on_ground(road.transform_at(slice_index)))


func _nearest_slice() -> int:
	return road.nearest(car.global_position)


## Index of the slice `ahead` slices after `index` along the road (Road.ahead).
func slice_ahead(index: int, ahead: int) -> int:
	return road.ahead(index, ahead)


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
	elif event.is_action_pressed("menu"):
		_set_paused(false)
		_back_to_menu()
	elif get_tree().paused:
		return
	elif event.is_action_pressed("reset_car") and not car.auto_drive:
		_reset_car(_nearest_slice())
	elif event.is_action_pressed("restart_race") and race != null:
		_restart_race()
	elif event.is_action_pressed("telemetry"):
		_toggle_log()
	elif event.is_action_pressed("repair"):
		car.repair()
	elif event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


## Pause freezes the simulation, sounds and HUD; the camera then orbits the car with the mouse.
func _set_paused(on: bool) -> void:
	get_tree().paused = on
	($Camera as FollowCamera).set_orbit(on)
	_pause_label.visible = on


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
	if not get_tree().paused:
		if _stopping:
			_drive_to_stop(car)
		for opponent in _crossed.keys():
			if (opponent as Car).global_position.distance_to(_crossed[opponent]) > OPPONENT_STOP_AFTER:
				_start_stopping(opponent)
		for opponent in _stopping_opponents:
			_drive_to_stop(opponent)
	if _log == null or get_tree().paused or car.telemetry.is_empty():
		return
	_log_time += delta
	var row := PackedStringArray()
	for field: String in LOG_FIELDS:
		row.append(str(snappedf(_log_time, 0.001)) if field == "time" else str(car.telemetry.get(field, "")))
	_log.store_line(",".join(row))
