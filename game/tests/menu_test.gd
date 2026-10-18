extends Node
## Headless test of the main menu:
##   godot --headless --path game res://tests/menu_test.tscn
## Checks that the dropdowns list main.gd CARS and TRACKS, that entries with data in decomposed/
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
	_expect(menu.car_option.selected >= 0 and not menu.car_option.is_item_disabled(menu.car_option.selected), "car preselected")
	_expect(menu.track_option.selected >= 0 and not menu.track_option.is_item_disabled(menu.track_option.selected), "track preselected")
	_expect(not menu.play_button.disabled, "Play enabled")
	_expect(menu.option_toggles.size() == GameSettings.DEFAULT_OPTIONS.size(), "option toggles %d" % menu.option_toggles.size())
	for key: String in menu.option_toggles:
		var toggle: CheckButton = menu.option_toggles[key]
		_expect(toggle.get_parent() == menu.options_row and toggle.button_pressed == GameSettings.options[key], "toggle %s" % key)
	var row: int = menu.options_row.get_index()
	_expect(row > menu.track_option.get_index() and row < menu.play_button.get_index(), "toggles between track and Play")
	_expect(not Main.track_available("no_such_track"), "missing track detected")
	_expect(not Main.car_available("no_such_car", {}), "missing car detected")
	menu._add_item(menu.track_option, "Test", false)
	_expect(menu.track_option.get_item_text(menu.track_option.item_count - 1).ends_with(menu.MISSING), "missing note")
	print("  %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", what)
