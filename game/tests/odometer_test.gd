extends Node
## Headless test of the odometer drum logic:
##   godot --headless --path game res://tests/odometer_test.tscn
## Checks that higher drums stand still outside a carry, roll together during one, and land on
## whole digits after it. With a window it then shows one speedometer per era whose odometer runs
## fast through 99 999.5 -> 100 000.5 km (trip 999.5 -> 0.5) so the carry can be watched; the
## drums shake for the second half.

const OdometerLogic := preload("res://scripts/odometer_logic.gd")
const Odometer := preload("res://scripts/odometer.gd")
const SHOW_TIME := 6.0

var failures := 0
var gauges: Array[Gauge] = []
var t := 0.0


func _ready() -> void:
	print("ODOMETER TEST")
	_check(0.5, [0.5, 0, 0, 0])
	_check(9.95, [9.95, 0.95, 0, 0])
	_check(123.4, [3.4, 2, 1, 0])
	_check(999.95, [9.95, 9.95, 9.95, 0.95])
	_check(1000.0, [0, 0, 0, 1])
	_check(12345.6, [5.6, 4, 3, 2, 1])
	_check(-3.0, [0, 0, 0, 0])
	print("  %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if failures > 0 else 0)
		return
	RenderingServer.set_default_clear_color(Color(0.25, 0.3, 0.35))
	for era: int in Odometer.Era.values():
		var gauge := Gauge.new()
		gauge.max_value = 180.0
		gauge.major_step = 20.0
		gauge.label_divisor = 1.0
		gauge.caption = "km/h"
		gauge.odometer = true
		gauge.position = Vector2(12 + era * 380, 140)
		gauge.size = Vector2(370, 370)
		add_child(gauge)
		gauge.odo_era = era
		gauges.append(gauge)


func _process(delta: float) -> void:
	if gauges.is_empty():
		return
	t += delta
	var m := lerpf(99999.5, 100000.5, t / SHOW_TIME) * 1000.0
	for gauge in gauges:
		gauge.odo_m = m
		gauge.trip_m = fposmod(m, 1000000.0)
		gauge.value = 60.0
		gauge.odo_shake = 1.0 if t > SHOW_TIME * 0.5 else 0.0
	if t > SHOW_TIME:
		get_tree().quit(1 if failures > 0 else 0)


func _check(value: float, expected: Array) -> void:
	var got := OdometerLogic.drums(value, expected.size())
	var ok := true
	for i in expected.size():
		ok = ok and absf(got[i] - float(expected[i])) < 1e-3
	if not ok:
		failures += 1
	print("  %10.2f -> %s %s" % [value, Array(got).map(func(x: float) -> String: return "%.2f" % x), "ok" if ok else "FAIL, expected %s" % [expected]])
