extends Node
## Autoload GameSettings: the car, track and options chosen in the menu, handed over to main.gd.
## Empty car / track mean "not chosen", so main.gd falls back to --car/--track and the project
## settings. The tests run main.tscn directly and get the option defaults below: only the menu
## loads the saved choice (user://settings.cfg), so a player's settings never change a test.

const FILE := "user://settings.cfg"
## Option -> default. steering_assist, brake_assist (ABS) and traction_control are Car properties;
## sound unmutes the master bus; opponents puts the opponents (main.gd, stuttgart/opponents of them) on the grid of a race;
## rubber_band keeps them near the player (RaceRubberBand).
const DEFAULT_OPTIONS := {
	"steering_assist": false,
	"brake_assist": false,
	"traction_control": false,
	"sound": true,
	"opponents": true,
	"rubber_band": true,
}

## Key in cars.json (main.gd CARS); empty = not chosen in the menu.
var car_key := ""
## Track name in decomposed/GameData/Track/ (main.gd TRACKS); empty = not chosen in the menu.
var track_name := ""
## "day" / "night" (main.gd TIMES); empty = not chosen in the menu.
var time_of_day := ""
## Body colour "#rrggbb" from the car's original palette (menu); empty = the texture as it is.
var car_color := ""
## Parts: "stock" / "sport" (CarParts); empty = not chosen in the menu (stock).
var car_tune := ""
## Tyres: "stock" / "slick" / "rain" (CarParts); empty = not chosen in the menu (stock).
var tyres := ""
## Options toggled in the menu (not during the game), applied by main.gd when the game starts.
var options := DEFAULT_OPTIONS.duplicate()
## Calibrated wheel (WheelInput.to_dict, set in WheelSetup); empty = none. Loaded only by the menu.
var wheel := {}


## Last choice saved by save_last(): {"car": key, "track": name, "time": day|night,
## "color": hex, "tune": stock|sport, "tyres": stock|slick|rain}, values "" when never saved.
## Also loads the saved options into `options` (defaults for the ones never saved).
func load_last() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	for key: String in DEFAULT_OPTIONS:
		options[key] = bool(cfg.get_value("options", key, DEFAULT_OPTIONS[key]))
	wheel = cfg.get_value("wheel", "mapping", {})
	return {"car": str(cfg.get_value("last", "car", "")), "track": str(cfg.get_value("last", "track", "")),
		"time": str(cfg.get_value("last", "time", "")), "color": str(cfg.get_value("last", "color", "")),
		"tune": str(cfg.get_value("last", "tune", "")), "tyres": str(cfg.get_value("last", "tyres", ""))}


func save_last() -> void:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	cfg.set_value("last", "car", car_key)
	cfg.set_value("last", "track", track_name)
	cfg.set_value("last", "color", car_color)
	cfg.set_value("last", "time", time_of_day)
	cfg.set_value("last", "tune", car_tune)
	cfg.set_value("last", "tyres", tyres)
	for key: String in options:
		cfg.set_value("options", key, options[key])
	cfg.save(FILE)


## The wheel is saved on its own, when its setup closes; an empty mapping removes the key.
func save_wheel() -> void:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	cfg.set_value("wheel", "mapping", wheel if not wheel.is_empty() else null)
	cfg.save(FILE)


func _ready() -> void:
	get_tree().root.size_changed.connect(_apply_render_height)
	_apply_render_height()


## The 3D view renders at most stuttgart/render_height lines (1080 = Full HD) and is upscaled to
## the window (project setting rendering/scaling_3d/mode, MetalFX spatial on macOS); the HUD stays
## at the native resolution. 0 = the project's own rendering/scaling_3d/scale.
func _apply_render_height() -> void:
	var lines := int(ProjectSettings.get_setting("stuttgart/render_height", 0))
	var height := DisplayServer.window_get_size().y
	if lines <= 0 or height <= 0 or DisplayServer.get_name() == "headless":
		return
	get_tree().root.scaling_3d_scale = clampf(float(lines) / height, 0.25, 1.0)


## Full screen when the game runs on its own (not in the editor's embedded view, not headless
## tests); -- --windowed=1 keeps a window. The project starts full screen already
## (display/window/size/mode, which also makes the editor run the game in its own window).
func go_fullscreen() -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--windowed="):
			_go_windowed()
			return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Leaves the full screen the project starts in. macOS ignores the switch while the window is
## still animating into full screen (~1.5 s), so it is repeated until it takes.
func _go_windowed() -> void:
	for i in 50:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			return
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await get_tree().create_timer(0.1, true, false, true).timeout
