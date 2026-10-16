class_name Gauge
extends Control
## Round analogue dial in a classic style: chrome bezel, black face, teal scale with a fan of
## concentric arcs, red hatched zone, grey inner circle, silver needle. Drawn procedurally,
## scales with the control size. The needle follows `value` as a damped spring.

const TEAL := Color("2fd0a2")
const RED := Color("e0352f")
const RING_GREY := Color(0.62, 0.63, 0.64)
const FACE := Color(0.035, 0.038, 0.042)
const START_ANGLE := deg_to_rad(150.0)  ## value 0, lower left (screen angles, clockwise from +x)
const SWEEP := deg_to_rad(240.0)

@export var max_value := 8000.0:
	set(v):
		max_value = v
		queue_redraw()
@export var major_step := 1000.0:  ## numbered, long ticks
	set(v):
		major_step = v
		queue_redraw()
@export var minor_divisions := 4:  ## ticks per major step; with an even count the middle one is longer
	set(v):
		minor_divisions = v
		queue_redraw()
@export var label_divisor := 1000.0:  ## scale numbers are value / label_divisor
	set(v):
		label_divisor = v
		queue_redraw()
@export var band_from := INF:  ## fan of concentric arcs between these values, INF for none
	set(v):
		band_from = v
		queue_redraw()
@export var band_to := INF:
	set(v):
		band_to = v
		queue_redraw()
@export var band_lines := 8
@export var red_from := INF:  ## start of the red hatched zone, INF for none
	set(v):
		red_from = v
		queue_redraw()
@export var red_to := INF:
	set(v):
		red_to = v
		queue_redraw()
@export_multiline var caption := "":
	set(v):
		caption = v
		queue_redraw()
@export var sub_text := "":  ## small boxed readout in the lower half (gear)
	set(v):
		if v != sub_text:
			sub_text = v
			queue_redraw()
@export var odometer := false  ## draw the odometer window with odo_text and trip_text
@export var odo_text := "":
	set(v):
		if v != odo_text:
			odo_text = v
			queue_redraw()
@export var trip_text := "":
	set(v):
		if v != trip_text:
			trip_text = v
			queue_redraw()
@export var value := 0.0  ## target; the needle follows it with some inertia
@export var needle_frequency := 12.0  ## rad/s, natural frequency of the damped needle (0 = instant)
@export var needle_damping := 0.85  ## below 1 the needle overshoots slightly, like a real one

var _needle := 0.0
var _needle_velocity := 0.0
var _drawn := 0.0
var _font: Font


func _ready() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DIN Alternate", "Futura", "Helvetica Neue", "Arial"])
	f.font_weight = 700
	_font = f


func _process(delta: float) -> void:
	if needle_frequency <= 0.0:
		_needle = value
		_needle_velocity = 0.0
	else:
		# Spring-damper, substepped so a long frame stays stable.
		var steps := ceili(delta * needle_frequency * 4.0)
		var h := delta / maxi(steps, 1)
		for i in steps:
			var accel := needle_frequency * needle_frequency * (value - _needle) \
					- 2.0 * needle_damping * needle_frequency * _needle_velocity
			_needle_velocity += accel * h
			_needle += _needle_velocity * h
	if absf(_needle - _drawn) > max_value * 1e-4:
		queue_redraw()


func _angle(v: float) -> float:
	return START_ANGLE + SWEEP * clampf(v / max_value, 0.0, 1.0)


func _dir(v: float) -> Vector2:
	return Vector2.from_angle(_angle(v))


func _centered(text: String, pos: Vector2, font_size: int, color: Color, outline := 0) -> void:
	var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var p := pos + Vector2(-ts.x * 0.5, font_size * 0.36)
	if outline > 0:
		draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, FACE)
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var line := maxf(1.0, r * 0.012)

	# Chrome bezel: dark edge, bright polished ring with highlights, shadowed lip.
	draw_circle(c, r, Color(0.16, 0.16, 0.17))
	draw_circle(c, r * 0.975, Color(0.78, 0.79, 0.81))
	draw_arc(c, r * 0.94, deg_to_rad(190), deg_to_rad(300), 32, Color(1, 1, 1, 0.9), r * 0.035, true)
	draw_arc(c, r * 0.94, deg_to_rad(10), deg_to_rad(80), 24, Color(1, 1, 1, 0.6), r * 0.03, true)
	draw_arc(c, r * 0.94, deg_to_rad(95), deg_to_rad(160), 24, Color(0.35, 0.36, 0.38), r * 0.035, true)
	draw_circle(c, r * 0.905, Color(0.3, 0.3, 0.32))
	draw_circle(c, r * 0.89, FACE)

	# Fan of concentric arcs; the ends step inwards so the band has slanted edges.
	if band_from < band_to:
		var stagger := (band_to - band_from) * 0.06
		for i in band_lines:
			var k := float(i) / maxf(band_lines - 1, 1)  # 0 outer, 1 inner
			var rad := lerpf(r * 0.7, r * 0.5, k)
			draw_arc(c, rad, _angle(band_from + stagger * k), _angle(band_to - stagger * k * 0.5), 48, TEAL, line * 1.3, true)

	# Red zone: short radial strokes between the inner arcs and the ticks.
	if red_from < red_to:
		var strokes := 7
		for i in strokes:
			var d := _dir(lerpf(red_from, red_to, (i + 0.5) / strokes))
			draw_line(c + d * r * 0.52, c + d * r * 0.7, RED, line * 1.6, true)

	# Ticks.
	var minor := major_step / maxf(1.0, minor_divisions)
	var n := roundi(max_value / minor)
	for i in n + 1:
		var d := _dir(i * minor)
		var tick_len := 0.07
		var width := 0.02
		if i % maxi(1, minor_divisions) == 0:
			tick_len = 0.13
			width = 0.04
		elif minor_divisions % 2 == 0 and i % (minor_divisions / 2) == 0:
			tick_len = 0.1
			width = 0.026
		draw_line(c + d * r * (0.86 - tick_len), c + d * r * 0.86, TEAL, r * width)

	# Grey inner circle.
	draw_arc(c, r * 0.46, 0.0, TAU, 96, RING_GREY, line * 1.2, true)

	# Numbers, cut out of the arcs behind them.
	var digits := str(roundi(max_value / label_divisor)).length()
	var num_size := roundi(r * (0.2 if digits <= 2 else 0.15))
	var v := 0.0
	while v <= max_value + 0.5:
		var label_r := 0.6 if digits <= 2 else 0.58
		_centered(str(roundi(v / label_divisor)), c + _dir(v) * r * label_r, num_size, TEAL, roundi(r * 0.04))
		v += major_step

	# Lower half: odometer window or gear box, then caption.
	var y := c.y + r * 0.56
	if odometer:
		var box := Rect2(c.x - r * 0.28, c.y + r * 0.47, r * 0.56, r * 0.3)
		draw_rect(box, Color(0.01, 0.01, 0.01))
		draw_rect(box, Color(0.25, 0.25, 0.26), false, line)
		var os := roundi(r * 0.1)
		_centered(odo_text, Vector2(c.x, box.position.y + box.size.y * 0.3), os, Color(0.92, 0.92, 0.92))
		draw_line(Vector2(box.position.x + r * 0.06, box.get_center().y), Vector2(box.end.x - r * 0.06, box.get_center().y), Color(0.7, 0.7, 0.7), line)
		_centered("TRIP  " + trip_text, Vector2(c.x, box.position.y + box.size.y * 0.74), os, Color(0.92, 0.92, 0.92))
		y = box.end.y + r * 0.06
	if sub_text != "":
		var gs := roundi(r * 0.11)
		var gbox := Rect2(c.x - r * 0.075, c.y + r * 0.22, r * 0.15, gs * 1.15)
		draw_rect(gbox, TEAL, false, line)
		_centered(sub_text, Vector2(c.x, gbox.get_center().y - gs * 0.04), gs, TEAL)
	var cap_size := roundi(r * 0.11)
	for text in caption.split("\n"):
		_centered(text, Vector2(c.x, y), cap_size, TEAL)
		y += cap_size * 1.0

	# Needle: long tapered silver blade with a short tail, chrome centre dome.
	_drawn = _needle
	var d := _dir(_needle)
	var side := d.orthogonal()
	var tip := c + d * r * 0.84
	var tail := c - d * r * 0.16
	draw_colored_polygon(PackedVector2Array([
		tail + side * r * 0.03, c + side * r * 0.032, tip + side * r * 0.006,
		tip - side * r * 0.006, c - side * r * 0.032, tail - side * r * 0.03,
	]), Color(0.9, 0.91, 0.92))
	draw_line(c, tip, Color(1, 1, 1, 0.7), maxf(1.0, r * 0.008), true)
	draw_circle(c, r * 0.085, Color(0.25, 0.25, 0.27))
	draw_circle(c, r * 0.072, Color(0.75, 0.76, 0.78))
	draw_circle(c + Vector2(-r, -r) * 0.02, r * 0.04, Color(0.97, 0.97, 0.98))
