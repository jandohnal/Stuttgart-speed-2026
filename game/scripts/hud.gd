extends CanvasLayer
## Rev counter and speedometer dials plus a small telemetry readout.

const GAUGE_SIZE := 210.0
const MARGIN := 16.0

@export var car_path: NodePath

@onready var car := get_node_or_null(car_path) as Car
@onready var label: Label = $Label

var rpm_gauge := Gauge.new()
var speed_gauge := Gauge.new()
var _scales_set := false
var _distance_m := 0.0


func _ready() -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -MARGIN
	box.offset_bottom = -MARGIN
	add_child(box)
	for g: Gauge in [speed_gauge, rpm_gauge]:
		g.custom_minimum_size = Vector2(GAUGE_SIZE, GAUGE_SIZE)
		box.add_child(g)
	rpm_gauge.caption = "UPM\nx1000\nRPM"
	speed_gauge.caption = "km/h"
	speed_gauge.major_step = 20.0
	speed_gauge.minor_divisions = 4
	speed_gauge.label_divisor = 1.0
	speed_gauge.band_from = 40.0
	speed_gauge.band_to = 70.0
	speed_gauge.odometer = true


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
	_scales_set = true


func _process(delta: float) -> void:
	if car == null or car.telemetry.is_empty():
		return
	if not _scales_set:
		_set_scales()
	var t := car.telemetry
	rpm_gauge.value = t["rpm"]
	speed_gauge.value = absf(t["speed_kmh"])
	rpm_gauge.sub_text = "R" if int(t["gear"]) == -1 else str(t["gear"])
	_distance_m += absf(float(t["speed_kmh"])) / 3.6 * delta
	speed_gauge.odo_text = "%06d" % floori(_distance_m / 1000.0)
	speed_gauge.trip_text = "%05d" % floori(_distance_m / 100.0)  # last digit is tenths of a km
	label.text = "lat %.2f g   long %.2f g   steer %.1f°   steering assist %s\n" % [
		t["lat_g"], t["long_g"], t["steer_deg"], "ON" if t["assist"] else "OFF",
	] + "W/S throttle/brake  A/D steer  Space handbrake  R reset  F2 telemetry  F3 assist  F11 full screen"
