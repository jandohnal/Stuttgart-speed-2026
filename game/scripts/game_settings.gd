extends Node
## Autoload GameSettings: the car, track and options chosen in the menu, handed over to main.gd.
## Empty car / track mean "not chosen", so main.gd falls back to --car/--track and the project
## settings. The tests run main.tscn directly and get the option defaults below: only the menu
## loads the saved choice (user://settings.cfg), so a player's settings never change a test.

const FILE := "user://settings.cfg"
## Option -> default. steering_assist, brake_assist (ABS) and traction_control are Car properties;
## sound unmutes the master bus; diagnostics shows the telemetry readout in the HUD.
const DEFAULT_OPTIONS := {
	"steering_assist": false,
	"brake_assist": false,
	"traction_control": false,
	"sound": true,
	"diagnostics": true,
}

## Key in cars.json (main.gd CARS); empty = not chosen in the menu.
var car_key := ""
## Track name in decomposed/GameData/Track/ (main.gd TRACKS); empty = not chosen in the menu.
var track_name := ""
## "day" / "night" (main.gd TIMES); empty = not chosen in the menu.
var time_of_day := ""
## Body colour "#rrggbb" from the car's original palette (menu); empty = the texture as it is.
var car_color := ""
## Options toggled in the menu (not during the game), applied by main.gd when the game starts.
var options := DEFAULT_OPTIONS.duplicate()


## Last choice saved by save_last(): {"car": key, "track": name, "time": day|night,
## "color": hex}, values "" when never saved.
## Also loads the saved options into `options` (defaults for the ones never saved).
func load_last() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	for key: String in DEFAULT_OPTIONS:
		options[key] = bool(cfg.get_value("options", key, DEFAULT_OPTIONS[key]))
	return {"car": str(cfg.get_value("last", "car", "")), "track": str(cfg.get_value("last", "track", "")),
		"time": str(cfg.get_value("last", "time", "")), "color": str(cfg.get_value("last", "color", ""))}


func save_last() -> void:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	cfg.set_value("last", "car", car_key)
	cfg.set_value("last", "track", track_name)
	cfg.set_value("last", "color", car_color)
	cfg.set_value("last", "time", time_of_day)
	for key: String in options:
		cfg.set_value("options", key, options[key])
	cfg.save(FILE)


## Full screen when the game runs on its own (not in the editor's embedded view, not headless
## tests); -- --windowed=1 keeps a window.
func go_fullscreen() -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--windowed="):
			return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
