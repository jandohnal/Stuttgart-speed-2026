extends Node
## Autoload GameSettings: the car, track and options chosen in the menu, handed over to main.gd.
## Empty car / track mean "not chosen", so main.gd falls back to --car/--track and the project
## settings. The tests run main.tscn directly and get the option defaults below: only the menu
## loads the saved choice (user://settings.cfg), so a player's settings never change a test.

const FILE := "user://settings.cfg"
## Option -> default. steering_assist, brake_assist (ABS) and traction_control are Car properties;
## sound unmutes the master bus; opponents puts the opponents (main.gd, stuttgart/opponents of them) on the grid of a race;
## rubber_band keeps them near the player (RaceRubberBand); low_quality is the reduced graphics for
## weak computers (is_low_quality, LOW_* below), on the web also set by the address ?quality=low|high.
## original_sky draws the original's sky and horizon, off the HDRI with the original's horizon (D-045,
## SkyLighting.apply); without an HDRI file the original's sky is used either way.
const DEFAULT_OPTIONS := {
	"steering_assist": false,
	"brake_assist": false,
	"traction_control": false,
	"sound": true,
	"opponents": true,
	"rubber_band": true,
	"low_quality": false,
	"original_sky": true,
}
## Low quality: the 3D view renders at most this many lines (instead of stuttgart/render_height),
## the camera sees this far (m, the fog thickens to hide the edge), at most this many opponents
## and night track lights; the sun's shadows reach LOW_SHADOW_DISTANCE (m) in one split of a
## LOW_SHADOW_ATLAS map with hard edges. No headlight shadows, glow or SSAO, effects only on the
## player's car.
const LOW_RENDER_HEIGHT := 720
const LOW_VIEW_DISTANCE := 1500.0
const LOW_FOG_DENSITY := 0.0012
const LOW_OPPONENTS := 1
const LOW_LIGHT_POOL := 2
const LOW_SHADOW_DISTANCE := 150.0
const LOW_SHADOW_ATLAS := 2048
## Low quality adapts the 3D resolution to the graphics card (_adapt_render_height): below
## ADAPT_LOWER_FPS on average over ADAPT_LOWER_TIME s it renders ADAPT_STEP times fewer lines,
## down to LOW_MIN_RENDER_HEIGHT; above ADAPT_RAISE_FPS for ADAPT_RAISE_TIME s one step more, up to
## LOW_RENDER_HEIGHT. A step up that has to be taken back within ADAPT_RAISE_TIME becomes the
## ceiling, so the resolution does not swing. Frames longer than ADAPT_HITCH s (loading) are left out.
const LOW_MIN_RENDER_HEIGHT := 360
const ADAPT_LOWER_FPS := 50.0
const ADAPT_RAISE_FPS := 58.0
const ADAPT_LOWER_TIME := 2.0
const ADAPT_RAISE_TIME := 8.0
const ADAPT_STEP := 0.85
const ADAPT_HITCH := 0.25

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
## Lines of the 3D view chosen by _adapt_render_height (0 = not adapting yet: LOW_RENDER_HEIGHT).
var adaptive_lines := 0
var _adapt_ceiling := 0
var _adapt_frames := 0
var _adapt_time := 0.0
var _adapt_good_time := 0.0
var _adapt_since_raise := INF


## Last choice saved by save_last(): {"car": key, "track": name, "time": day|night,
## "color": hex, "tune": stock|sport, "tyres": stock|slick|rain}, values "" when never saved.
## Also loads the saved options into `options` (defaults for the ones never saved).
func load_last() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(FILE)
	for key: String in DEFAULT_OPTIONS:
		options[key] = bool(cfg.get_value("options", key, DEFAULT_OPTIONS[key]))
	var quality := _url_quality()
	if not quality.is_empty():
		options["low_quality"] = quality == "low"
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


## The web build's reduced quality: fewer lights and particles, no decals (Compatibility renderer).
func is_web_profile() -> bool:
	return OS.has_feature("web")


## The menu's LOW QUALITY option (also ?quality=low in the web build's address).
func is_low_quality() -> bool:
	return bool(options.get("low_quality", false))


## "low" / "high" from the web page's address (?quality=...), "" elsewhere or when not given.
func _url_quality() -> String:
	var value := _url_param("quality")
	return value if value in ["low", "high"] else ""


## Value of ?name=... in the web page's address (lower case), "" elsewhere or when not given.
func _url_param(name: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var search := str(JavaScriptBridge.eval("window.location.search", true))
	for pair in search.trim_prefix("?").split("&", false):
		if pair.begins_with(name + "="):
			return pair.trim_prefix(name + "=").to_lower()
	return ""


func _ready() -> void:
	get_tree().root.size_changed.connect(apply_render_height)
	apply_render_height()


## The 3D view renders at most stuttgart/render_height lines (1080 = Full HD) and is upscaled to
## the window (project setting rendering/scaling_3d/mode, MetalFX spatial on macOS); the HUD stays
## at the native resolution. 0 = the project's own rendering/scaling_3d/scale. Low quality: at most
## LOW_RENDER_HEIGHT lines.
func apply_render_height() -> void:
	var lines := int(ProjectSettings.get_setting("stuttgart/render_height", 0))
	if is_low_quality():
		var low := adaptive_lines if adaptive_lines > 0 else LOW_RENDER_HEIGHT
		lines = low if lines <= 0 else mini(lines, low)
	var height := DisplayServer.window_get_size().y
	if lines <= 0 or height <= 0 or DisplayServer.get_name() == "headless":
		return
	get_tree().root.scaling_3d_scale = clampf(float(lines) / height, 0.25, 1.0)


func _process(delta: float) -> void:
	if is_low_quality() and DisplayServer.get_name() != "headless":
		_adapt_render_height(delta)
	elif adaptive_lines != 0:
		adaptive_lines = 0
		_adapt_ceiling = 0


## Low quality: fewer 3D lines while the frame rate stays low, more again once it has room
## (ADAPT_* above); the HUD shows the result (hud.gd diagnostics).
func _adapt_render_height(delta: float) -> void:
	if delta > ADAPT_HITCH:
		return
	_adapt_frames += 1
	_adapt_time += delta
	_adapt_since_raise += delta
	if _adapt_time < ADAPT_LOWER_TIME:
		return
	var fps := _adapt_frames / _adapt_time
	_adapt_frames = 0
	var window := _adapt_time
	_adapt_time = 0.0
	var lines := adaptive_lines if adaptive_lines > 0 else LOW_RENDER_HEIGHT
	var top := _adapt_ceiling if _adapt_ceiling > 0 else LOW_RENDER_HEIGHT
	var next := lines
	if fps < ADAPT_LOWER_FPS:
		_adapt_good_time = 0.0
		if _adapt_since_raise < ADAPT_RAISE_TIME:
			_adapt_ceiling = maxi(LOW_MIN_RENDER_HEIGHT, int(lines * ADAPT_STEP))  # the last step up was too much
		next = maxi(LOW_MIN_RENDER_HEIGHT, int(lines * ADAPT_STEP))
	elif fps >= ADAPT_RAISE_FPS:
		_adapt_good_time += window
		if _adapt_good_time >= ADAPT_RAISE_TIME and lines < top:
			_adapt_good_time = 0.0
			_adapt_since_raise = 0.0
			next = mini(top, ceili(lines / ADAPT_STEP))
	else:
		_adapt_good_time = 0.0
	if next != lines:
		adaptive_lines = next
		apply_render_height()


## Full screen when the game runs on its own (not in the editor's embedded view, not headless
## tests); -- --windowed=1 keeps a window. The project starts full screen already
## (display/window/size/mode, which also makes the editor run the game in its own window).
func go_fullscreen() -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor() or OS.has_feature("web"):
		return  # a browser allows full screen only from a key press or click (the fullscreen action)
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
