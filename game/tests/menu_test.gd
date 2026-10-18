extends Node
## Headless test of the main menu:
##   godot --headless --path game res://tests/menu_test.tscn
## Checks that the dropdowns list main.gd CARS, TRACKS and TIMES (day / night after the track), that entries with data in decomposed/
## are enabled and preselected, that the option toggles sit on one row between the track and Play
## showing GameSettings.options, and that missing data disables an entry instead of failing.

const Main := preload("res://scripts/main.gd")

var failures := 0


func _ready() -> void:
	print("MENU TEST")
	var menu: Control = preload("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	_expect(menu.car_option.item_count == Main.CARS.size(), "car entries %d" % menu.car_option.item_count)
	_expect(menu.track_option.item_count == Main.TRACKS.size(), "track entries %d" % menu.track_option.item_count)
	for i in menu.car_option.item_count:
		print("  car   %-14s %-28s %s" % [menu.car_keys[i], menu.car_option.get_item_text(i),
			"disabled" if menu.car_option.is_item_disabled(i) else "ok"])
	for i in menu.track_option.item_count:
		print("  track %-14s %-28s %s" % [menu.track_names[i], menu.track_option.get_item_text(i),
			"disabled" if menu.track_option.is_item_disabled(i) else "ok"])
	_expect(menu.time_option.item_count == Main.TIMES.size() and menu.time_option.selected >= 0, "time of day choice")
	var time_row: int = menu.time_option.get_index()
	_expect(time_row > menu.track_option.get_index() and time_row < menu.options_row.get_index(), "time of day after the track")
	_expect(menu.car_option.selected >= 0 and not menu.car_option.is_item_disabled(menu.car_option.selected), "car preselected")
	_expect(menu.track_option.selected >= 0 and not menu.track_option.is_item_disabled(menu.track_option.selected), "track preselected")
	_expect(not menu.play_button.disabled, "Play enabled")
	_expect(menu.option_toggles.size() == GameSettings.DEFAULT_OPTIONS.size(), "option toggles %d" % menu.option_toggles.size())
	for key: String in menu.option_toggles:
		var toggle: CheckButton = menu.option_toggles[key]
		_expect(toggle.get_parent() == menu.options_row and toggle.button_pressed == GameSettings.options[key], "toggle %s" % key)
	var row: int = menu.options_row.get_index()
	_expect(row > menu.track_option.get_index() and row < menu.play_button.get_index(), "toggles between track and Play")
	_check_colors(menu)
	_expect(not Main.track_available("no_such_track"), "missing track detected")
	_expect(not Main.car_available("no_such_car", {}), "missing car detected")
	menu._add_item(menu.track_option, "Test", false)
	_expect(menu.track_option.get_item_text(menu.track_option.item_count - 1).ends_with(menu.MISSING), "missing note")
	print("  %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	get_tree().quit(1 if failures > 0 else 0)


## Colour dropdown beside the car: "original" first, then the car's palette with the factory colour
## marked; switching cars refills it and keeps a colour both cars have.
func _check_colors(menu: Control) -> void:
	_expect(menu.color_option.get_parent() == menu.car_option.get_parent(), "colour beside car")
	_expect(menu.color_option.get_item_text(0) == menu.ORIGINAL_COLOR, "first colour is original")
	if menu.car_colors == null:
		print("  colours: no car_colors.json, only original")
		return
	var i356: int = menu.car_keys.find("356Acoupe16")
	if i356 < 0 or menu.car_option.is_item_disabled(i356):
		return
	menu.car_option.select(i356)
	menu._on_car_selected(i356)
	_expect(menu.color_option.item_count == 20, "356 A colours %d" % menu.color_option.item_count)
	_expect(menu.color_option.get_item_text(menu.colors.find("#004396")).ends_with(menu.FACTORY), "356 A factory blue")
	menu.color_option.select(menu.colors.find("#ff0000"))
	var i996: int = menu.car_keys.find("996coupe34")
	if i996 >= 0 and not menu.car_option.is_item_disabled(i996):
		menu.car_option.select(i996)
		menu._on_car_selected(i996)
		_expect(menu.colors[menu.color_option.selected] == "#ff0000", "red kept on 996")
	var i550: int = menu.car_keys.find("550Arace")
	if i550 >= 0 and not menu.car_option.is_item_disabled(i550):
		menu.car_option.select(i550)
		menu._on_car_selected(i550)
		_expect(menu.color_option.item_count == 2 and menu.color_option.selected == 0, "550 one colour, red not kept")
	print("  colours ok")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", what)
