extends Node
## Autoload GameSettings: the car and track chosen in the menu, handed over to main.gd. Empty
## values mean "not chosen", so main.gd falls back to --car/--track and the project settings (the
## tests run main.tscn directly and never touch this). The last choice is kept in
## user://settings.cfg so the menu can preselect it.

const FILE := "user://settings.cfg"

## Key in cars.json (main.gd CARS); empty = not chosen in the menu.
var car_key := ""
## Track name in decomposed/GameData/Track/ (main.gd TRACKS); empty = not chosen in the menu.
var track_name := ""


## Last choice saved by save_last(): {"car": key, "track": name}, values "" when never saved.
func load_last() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	return {"car": str(cfg.get_value("last", "car", "")), "track": str(cfg.get_value("last", "track", ""))}


func save_last() -> void:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	cfg.set_value("last", "car", car_key)
	cfg.set_value("last", "track", track_name)
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
