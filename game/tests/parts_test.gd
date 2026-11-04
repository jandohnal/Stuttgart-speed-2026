extends Node
## Headless test of the performance parts (CarParts, FEData/Data/parts.json from tools/parts.py):
##   godot --headless --path game res://tests/parts_test.tscn
## Checks that the factory parts leave every car's .sim values as they are, that Sport makes the
## 356 A 1600 stronger, lighter and better braking, that slicks add grip and rain tyres lose it on
## dry asphalt, that the cars the original keeps stock (GT3) stay stock, and that the menu puts
## Stock / Sport between the car and its colour and the tyres above the track.

const Main := preload("res://scripts/main.gd")
const CarParts := preload("res://scripts/car_parts.gd")

var failures := 0


func _ready() -> void:
	print("PARTS TEST")
	var cars: Variant = OriginalAssets.load_json(Main.CAR_PHYSICS)
	var parts: Variant = OriginalAssets.load_json(CarParts.FILE)
	if not cars is Dictionary or not parts is Dictionary:
		print("  data missing (tools/sim_dump.py, tools/parts.py)")
		get_tree().quit(1)
		return
	for key: String in parts["cars"]:
		var sim: Dictionary = cars[key]
		var fitted := sim.duplicate(true)
		for id: Variant in parts["cars"][key]["stock"]:
			CarParts.apply_part(fitted, parts["parts"][str(int(id))], parts["formula"])
		fitted.erase("tyre_type")
		_expect(_same(fitted, sim), "%s: factory parts are neutral" % key)
	var base: Dictionary = cars["356Acoupe16"]
	var sport := CarParts.apply(base, parts, "356Acoupe16", "sport", "stock")
	print("  356Acoupe16 stock -> sport: %.0f -> %.0f kg, torque %.1f -> %.1f Nm, brakes %.2f -> %.2f, grip %.3f -> %.3f" % [
		base["mass_kg"], sport["mass_kg"], base["torque_peak_nm"], sport["torque_peak_nm"],
		base["unknown"]["0x104"], sport["unknown"]["0x104"], base["unknown"]["0x0F4"], sport["unknown"]["0x0F4"]])
	_expect(sport["mass_kg"] < base["mass_kg"], "sport is lighter")
	_expect(sport["torque_peak_nm"] > base["torque_peak_nm"], "sport has more torque")
	_expect(sport["unknown"]["0x104"] > base["unknown"]["0x104"], "sport brakes harder")
	_expect(sport["unknown"]["0x0F4"] > base["unknown"]["0x0F4"], "sport has more grip")
	var slick := CarParts.apply(base, parts, "356Acoupe16", "stock", "slick")
	var rain := CarParts.apply(base, parts, "356Acoupe16", "stock", "rain")
	print("  356Acoupe16 tyres: slick 0x0F4 %.3f x %.2f, rain 0x0F4 %.3f x %.2f" % [
		slick["unknown"]["0x0F4"], slick["tyre_grip_factor"], rain["unknown"]["0x0F4"], rain["tyre_grip_factor"]])
	_expect(slick["tyre_type"] == 2 and slick["tyre_grip_factor"] > 1.0, "slicks grip more on asphalt")
	_expect(rain["tyre_type"] == 1 and rain["tyre_grip_factor"] < 1.0, "rain tyres grip less on dry asphalt")
	var gt3 := CarParts.apply(cars["GT3race"], parts, "GT3race", "sport", "slick")
	_expect(not CarParts.upgradable(CarParts.car_entry(parts, "GT3race")), "GT3 has no Sport")
	gt3.erase("tyre_type")
	gt3.erase("tyre_grip_factor")
	_expect(_same(gt3, cars["GT3race"]), "GT3 stays stock")
	_expect(CarParts.tyre_choices(CarParts.car_entry(parts, "996coupe34")) == ["stock", "slick", "rain"], "996 tyres")
	var menu: Control = preload("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	_expect(_row(menu.car_option) < _row(menu.tune_option) and _row(menu.tune_option) < _row(menu.color_option),
		"Stock / Sport between car and colour")
	_expect(_row(menu.tyre_option) < _row(menu.track_option), "tyres above the track")
	menu.car_option.select(menu.car_keys.find("GT3race"))
	menu._on_car_selected(menu.car_option.selected)
	_expect(menu.tune_option.disabled and menu.tune_option.selected == 0, "menu: GT3 stock only")
	menu.car_option.select(menu.car_keys.find("356Acoupe16"))
	menu._on_car_selected(menu.car_option.selected)
	_expect(not menu.tune_option.disabled and not menu.tyre_option.disabled, "menu: 356 A Sport and tyres")
	print("  %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	get_tree().quit(1 if failures > 0 else 0)


## Equal up to float rounding (the formulas multiply by factors that are exactly 1 for stock parts).
func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k: Variant in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 1e-3 * maxf(1.0, absf(float(b)))
	return a == b


## Position of the menu row holding `option` in the RACE SETUP panel.
func _row(option: Control) -> int:
	return option.get_parent().get_index()


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL %s" % what)
