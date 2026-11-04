extends Control
## Round cut-out of the road map, bottom left in the HUD: the player's arrow stays in the centre
## pointing up, the road turns and slides around it (heading up). Opponents are dots in their paint;
## one beyond the map's range stays on the rim, in its direction, as a smaller dot.

const MAP_SIZE := 170.0
const RANGE_M := 300.0  ## m from the player to the rim
const POINT_STEP := 3  ## every n-th road slice (slices are about 6 m apart)
const ROAD_WIDTH := 3.5
const ROAD_BORDER := 2.0  ## on each side
const DOT_RADIUS := 4.5
const RIM_DOT_RADIUS := 3.0
const RIM_INSET := 7.0  ## px from the rim to the centre of a dot out of range
const MIN_HEADING := 0.2  ## length of the forward vector on the ground below which the car keeps its last heading
const DISC := Color(0.035, 0.038, 0.042, 0.6)
const ROAD := Color(0.85, 0.86, 0.84)
const BORDER := Color(0.0, 0.0, 0.0, 0.55)
const RING := Color(0.62, 0.63, 0.64)
const PLAYER := Color(1.0, 0.85, 0.3)
const DEFAULT_DOT := Color(0.9, 0.2, 0.2)
const ARROW := [Vector2(0.0, -9.0), Vector2(6.0, 7.0), Vector2(0.0, 3.5), Vector2(-6.0, 7.0)]

var player: Node3D
var _lines: Array[PackedVector2Array] = []  ## road segments on the ground (world x, z)
var _others: Array[Dictionary] = []  ## {car: Node3D, color: Color}
var _forward := Vector2(0.0, -1.0)


func _init() -> void:
	custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Shows the map of `road` around `player_car`.
func setup(road: Road, player_car: Node3D) -> void:
	player = player_car
	_lines = road_lines(road)
	visible = not _lines.is_empty()


## Adds an opponent's dot; `paint` is "#rrggbb" (anything else: the default colour).
func add_car(opponent: Node3D, paint: String) -> void:
	_others.append({"car": opponent, "color": Color.html(paint) if Color.html_is_valid(paint) else DEFAULT_DOT})


## World x, z of each road segment, thinned out; a segment runs on to the slice it links to.
static func road_lines(road: Road) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	for segment: Dictionary in road.segments:
		var line := PackedVector2Array()
		var first := int(segment["first"])
		var last := int(segment["last"])
		for i in range(first, last, POINT_STEP):
			line.append(_ground(road.positions[i]))
		line.append(_ground(road.positions[last]))
		if segment.get("closed", false):
			line.append(_ground(road.positions[first]))
		elif segment.get("next") != null:
			line.append(_ground(road.positions[int(road.segments[int(segment["next"])]["first"])]))
		lines.append(line)
	return lines


## Ground to map: `position` goes to the origin, `forward` (unit) points up on the screen and the
## car's right to the right, `scale_px` is px per metre.
static func map_transform(position: Vector2, forward: Vector2, scale_px: float) -> Transform2D:
	var right := Vector2(-forward.y, forward.x)
	var basis := Transform2D(Vector2(right.x, -forward.x) * scale_px, Vector2(right.y, -forward.y) * scale_px, Vector2.ZERO)
	basis.origin = -basis.basis_xform(position)
	return basis


## The parts of a polyline inside the circle around the origin, cut at its edge.
static func clip_to_circle(points: PackedVector2Array, radius: float) -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	var was_inside := false
	for i in points.size():
		var inside := points[i].length_squared() <= radius * radius
		if i > 0 and inside != was_inside:
			var cut := points[i - 1].lerp(points[i], maxf(Geometry2D.segment_intersects_circle(points[i - 1], points[i], Vector2.ZERO, radius), 0.0))
			run.append(cut)
			if was_inside:
				runs.append(run)
				run = PackedVector2Array()
		if inside:
			run.append(points[i])
		was_inside = inside
	if run.size() >= 2:
		runs.append(run)
	return runs


## Road inside the map for a car at `position` heading along `forward`, in px around the centre.
func visible_runs(position: Vector2, forward: Vector2) -> Array[PackedVector2Array]:
	var to_map := map_transform(position, forward, MAP_SIZE * 0.5 / RANGE_M)
	var runs: Array[PackedVector2Array] = []
	for line in _lines:
		runs.append_array(clip_to_circle(to_map * line, MAP_SIZE * 0.5))
	return runs


func _process(_delta: float) -> void:
	if player != null and visible:
		queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var heading := _ground(-player.global_basis.z)
	if heading.length() > MIN_HEADING:
		_forward = heading.normalized()
	var position_now := _ground(player.global_position)
	var radius := MAP_SIZE * 0.5
	draw_set_transform(size * 0.5)
	draw_circle(Vector2.ZERO, radius, DISC, true, -1.0, true)
	var runs := visible_runs(position_now, _forward)
	for run in runs:
		draw_polyline(run, BORDER, ROAD_WIDTH + ROAD_BORDER * 2.0, true)
	for run in runs:  # after all the borders, so a junction reads as one road
		draw_polyline(run, ROAD, ROAD_WIDTH, true)
	_draw_others(map_transform(position_now, _forward, radius / RANGE_M), radius)
	draw_colored_polygon(PackedVector2Array(ARROW), PLAYER)
	var outline := PackedVector2Array(ARROW)
	outline.append(ARROW[0])
	draw_polyline(outline, Color.BLACK, 1.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, RING, 3.0, true)


func _draw_others(to_map: Transform2D, radius: float) -> void:
	for other in _others:
		var car: Node3D = other["car"]
		if not is_instance_valid(car):
			continue
		var p := to_map * _ground(car.global_position)
		var in_range := p.length() <= radius - RIM_INSET
		var dot := DOT_RADIUS if in_range else RIM_DOT_RADIUS
		if not in_range:
			p = p.limit_length(radius - RIM_INSET)
		draw_circle(p, dot, other["color"], true, -1.0, true)
		draw_circle(p, dot, Color.WHITE, false, 1.0, true)


static func _ground(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
