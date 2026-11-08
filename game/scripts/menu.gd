extends Control
## Main menu (D-009, look D-032): race setup panel on the left (car, parts Stock / Sport via CarParts,
## paint colour, tyres and track dropdowns, then option checkboxes: night, driver aids, sound,
## opponents, rubber band) and PLAY; a porthole with an archive photo (ui/photos/porthole_*, else a
## placeholder) with the selected car turning in it (CarShowcase, one turn a minute) above a caption
## naming the car; top right the selected track's outline from the original menu (TRACK_ART); a footer with credits (a dialog: tribute, how it was made, CREDITS_STATS) and exit. The lists come from
## main.gd (CARS, TRACKS); entries whose data is missing in decomposed/ are disabled. The choice
## goes to the GameSettings autoload and user://settings.cfg, then the game scene takes over.
## Colours: the car's original palette (Main.car_palette), first entry "original" = the texture
## untinted. The options are set only here, not in game.
## Layout: 1920x1080 design pixels (root content scale while the menu is up), wider or taller
## windows grow the background and keep the panel left and the porthole bottom-centre.
## Keyboard / gamepad: arrows or D-pad move the focus (dropdowns -> options -> PLAY -> wheel -> credits ->
## exit -> back to the top), Space / A opens a list or toggles, Enter (anywhere) or Start plays,
## Esc asks to quit.

signal race_requested(config: Dictionary)
signal credits_requested
signal exit_requested

const Main := preload("res://scripts/main.gd")
const CarParts := preload("res://scripts/car_parts.gd")
const MenuTheme := preload("res://ui/theme/menu_theme.gd")
const WheelSetup := preload("res://scripts/wheel_setup.gd")
const GAME_SCENE := "res://scenes/main.tscn"
const DESIGN_SIZE := Vector2i(1920, 1080)
const PHOTO_DIR := "res://ui/photos"
const MISSING := " – no data"
const ORIGINAL_COLOR := "Original"
const FACTORY := " (factory)"
const SWATCH := 20  ## px
const TUNE_LABELS := {"stock": "Stock", "sport": "Sport"}
const TYRE_LABELS := {"stock": "Stock", "slick": "Racing slick", "rain": "Rain"}
const NIGHT := "night"
## Checkbox key -> label, in grid order (2 columns). "night" is the time of day, the rest are
## GameSettings options.
const OPTION_LABELS := {
	NIGHT: "NIGHT RACE",
	"steering_assist": "DRIVING ASSIST",
	"brake_assist": "ABS",
	"traction_control": "TRACTION CONTROL",
	"sound": "SOUND",
	"opponents": "OPPONENTS",
	"rubber_band": "RUBBER BAND",
}
## Track outlines of the original menu (yellow line with shadow, docs/formats/trackart.md): first
## image of FEData/TrackArt/<track>/ (folder name in any case), none for tracks without art.
const TRACK_ART := "FEData/TrackArt"
const CREDITS_CAPTION := "Credits — the people behind Stuttgart Speed"
## How the game was made (tools/credits_stats.py: git history and Claude Code logs).
const CREDITS_STATS := "res://ui/credits_stats.json"

## Accent of buttons, arrows, checkboxes and pills (MenuTheme.ACCENT_CHOICES).
@export var accent := MenuTheme.ACCENT

@onready var car_option: OptionButton = %CarOption
@onready var tune_option: OptionButton = %TuneOption
@onready var color_option: OptionButton = %ColorOption
@onready var tyre_option: OptionButton = %TyreOption
@onready var track_option: OptionButton = %TrackOption
@onready var play_button: Button = %PlayButton
@onready var note: Label = %Note
@onready var options_grid: GridContainer = %Options
@onready var caption: Label = %CaptionLabel
@onready var exit_dialog: ConfirmationDialog = %ExitDialog
@onready var credits_dialog: AcceptDialog = %CreditsDialog

var car_keys: Array[String] = []
var track_names: Array[String] = []
var colors: Array[String] = []  ## color_option items: "" (original) or "#rrggbb"
var car_colors: Variant  ## Main.CAR_COLORS, null when missing
var parts: Variant  ## CarParts.FILE, null when missing
var option_toggles := {}  ## key of OPTION_LABELS -> CheckBox
var wheel_setup: WheelSetup
var _scale_size := Vector2i.ZERO  ## root content scale before the menu
var _caption_tween: Tween


func _enter_tree() -> void:
	_scale_size = get_tree().root.content_scale_size
	get_tree().root.content_scale_size = DESIGN_SIZE


func _exit_tree() -> void:
	get_tree().root.content_scale_size = _scale_size


func _ready() -> void:
	GameSettings.go_fullscreen()
	theme = MenuTheme.build(accent)
	_setup_art()
	var last := GameSettings.load_last()
	var cars: Variant = OriginalAssets.load_json(Main.CAR_PHYSICS) if OriginalAssets.exists(Main.CAR_PHYSICS) else null
	for key: String in Main.CARS:
		car_keys.append(key)
		_add_item(car_option, Main.car_info(key)["name"], Main.car_available(key, cars))
	for track: String in Main.TRACKS:
		track_names.append(track)
		_add_item(track_option, Main.TRACKS[track], Main.track_available(track))
	_preselect(car_option, car_keys.find(last["car"]))
	car_colors = OriginalAssets.load_json(Main.CAR_COLORS) if OriginalAssets.exists(Main.CAR_COLORS) else null
	_fill_colors(last["color"])
	parts = OriginalAssets.load_json(CarParts.FILE) if OriginalAssets.exists(CarParts.FILE) else null
	for tune: String in CarParts.TUNES:
		tune_option.add_item(TUNE_LABELS[tune])
	tune_option.select(maxi(CarParts.TUNES.find(last["tune"]), 0))
	for kind: String in CarParts.TYRES:
		tyre_option.add_item(TYRE_LABELS[kind])
	tyre_option.select(maxi(CarParts.TYRES.find(last["tyres"]), 0))
	_update_parts()
	_preselect(track_option, track_names.find(last["track"]))
	for key: String in OPTION_LABELS:
		var toggle := CheckBox.new()
		toggle.theme_type_variation = &"SetupCheckBox"
		toggle.text = OPTION_LABELS[key]
		toggle.custom_minimum_size.y = 38
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle.button_pressed = last["time"] == NIGHT if key == NIGHT else GameSettings.options[key]
		toggle.toggled.connect(_update_caption.unbind(1))
		options_grid.add_child(toggle)
		option_toggles[key] = toggle
	car_option.item_selected.connect(_on_car_selected)
	for option: OptionButton in [tune_option, color_option, tyre_option, track_option]:
		option.item_selected.connect(_on_item_selected)
	track_option.item_selected.connect(_show_track.unbind(1))
	_show_track()
	play_button.pressed.connect(_play)
	play_button.button_down.connect(_shift_play.bind(2))
	play_button.button_up.connect(_shift_play.bind(0))
	play_button.mouse_entered.connect(_glow.bind(play_button, true))
	play_button.mouse_exited.connect(_glow.bind(play_button, false))
	%WheelButton.pressed.connect(_on_wheel)
	%CreditsButton.pressed.connect(_on_credits)
	%ExitButton.pressed.connect(_ask_exit)
	exit_dialog.theme = theme
	exit_dialog.confirmed.connect(_exit)
	credits_dialog.theme = theme
	wheel_setup = WheelSetup.new()
	wheel_setup.theme = theme
	add_child(wheel_setup)
	_fill_stats()
	_link_focus()
	_update_play()
	_update_caption()
	car_option.grab_focus()


## Background pattern, top shade, play icon and the porthole photo.
func _setup_art() -> void:
	%Background.resized.connect(_place_background)
	_place_background()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 110.0 / 300.0, 290.0 / 300.0])
	gradient.colors = PackedColorArray([MenuTheme.TOP_SHADE, Color(MenuTheme.TOP_SHADE, 0.88), Color(MenuTheme.TOP_SHADE, 0.0)])
	var shade := GradientTexture2D.new()
	shade.gradient = gradient
	shade.fill_to = Vector2(0, 1)
	shade.width = 4
	shade.height = 300
	%TopShade.texture = shade
	%PlayIcon.texture = MenuTheme.icon("play", accent)
	var photo := _photo()
	var shader: ShaderMaterial = %Photo.material
	shader.set_shader_parameter("has_photo", photo != null)
	if photo != null:
		shader.set_shader_parameter("photo", photo)
		shader.set_shader_parameter("photo_aspect", float(photo.get_width()) / photo.get_height())


## Ring and spoke centres follow the porthole (bottom-centre anchor), as in the 1920x1080 design.
func _place_background() -> void:
	var area: Vector2 = %Background.size
	var shader: ShaderMaterial = %Background.material
	var origin := Vector2(area.x * 0.5 - DESIGN_SIZE.x * 0.5, area.y - DESIGN_SIZE.y)
	shader.set_shader_parameter("rect_size", area)
	shader.set_shader_parameter("ring_center", origin + Vector2(1060, 820))
	shader.set_shader_parameter("spoke_center", origin + Vector2(1172, 829))


## First res://ui/photos/porthole_*.jpg|png (black-and-white archive photo with a clear licence,
## not in git), null when there is none.
static func _photo() -> Texture2D:
	if not DirAccess.dir_exists_absolute(PHOTO_DIR):
		return null
	var files := Array(DirAccess.get_files_at(PHOTO_DIR))
	files.sort()
	for file: String in files:
		if file.begins_with("porthole_") and file.get_extension().to_lower() in ["jpg", "jpeg", "png"]:
			var image := Image.load_from_file(PHOTO_DIR.path_join(file))
			if image != null:
				return ImageTexture.create_from_image(image)
	return null


## D-pad / arrows top to bottom: 5 dropdowns -> option grid (2 columns) -> PLAY -> wheel -> credits -> exit,
## wrapping to the first dropdown; Tab goes the same way.
func _link_focus() -> void:
	var toggles: Array = option_toggles.values()
	var chain: Array[Control] = [car_option, tune_option, color_option, tyre_option, track_option]
	chain.append_array(toggles)
	chain.append_array([play_button, %WheelButton, %CreditsButton, %ExitButton])
	for i in chain.size():
		var c: Control = chain[i]
		c.focus_next = c.get_path_to(chain[(i + 1) % chain.size()])
		c.focus_previous = c.get_path_to(chain[i - 1])
		c.focus_neighbor_bottom = c.focus_next
		c.focus_neighbor_top = c.focus_previous
	for i in toggles.size():
		var t: Control = toggles[i]
		t.focus_neighbor_top = t.get_path_to(toggles[i - 2] if i >= 2 else track_option)
		t.focus_neighbor_bottom = t.get_path_to(toggles[i + 2] if i + 2 < toggles.size() else play_button)
		var other: Control = toggles[i ^ 1] if (i ^ 1) < toggles.size() else t
		t.focus_neighbor_left = t.get_path_to(other)
		t.focus_neighbor_right = t.get_path_to(other)
	play_button.focus_neighbor_top = play_button.get_path_to(toggles[toggles.size() - 1])
	%WheelButton.focus_neighbor_right = %WheelButton.get_path_to(%CreditsButton)
	%CreditsButton.focus_neighbor_left = %CreditsButton.get_path_to(%WheelButton)
	%CreditsButton.focus_neighbor_right = %CreditsButton.get_path_to(%ExitButton)
	%ExitButton.focus_neighbor_left = %ExitButton.get_path_to(%CreditsButton)


func _on_car_selected(_index: int) -> void:
	_fill_colors(colors[color_option.selected] if color_option.selected >= 0 else "")
	_update_parts()
	_update_play()
	_update_caption()


func _on_item_selected(_index: int) -> void:
	_update_play()
	_update_caption()


## Sport and the tyres the selected car offers; the rest is disabled and falls back to stock.
func _update_parts() -> void:
	var entry := {}
	if car_option.selected >= 0:
		entry = CarParts.car_entry(parts, Main.car_physics_key(car_keys[car_option.selected]))
	var sport := CarParts.upgradable(entry)
	tune_option.set_item_disabled(CarParts.TUNES.find("sport"), not sport)
	if not sport:
		tune_option.select(0)
	tune_option.disabled = not sport
	var choices := CarParts.tyre_choices(entry)
	for i in CarParts.TYRES.size():
		tyre_option.set_item_disabled(i, not CarParts.TYRES[i] in choices)
	if tyre_option.is_item_disabled(maxi(tyre_option.selected, 0)):
		tyre_option.select(0)
	tyre_option.disabled = choices.size() <= 1


## Palette of the selected car; keeps `keep` selected when the car has it, else "original".
func _fill_colors(keep: String) -> void:
	color_option.clear()
	colors = [""]
	color_option.add_item(ORIGINAL_COLOR)
	if car_option.selected >= 0:
		var palette := Main.car_palette(car_keys[car_option.selected], car_colors)
		for hex: String in palette["colors"]:
			colors.append(hex)
			var text := hex.to_upper() + (FACTORY if hex == palette["default"] else "")
			color_option.add_icon_item(_swatch(Color(hex)), text)
	color_option.select(maxi(colors.find(keep.to_lower()), 0))
	color_option.disabled = colors.size() <= 1


static func _swatch(color: Color) -> Texture2D:
	var img := Image.create(SWATCH, SWATCH, false, Image.FORMAT_RGBA8)
	img.fill(MenuTheme.BORDER)
	img.fill_rect(Rect2i(2, 2, SWATCH - 4, SWATCH - 4), color)
	return ImageTexture.create_from_image(img)


func _add_item(option: OptionButton, text: String, available: bool) -> void:
	option.add_item(text if available else text + MISSING)
	option.set_item_disabled(option.item_count - 1, not available)


## Selects the last choice if it is still available, else the first available entry, else none.
func _preselect(option: OptionButton, index: int) -> void:
	if index < 0 or option.is_item_disabled(index):
		index = -1
		for i in option.item_count:
			if not option.is_item_disabled(i):
				index = i
				break
	option.select(index)


func _update_play() -> void:
	var can_play := car_option.selected >= 0 and track_option.selected >= 0
	play_button.disabled = not can_play
	note.text = "" if can_play else "Data missing in decomposed/ – run tools/build_data.py (see docs/setup.md)."
	note.visible = not can_play


## Outline and name of the selected track top right; hidden when the track has no art.
func _show_track() -> void:
	var track := track_names[track_option.selected] if track_option.selected >= 0 else ""
	var map := _track_art(track)
	%TrackMap.texture = map
	%TrackName.text = Main.TRACKS[track].to_upper() if not track.is_empty() else ""
	%TrackName.visible = map != null


static func _track_art(track: String) -> Texture2D:
	if track.is_empty() or not DirAccess.dir_exists_absolute(OriginalAssets.path(TRACK_ART)):
		return null
	for folder: String in DirAccess.get_directories_at(OriginalAssets.path(TRACK_ART)):
		if folder.to_lower() != track:
			continue
		var dir := OriginalAssets.path(TRACK_ART).path_join(folder)
		for file: String in DirAccess.get_files_at(dir):
			if file.begins_with("000_") and file.get_extension() == "png":
				var image := Image.load_from_file(dir.path_join(file))
				return ImageTexture.create_from_image(image) if image != null else null
	return null


## Caption under the porthole: the selected car (the default after any change in the setup).
## Also turns the selected car in its colour in the porthole.
func _update_caption() -> void:
	_set_caption(car_option.get_item_text(car_option.selected) if car_option.selected >= 0 else "")
	var key := car_keys[car_option.selected] if car_option.selected >= 0 else ""
	%CarView.show_car(key, colors[color_option.selected] if color_option.selected >= 0 else "", car_colors)


func _set_caption(text: String) -> void:
	if caption.text == text:
		return
	caption.text = text
	if _caption_tween != null:
		_caption_tween.kill()
	caption.modulate.a = 0.0
	_caption_tween = create_tween()
	_caption_tween.tween_property(caption, "modulate:a", 1.0, 0.15)


func _shift_play(offset: float) -> void:
	%PlayContent.position.y = offset


func _glow(button: Button, on: bool) -> void:
	var lit := on and not button.disabled
	create_tween().tween_property(button, "modulate", Color(1.15, 1.15, 1.15) if lit else Color.WHITE, 0.12)


func _on_wheel() -> void:
	wheel_setup.open()


func _on_credits() -> void:
	_set_caption(CREDITS_CAPTION)
	credits_requested.emit()
	credits_dialog.popup_centered()
	credits_dialog.get_ok_button().grab_focus()


## "By the numbers" in the credits from CREDITS_STATS; the section hides when the file is missing.
func _fill_stats() -> void:
	var stats: Variant = null
	if FileAccess.file_exists(CREDITS_STATS):
		stats = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_STATS))
	%StatsHeader.visible = stats is Dictionary
	%Stats.visible = stats is Dictionary
	if not stats is Dictionary:
		return
	var tokens: Dictionary = stats["tokens"]
	%StatsHeader.text = "BY THE NUMBERS (%s)" % _date(stats["updated"])
	var rows := [
		["Days in development", "%d (since %s)" % [stats["days"], _date(stats["first_commit"])]],
		["Commits", _thousands(stats["commits"])],
		["Claude Code sessions", _thousands(stats["sessions"])],
		["Claude responses", _thousands(stats["responses"])],
		["Active time together", "about %d h" % roundi(stats["active_hours"])],
		["Tokens read by Claude", "%.0f million" % ((tokens["total"] - tokens["output"]) / 1e6)],
		["Tokens written by Claude", "%.1f million" % (tokens["output"] / 1e6)],
	]
	for row: Array in rows:
		var label := Label.new()
		label.theme_type_variation = &"CreditsText"
		label.text = row[0]
		var value := Label.new()
		value.theme_type_variation = &"CreditsValue"
		value.text = row[1]
		%Stats.add_child(label)
		%Stats.add_child(value)


static func _thousands(n: float) -> String:
	var digits := str(int(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


## "2026-10-15" -> "15 Oct 2026".
static func _date(iso: String) -> String:
	var parts := iso.split("-")
	if parts.size() != 3:
		return iso
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %s" % [int(parts[2]), months[clampi(int(parts[1]) - 1, 0, 11)], parts[0]]


func _ask_exit() -> void:
	exit_dialog.popup_centered()
	exit_dialog.get_cancel_button().grab_focus()


func _exit() -> void:
	exit_requested.emit()
	get_tree().quit()


func get_config() -> Dictionary:
	var config := {
		"car": car_keys[car_option.selected],
		"track": track_names[track_option.selected],
		"time": NIGHT if (option_toggles[NIGHT] as CheckBox).button_pressed else "day",
		"color": colors[color_option.selected] if color_option.selected >= 0 else "",
		"tune": CarParts.TUNES[maxi(tune_option.selected, 0)],
		"tyres": CarParts.TYRES[maxi(tyre_option.selected, 0)],
	}
	for key: String in option_toggles:
		if key != NIGHT:
			config[key] = (option_toggles[key] as CheckBox).button_pressed
	return config


func _play() -> void:
	if play_button.disabled:
		return
	var config := get_config()
	GameSettings.car_key = config["car"]
	GameSettings.track_name = config["track"]
	GameSettings.time_of_day = config["time"]
	GameSettings.car_color = config["color"]
	GameSettings.car_tune = config["tune"]
	GameSettings.tyres = config["tyres"]
	for key: String in GameSettings.options:
		GameSettings.options[key] = config[key]
	GameSettings.save_last()
	var color := color_option.get_item_text(color_option.selected).trim_suffix(FACTORY).to_lower()
	_set_caption("Loading… %s · %s, %s · %s" % [track_option.get_item_text(track_option.selected),
		car_option.get_item_text(car_option.selected), color, config["time"]])
	race_requested.emit(config)
	play_button.disabled = true
	# Let the caption show before the game scene loads (which blocks).
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(GAME_SCENE)


## Enter plays even while the focus is on a dropdown (there Enter would open the list; Space or
## gamepad A still does). An open list or the exit dialog is a popup window and gets its keys first.
func _input(event: InputEvent) -> void:
	if exit_dialog.visible or credits_dialog.visible or wheel_setup.visible:
		return
	var key := event as InputEventKey
	var joy := event as InputEventJoypadButton
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_play()
		elif key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_ask_exit()
	elif joy != null and joy.pressed and joy.button_index == JOY_BUTTON_START:
		get_viewport().set_input_as_handled()
		_play()
