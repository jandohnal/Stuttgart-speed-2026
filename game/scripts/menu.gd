extends Control
## Main menu of the prototype (D-009): car and track dropdowns, a row of option toggles (driver
## aids, sound, diagnostics) and Play. The lists come from main.gd (CARS, TRACKS); entries whose
## data is missing in decomposed/ are disabled. The choice goes to the GameSettings autoload and
## user://settings.cfg, then the game scene takes over. The options are set only here, not in game.
## Keyboard / gamepad: arrows or D-pad move the focus, Enter (anywhere) or Start plays, Esc quits.

const Main := preload("res://scripts/main.gd")
const GAME_SCENE := "res://scenes/main.tscn"
const MISSING := " – chybí data"
## GameSettings option -> toggle label, in the order of the row.
const OPTION_LABELS := {
	"steering_assist": "Asistent řízení",
	"brake_assist": "ABS",
	"traction_control": "Kontrola trakce",
	"sound": "Zvuk",
	"diagnostics": "Diagnostika",
}

@onready var car_option: OptionButton = %CarOption
@onready var track_option: OptionButton = %TrackOption
@onready var play_button: Button = %PlayButton
@onready var note: Label = %Note
@onready var options_row: HBoxContainer = %Options

var car_keys: Array[String] = []
var track_names: Array[String] = []
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
	_preselect(car_option, car_keys.find(last["car"]))
	_preselect(track_option, track_names.find(last["track"]))
	for key: String in OPTION_LABELS:
		var toggle := CheckButton.new()
		toggle.text = OPTION_LABELS[key]
		toggle.button_pressed = GameSettings.options[key]
		toggle.add_theme_font_size_override("font_size", 20)
		options_row.add_child(toggle)
		option_toggles[key] = toggle
	car_option.item_selected.connect(_update_play.unbind(1))
	track_option.item_selected.connect(_update_play.unbind(1))
	play_button.pressed.connect(_play)
	_update_play()
	car_option.grab_focus()


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
