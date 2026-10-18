extends CanvasLayer
## Rev counter and speedometer dials plus a small telemetry readout.

const Odometer := preload("res://scripts/odometer.gd")
const GAUGE_SIZE := 210.0
const MARGIN := 16.0
const GAUGE_OPACITY := 0.6

@export var car_path: NodePath

@onready var car := get_node_or_null(car_path) as Car
@onready var label: Label = $Label

var rpm_gauge := Gauge.new()
var speed_gauge := Gauge.new()
var _scales_set := false
const TRIP_RESET_TIME := 0.8  ## s for the trip drums to roll back to zero

var _trip_start_m := 0.0
var _trip_reset: Tween
var _gauge_box := HBoxContainer.new()


func _ready() -> void:
	# Drawn into one group first so the fade applies to the finished dials, not each layer.
	# The group is a Node2D, so the box is placed by hand instead of anchored.
	var group := CanvasGroup.new()
	group.self_modulate.a = GAUGE_OPACITY
	add_child(group)
	_gauge_box.add_theme_constant_override("separation", 12)
	group.add_child(_gauge_box)
	for g: Gauge in [speed_gauge, rpm_gauge]:
		g.custom_minimum_size = Vector2(GAUGE_SIZE, GAUGE_SIZE)
		_gauge_box.add_child(g)
	get_viewport().size_changed.connect(_place_gauges)
	_place_gauges.call_deferred()
	rpm_gauge.caption = "UPM\nx1000\nRPM"
	speed_gauge.caption = "km/h"
	speed_gauge.major_step = 20.0
	speed_gauge.minor_divisions = 4
	speed_gauge.label_divisor = 1.0
	speed_gauge.band_from = 40.0
	speed_gauge.band_to = 70.0
	speed_gauge.odometer = true


func _place_gauges() -> void:
	_gauge_box.size = _gauge_box.get_combined_minimum_size()
	_gauge_box.position = get_viewport().get_visible_rect().size - _gauge_box.size - Vector2(MARGIN, MARGIN)


## Scales come from the car data, which is loaded once the car is ready.
func _set_scales() -> void:
	rpm_gauge.max_value = ceilf(car.redline / 1000.0) * 1000.0 + 2000.0
	rpm_gauge.red_from = car.redline
	rpm_gauge.red_to = car.redline + 1000.0
	rpm_gauge.band_from = roundf(car.redline / 3.0 / 500.0) * 500.0
	rpm_gauge.band_to = car.redline
	var top_kmh := 160.0
	if not car.gear_ratios.is_empty():
		var wheel_rpm := car.redline / (car.gear_ratios[-1] * car.final_drive)
		top_kmh = maxf(top_kmh, wheel_rpm * TAU / 60.0 * car.wheel_radius * 3.6)
	speed_gauge.max_value = ceilf(top_kmh / 20.0) * 20.0
	_trip_start_m = car.odometer_m  # mileage is loaded with the car; the trip starts at zero
	var year := str(car.params.get("name", "")).get_slice(" ", 0)
	if year.is_valid_int():
		speed_gauge.odo_era = Odometer.era_for_year(year.to_int())
	_scales_set = true


func _process(_delta: float) -> void:
	if car == null or car.telemetry.is_empty():
		return
	if not _scales_set:
		_set_scales()
	var t := car.telemetry
	rpm_gauge.value = t["rpm"]
	speed_gauge.value = absf(t["speed_kmh"])
	rpm_gauge.sub_text = "R" if int(t["gear"]) == -1 else str(t["gear"])
	speed_gauge.odo_m = car.odometer_m
	speed_gauge.odo_shake = clampf((car.rpm / car.redline - 0.75) / 0.25, 0.0, 1.0)
	if _trip_reset == null or not _trip_reset.is_running():
		speed_gauge.trip_m = car.odometer_m - _trip_start_m
	label.text = "lat %.2f g   long %.2f g   steer %.1f°   steering assist %s   ABS %s   TC %s%s   sound %s\n" % [
		t["lat_g"], t["long_g"], t["steer_deg"], "ON" if t["assist"] else "OFF", "ON" if t["abs"] else "OFF",
		"ON" if t["tc"] else "OFF", " (-%d%%)" % roundi(t["tc_cut"] * 100.0) if t["tc_cut"] > 0.02 else "",
		"OFF" if AudioServer.is_bus_mute(0) else "ON",
	] + ("boost %d%%\n" % roundi(t["boost"] * 100.0) if car.turbo else "") + _damage_text(t.get("damage", {})) \
		+ "W/S throttle/brake  A/D steer  Space handbrake  R reset  F2 telemetry  F3 assist  F4 ABS  F5 repair  F6 TC  T trip  M sound  F11 full screen"


## Trip reset: like pressing the knob, the drums roll back to zero instead of jumping.
func _unhandled_input(event: InputEvent) -> void:
	if car == null or not event.is_action_pressed("trip_reset"):
		return
	_trip_start_m = car.odometer_m
	if _trip_reset != null:
		_trip_reset.kill()
	_trip_reset = create_tween()
	_trip_reset.tween_property(speed_gauge, "trip_m", 0.0, TRIP_RESET_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _damage_text(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	return "damage  front %d%%  rear %d%%  left %d%%  right %d%%  roof %d%%   engine -%d%%   parts lost %d  loose %d\n" % [
		roundi(d["front"] * 100.0), roundi(d["rear"] * 100.0), roundi(d["left"] * 100.0),
		roundi(d["right"] * 100.0), roundi(d["roof"] * 100.0), roundi(d["engine"] * 100.0), int(d["lost"]), int(d["loose"])]
