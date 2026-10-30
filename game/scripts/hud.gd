class_name Hud
extends CanvasLayer
## Rev counter and speedometer dials, a small telemetry readout and the race stopwatch. With
## RaceStandings: the player's place and every car's gap to the player under the stopwatch while
## racing, and the results (place, time, gap) under the finish banner once the player is in
## (the cars behind with an estimated time, marked ~).

const Odometer := preload("res://scripts/odometer.gd")
const GAUGE_SIZE := 210.0
const MARGIN := 16.0
const GAUGE_OPACITY := 0.6
const LAP_BANNER_TIME := 1.5  ## s the "LAP n/N" banner shows after crossing the line on a circuit

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
var standings: RaceStandings  ## set by main with the race
var _place := _big_label(32)  ## "P2/4"
var _order := GridContainer.new()  ## place, name, gap while racing
var _results := GridContainer.new()  ## place, name, time, gap after the player's finish
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
	_stopwatch.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	for l: Label in [_stopwatch, _banner]:
		l.visible = false
		add_child(l)
	_place.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_place.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_place.position.y += 120.0  # below the stopwatch and the help line
	_order.columns = 3
	_order.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_order.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_order.position.y += 168.0
	_results.columns = 4
	# Top centre, below the help line: the finish banner is in the middle, the dials bottom right.
	_results.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 130)
	_results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	for c: Control in [_place, _order, _results]:
		c.visible = false
		add_child(c)
	for g: GridContainer in [_order, _results]:
		g.add_theme_constant_override("h_separation", 18)
		g.add_theme_constant_override("v_separation", 2)


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
	if race.laps > 1:
		_stopwatch.text += "\nLAP %d/%d" % [race.lap, race.laps] if race.state != RaceTimer.State.FINISHED else ""
		if race.last_lap < INF:
			_stopwatch.text += "\nlast %s" % RaceTimer.format_time(race.last_lap)
	_banner.visible = true
	_banner.modulate = Color.WHITE
	match race.state:
		RaceTimer.State.COUNTDOWN:
			_banner.text = str(ceili(race.countdown))
		RaceTimer.State.RUNNING:
			var go := race.since_go()
			var on_lap := race.elapsed - race.lap_start
			_banner.visible = go >= 0.0 or race.lap > 1 and on_lap < LAP_BANNER_TIME
			if go >= 0.0:
				_banner.text = "GO!"
				_banner.modulate.a = 1.0 - go / RaceTimer.GO_SHOW_TIME
			else:
				_banner.text = "FINAL LAP" if race.lap == race.laps else "LAP %d/%d" % [race.lap, race.laps]
				_banner.modulate.a = 1.0 - on_lap / LAP_BANNER_TIME
		RaceTimer.State.FINISHED:
			_update_standings(true)
			var text := "FINISH  %s" % RaceTimer.format_time(race.elapsed)
			if race.previous_best < INF:
				var diff := race.elapsed - race.previous_best
				text += "\nbest %s  (%+.2f s)" % [RaceTimer.format_time(race.previous_best), diff]
			_banner.text = text + "\nBackspace: race again"
			_banner.add_theme_font_size_override("font_size", 48)
			return
	_banner.add_theme_font_size_override("font_size", 96)
	_update_standings(false)


func _damage_text(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	return "damage  front %d%%  rear %d%%  left %d%%  right %d%%  roof %d%%   engine -%d%%   parts lost %d  loose %d\n" % [
		roundi(d["front"] * 100.0), roundi(d["rear"] * 100.0), roundi(d["left"] * 100.0),
		roundi(d["right"] * 100.0), roundi(d["roof"] * 100.0), roundi(d["engine"] * 100.0), int(d["lost"]), int(d["loose"])]


## Place and gaps while racing (`finished` false), the results table once the player is in.
func _update_standings(finished: bool) -> void:
	var racing := standings != null and standings.entries.size() > 1 and race.state != RaceTimer.State.COUNTDOWN
	_place.visible = racing and not finished
	_order.visible = racing and not finished
	_results.visible = racing and finished
	if not racing:
		return
	var order := standings.order()
	if not finished:
		_place.text = "P%d/%d" % [standings.player_position(), order.size()]
		_fill(_order, order, false)
	else:
		_fill(_results, order, true)


## One row per car: place, name, (time,) gap to the player; the player's row in yellow.
func _fill(grid: GridContainer, order: Array, with_time: bool) -> void:
	var cells: Array[String] = []
	var player_row := -1
	for k in order.size():
		var e: RaceStandings.Entry = order[k]
		var is_player: bool = e == standings.entries[0]
		if is_player:
			player_row = k
		cells.append("%d" % (k + 1))
		cells.append(e.name)
		if with_time:
			var time := RaceTimer.format_time(e.finish_time) if e.finish_time >= 0.0 else "racing"
			cells.append("~" + time if e.estimated else time)
		cells.append("" if is_player else "%+.2f" % standings.gap_to_player(e))
	var size := 28 if with_time else 22
	while grid.get_child_count() < cells.size():
		var l := _big_label(size)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for i in grid.get_child_count():
		var l := grid.get_child(i) as Label
		l.visible = i < cells.size()
		if i < cells.size():
			l.text = cells[i]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i % grid.columns == 1 else HORIZONTAL_ALIGNMENT_RIGHT
			l.modulate = Color(1.0, 0.85, 0.3) if i / grid.columns == player_row else Color.WHITE
