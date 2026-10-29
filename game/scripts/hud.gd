class_name Hud
extends CanvasLayer
## Rev counter and speedometer dials, a small telemetry readout and the race stopwatch.

const Odometer := preload("res://scripts/odometer.gd")
const GAUGE_SIZE := 210.0
const MARGIN := 16.0
const GAUGE_OPACITY := 0.6

@export var car_path: NodePath
## Telemetry readout (g forces, steering, TC cut, boost, damage); set from the menu option.
@export var diagnostics := true

@onready var car := get_node_or_null(car_path) as Car
@onready var label: Label = $Label

var rpm_gauge := Gauge.new()
var speed_gauge := Gauge.new()
var _scales_set := false
var _gauge_box := HBoxContainer.new()
var race: RaceTimer  ## set by main on tracks with start / finish lines
var _stopwatch := _big_label(40)
var _banner := _big_label(96)  ## countdown, GO, finish


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
	# Top right: the help and diagnostics text runs along the top left.
	_stopwatch.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_stopwatch.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	for l: Label in [_stopwatch, _banner]:
		l.visible = false
		add_child(l)


static func _big_label(font_size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", font_size / 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l


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
	var text := ""
	if diagnostics:
		text = "lat %.2f g   long %.2f g   steer %.1f°%s\n" % [t["lat_g"], t["long_g"], t["steer_deg"],
			"   TC -%d%%" % roundi(t["tc_cut"] * 100.0) if t["tc_cut"] > 0.02 else ""] \
			+ ("boost %d%%\n" % roundi(t["boost"] * 100.0) if car.turbo else "") + _damage_text(t.get("damage", {}))
	label.text = text + "W/S throttle/brake  A/D steer  Space handbrake  R reset  %sF2 telemetry  F5 repair  F11 full screen  Esc menu" \
		% ("Backspace restart  " if race != null else "")
	_update_race()


func _update_race() -> void:
	if race == null:
		return
	_stopwatch.visible = true
	_stopwatch.text = RaceTimer.format_time(race.elapsed)
	_banner.visible = true
	_banner.modulate = Color.WHITE
	match race.state:
		RaceTimer.State.COUNTDOWN:
			_banner.text = str(ceili(race.countdown))
		RaceTimer.State.RUNNING:
			var go := race.since_go()
			_banner.visible = go >= 0.0
			_banner.text = "GO!"
			_banner.modulate.a = 1.0 - go / RaceTimer.GO_SHOW_TIME
		RaceTimer.State.FINISHED:
			var text := "FINISH  %s" % RaceTimer.format_time(race.elapsed)
			if race.previous_best < INF:
				var diff := race.elapsed - race.previous_best
				text += "\nbest %s  (%+.2f s)" % [RaceTimer.format_time(race.previous_best), diff]
			_banner.text = text + "\nBackspace: race again"
			_banner.add_theme_font_size_override("font_size", 48)
			return
	_banner.add_theme_font_size_override("font_size", 96)


func _damage_text(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	return "damage  front %d%%  rear %d%%  left %d%%  right %d%%  roof %d%%   engine -%d%%   parts lost %d  loose %d\n" % [
		roundi(d["front"] * 100.0), roundi(d["rear"] * 100.0), roundi(d["left"] * 100.0),
		roundi(d["right"] * 100.0), roundi(d["roof"] * 100.0), roundi(d["engine"] * 100.0), int(d["lost"]), int(d["loose"])]
