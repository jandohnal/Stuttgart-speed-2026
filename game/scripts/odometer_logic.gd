extends RefCounted
## Drum positions of a mechanical odometer. The lowest drum turns continuously with the distance;
## each higher drum stands still and is carried one digit while every drum below it rolls from
## 9 to 0, so 0999 -> 1000 turns several drums at once.


## Position of each drum, lowest first, in digits 0..10 (10 shows 0 again). `value` is in units
## of the lowest drum.
static func drums(value: float, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	value = maxf(value, 0.0)
	out[0] = fposmod(value, 10.0)
	var place := 1.0
	for i in range(1, count):
		var below := fposmod(value, place * 10.0)  # what the lower drums show together
		var carry := clampf(below - (place * 10.0 - 1.0), 0.0, 1.0)
		out[i] = fposmod(floorf(value / (place * 10.0)), 10.0) + carry
		place *= 10.0
	return out
