extends Control
## Mechanical drum odometer, styled by era (IDEA-005): 1950s white serif digits on black drums
## with the lowest drum white; 1970s sans-serif with a red lowest drum; 1990s smaller sans-serif
## digits with a red lowest digit. Drawn procedurally; the drums curve away at the top and bottom
## of the window, sit very slightly out of line and can shake at high engine speed.

const OdometerLogic := preload("res://scripts/odometer_logic.gd")
const DRUM_DARK := Color(0.05, 0.05, 0.05)
const DRUM_LIGHT := Color(0.9, 0.89, 0.85)
const GAP := Color(0.0, 0.0, 0.0)
const DRUM_RED := Color(0.62, 0.07, 0.06)
const INK_RED := Color(0.95, 0.25, 0.2)

enum Era { FIFTIES, SEVENTIES, NINETIES }

@export var digits := 6:
	set(v):
		digits = v
		queue_redraw()
@export var value := 0.0:  ## in units of the lowest drum
	set(v):
		if v != value:  # exact: is_equal_approx is relative and would freeze large values
			value = v
			queue_redraw()
@export var era := Era.FIFTIES:
	set(v):
		era = v
		_font = null
		queue_redraw()
@export_range(0.0, 1.0) var shake := 0.0  ## drum vibration, e.g. from engine speed

var _font: Font


## Car era from its model year.
static func era_for_year(year: int) -> Era:
	if year < 1970:
		return Era.FIFTIES
	return Era.SEVENTIES if year < 1990 else Era.NINETIES


func _ready() -> void:
	clip_contents = true


func _process(_delta: float) -> void:
	if shake > 0.0:
		queue_redraw()


func _make_font() -> Font:
	var f := SystemFont.new()
	if era == Era.FIFTIES:
		f.font_names = PackedStringArray(["Times New Roman", "Georgia", "serif"])
		f.font_weight = 600
	else:
		f.font_names = PackedStringArray(["Helvetica Neue", "Arial", "sans-serif"])
		f.font_weight = 500
	return f


func _draw() -> void:
	if _font == null:
		_font = _make_font()
	var h := size.y
	var w := size.x / maxi(digits, 1)
	var pitch := h * 1.05  # digit spacing on the drum surface
	var radius := pitch * 10.0 / TAU
	var font_size := roundi(h * (0.75 if era == Era.NINETIES else 0.95))
	var now := Time.get_ticks_msec() / 1000.0
	var positions := OdometerLogic.drums(value, digits)
	draw_rect(Rect2(Vector2.ZERO, size), GAP)
	for i in digits:
		var drum := digits - 1 - i  # drums are stored lowest first, drawn left to right
		var x := i * w
		var cell := Rect2(x + 0.5, 0.0, w - 1.0, h)
		var drum_color := DRUM_DARK
		var ink := DRUM_LIGHT
		if drum == 0:
			match era:
				Era.FIFTIES:
					drum_color = DRUM_LIGHT
					ink = DRUM_DARK
				Era.SEVENTIES:
					drum_color = DRUM_RED
				Era.NINETIES:
					ink = INK_RED
		draw_rect(cell, drum_color)
		# Fixed, tiny misalignment per drum, plus a buzz at high engine speed.
		var jitter := (fposmod(sin(i * 12.9898 + 4.1) * 43758.5453, 1.0) - 0.5) * 0.06 * h
		jitter += sin(now * 47.0 + i * 1.7) * shake * 0.025 * h
		var p := positions[drum]
		var base := floorf(p)
		for k in range(-1, 2):
			var angle := (k - (p - base)) * TAU / 10.0
			if absf(angle) >= PI * 0.5:
				continue
			var digit := str(posmod(int(base) + k, 10))
			var ts := _font.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var centre := Vector2(x + w * 0.5, h * 0.5 + radius * sin(angle) + jitter)
			draw_set_transform(centre, 0.0, Vector2(1.0, cos(angle)))
			draw_string(_font, Vector2(-ts.x * 0.5, font_size * 0.34), digit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
		draw_set_transform(Vector2.ZERO)
		_shade(cell)


## Darkens the top and bottom of a drum so it reads as a cylinder.
func _shade(cell: Rect2) -> void:
	var band := cell.size.y * 0.32
	var dark := Color(0, 0, 0, 0.75)
	var clear := Color(0, 0, 0, 0)
	var x0 := cell.position.x
	var x1 := cell.end.x
	var y0 := cell.position.y
	var y1 := cell.end.y
	draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y0 + band), Vector2(x0, y0 + band)]),
			PackedColorArray([dark, dark, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(x0, y1 - band), Vector2(x1, y1 - band), Vector2(x1, y1), Vector2(x0, y1)]),
			PackedColorArray([clear, clear, dark, dark]))
