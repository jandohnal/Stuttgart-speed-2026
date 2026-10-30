extends Control
## Main menu of the prototype (D-009): car with its parts (Stock / Sport, CarParts) and paint colour,
## track, tyres (stock / slick / rain) and time of day (day / night) dropdowns, a row of option toggles (driver
## aids, sound, diagnostics, opponents) and Play. The lists come from main.gd (CARS, TRACKS); entries whose
## data is missing in decomposed/ are disabled. The choice goes to the GameSettings autoload and
## user://settings.cfg, then the game scene takes over. Colours: the car's original palette
## (Main.car_palette), first entry "original" = the texture untinted. The options are set only here, not in game.
## Keyboard / gamepad: arrows or D-pad move the focus, Enter (anywhere) or Start plays, Esc quits.

const Main := preload("res://scripts/main.gd")
const CarParts := preload("res://scripts/car_parts.gd")
const GAME_SCENE := "res://scenes/main.tscn"
const MISSING := " – chybí data"
const ORIGINAL_COLOR := "Původní"
const FACTORY := " (továrna)"
const SWATCH := 20  ## px
const TUNE_LABELS := {"stock": "Stock", "sport": "Sport"}
const TYRE_LABELS := {"stock": "Sériové", "slick": "Slick", "rain": "Rain (do deště)"}
## GameSettings option -> toggle label, in the order of the row.
const OPTION_LABELS := {
	"steering_assist": "Asistent řízení",
	"brake_assist": "ABS",
	"traction_control": "Kontrola trakce",
	"sound": "Zvuk",
	"diagnostics": "Diagnostika",
	"opponents": "Soupeři",
}

@onready var car_option: OptionButton = %CarOption
@onready var tune_option: OptionButton = %TuneOption
@onready var color_option: OptionButton = %ColorOption
@onready var tyre_option: OptionButton = %TyreOption
@onready var track_option: OptionButton = %TrackOption
@onready var time_option: OptionButton = %TimeOption
@onready var play_button: Button = %PlayButton
@onready var note: Label = %Note
@onready var options_row: HBoxContainer = %Options

var car_keys: Array[String] = []
var track_names: Array[String] = []
var times: Array[String] = []
var colors: Array[String] = []  ## color_option items: "" (original) or "#rrggbb"
var car_colors: Variant  ## Main.CAR_COLORS, null when missing
var parts: Variant  ## CarParts.FILE, null when missing
var option_toggles := {}  ## option key -> CheckButton


func _ready() -> void:
	GameSettings.go_fullscreen()
	var last := GameSettings.load_last()
	var cars: Variant = OriginalAssets.load_json(Main.CAR_PHYSICS) if OriginalAssets.exists(Main.CAR_PHYSICS) else null
	for key: String in Main.CARS:
		car_keys.append(key)
		_add_item(car_option, Main.car_info(key)["name"], Main.car_available(key, cars))
	for track: String in Main.TRACKS:
		track_names.append(track)
		_add_item(track_option, Main.TRACKS[track], Main.track_available(track))
	for time: String in Main.TIMES:
		times.append(time)
		time_option.add_item(Main.TIMES[time])
	time_option.select(maxi(times.find(last["time"]), 0))
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
		var toggle := CheckButton.new()
		toggle.text = OPTION_LABELS[key]
		toggle.button_pressed = GameSettings.options[key]
		toggle.add_theme_font_size_override("font_size", 20)
		options_row.add_child(toggle)
		option_toggles[key] = toggle
	car_option.item_selected.connect(_on_car_selected)
	track_option.item_selected.connect(_update_play.unbind(1))
	play_button.pressed.connect(_play)
	_update_play()
	car_option.grab_focus()


func _on_car_selected(_index: int) -> void:
	_fill_colors(colors[color_option.selected] if color_option.selected >= 0 else "")
	_update_parts()
	_update_play()


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
	img.fill(Color(0.5, 0.5, 0.5))
	img.fill_rect(Rect2i(1, 1, SWATCH - 2, SWATCH - 2), color)
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
	note.text = "" if can_play else "Chybí data v decomposed/ – spusť převodníky z tools/ (viz game/README.md)."


func _play() -> void:
	if play_button.disabled:
		return
	GameSettings.car_key = car_keys[car_option.selected]
	GameSettings.track_name = track_names[track_option.selected]
	GameSettings.time_of_day = times[time_option.selected]
	GameSettings.car_color = colors[color_option.selected] if color_option.selected >= 0 else ""
	GameSettings.car_tune = CarParts.TUNES[maxi(tune_option.selected, 0)]
	GameSettings.tyres = CarParts.TYRES[maxi(tyre_option.selected, 0)]
	for key: String in option_toggles:
		GameSettings.options[key] = (option_toggles[key] as CheckButton).button_pressed
	GameSettings.save_last()
	get_tree().change_scene_to_file(GAME_SCENE)


## Enter plays even while the focus is on a dropdown (there Enter would open the list; Space or
## gamepad A still does). An open list is a popup window and gets its keys before this.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var joy := event as InputEventJoypadButton
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_play()
		elif key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			get_tree().quit()
	elif joy != null and joy.pressed and joy.button_index == JOY_BUTTON_START:
		get_viewport().set_input_as_handled()
		_play()
