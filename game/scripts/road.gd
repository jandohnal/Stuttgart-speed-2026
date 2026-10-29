class_name Road
extends RefCounted
## The original's road (SimD slices from <track>_road.json): slice frames and the way the
## segments link up. Shared by main (resets, the stop after the finish) and AIDriver.

var slices: Array = []  ## the road file's slices {position, up, forward, right, flags, widths}
var segments: Array = []  ## {first, last, length_m, closed, next}
var positions := PackedVector3Array()
var forwards := PackedVector3Array()
var rights := PackedVector3Array()
var ups := PackedVector3Array()
var _segment_index := PackedInt32Array()  ## segment of each slice, -1 = none


func _init(road: Dictionary = {}) -> void:
	slices = road.get("slices", [])
	segments = road.get("segments", [])
	for s: Dictionary in slices:
		positions.append(vec(s["position"]))
		forwards.append(vec(s["forward"]))
		rights.append(vec(s["right"]))
		ups.append(vec(s["up"]))
	_segment_index.resize(slices.size())
	_segment_index.fill(-1)
	for k in segments.size():
		for i in range(int(segments[k]["first"]), int(segments[k]["last"]) + 1):
			_segment_index[i] = k


func size() -> int:
	return slices.size()


## Slice closest to `pos`, over the whole road.
func nearest(pos: Vector3) -> int:
	var best := 0
	var best_dist := INF
	for i in positions.size():
		var d := positions[i].distance_squared_to(pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best


## Slice closest to `pos` among `index` and the `window` slices after it along the road; cheap
## tracking of a car that was at `index` a moment ago.
func nearest_ahead(pos: Vector3, index: int, window: int) -> int:
	var best := index
	var best_dist := positions[index].distance_squared_to(pos)
	var i := index
	for n in window:
		var j := ahead(i, 1)
		if j == i:
			break
		i = j
		var d := positions[i].distance_squared_to(pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best


## Index of the slice `count` slices after `index` along the road: within its segment, then into
## the segment it continues into ("next", e.g. the laps of Monte Carlo), wrapping closed segments
## and stopping at the end of a road that goes nowhere.
func ahead(index: int, count: int) -> int:
	var k := _segment_index[index] if index < _segment_index.size() else -1
	if k < 0:
		return (index + count) % slices.size()
	var seg: Dictionary = segments[k]
	var i := index
	var left := count
	while left > 0:
		var last := int(seg["last"])
		if i < last:
			var step := mini(left, last - i)
			i += step
			left -= step
		elif seg["closed"]:
			i = int(seg["first"])
			left -= 1
		elif seg.get("next") != null:
			seg = segments[int(seg["next"])]
			i = int(seg["first"])
			left -= 1
		else:
			break
	return i


func segment_of(index: int) -> Dictionary:
	var k := _segment_index[index] if index >= 0 and index < _segment_index.size() else -1
	return segments[k] if k >= 0 else {}


## Car standing on slice `index`, facing along the road (car front is -Z, as in the original).
func transform_at(index: int, lateral := 0.0) -> Transform3D:
	var rot := Basis.looking_at(forwards[index], ups[index])
	return Transform3D(rot, positions[index] + rights[index] * lateral + ups[index] * 0.4)


static func vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
