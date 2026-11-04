class_name OpponentProfiles
## The opponents' drivers (D-026): a name, a driving style (AIDriver settings) and a colour of their
## own. Every opponent drives the player's model, so the colour is the nearest one in that model's
## original palette: the same driver keeps the same colour (or the closest the model offers) in
## every car of every era. The player's colour and the ones already taken are skipped, so two cars
## on the grid never look alike. The grid takes the profiles in order (pole position first); with
## more opponents than profiles they repeat with a number.

## name, style (shown nowhere yet, for the docs and tests), color "#rrggbb", and the AIDriver
## settings: grip_use, brake_use (pace into and through corners), follow_time (s of gap kept
## behind a car), pass_speed_margin (m/s a car ahead must be slower than the driver could drive
## there for it to try a pass: lower = more eager).
const PROFILES: Array[Dictionary] = [
	{"name": "Klaus Wendt", "style": "aggressive: late braking, short gaps, passes early",
		"color": "#b01818", "grip_use": 0.84, "brake_use": 0.86, "follow_time": 0.3, "pass_speed_margin": 1.0},
	{"name": "Henri Duval", "style": "smooth: steady and precise",
		"color": "#c8c8c8", "grip_use": 0.81, "brake_use": 0.8, "follow_time": 0.5, "pass_speed_margin": 2.0},
	{"name": "Marco Bellini", "style": "careful: brakes early, keeps his distance",
		"color": "#1c3270", "grip_use": 0.77, "brake_use": 0.74, "follow_time": 0.8, "pass_speed_margin": 3.5},
]


## Profile of opponent `k` (0 = pole position), with a number after the name when they repeat.
static func profile(k: int) -> Dictionary:
	var p: Dictionary = PROFILES[k % PROFILES.size()].duplicate()
	if k >= PROFILES.size():
		p["name"] = "%s %d" % [p["name"], k / PROFILES.size() + 1]
	return p


## Sets the driving style on `driver`; before AIDriver.setup, which builds the speed profile.
static func apply(driver: AIDriver, p: Dictionary) -> void:
	for key: String in ["grip_use", "brake_use", "follow_time", "pass_speed_margin"]:
		driver.set(key, float(p[key]))


## The colour of `palette` nearest to `wanted` (RGB distance) that is not in `taken`; "" when the
## palette is empty, the nearest one at all when every colour is taken.
static func nearest_color(wanted: String, palette: Array, taken: Array) -> String:
	var target := Color(wanted)
	var best := ""
	var best_d := INF
	for pass_taken in [false, true]:
		for hex: String in palette:
			if not pass_taken and hex in taken:
				continue
			var c := Color(hex)
			var d := Vector3(c.r - target.r, c.g - target.g, c.b - target.b).length_squared()
			if d < best_d:
				best_d = d
				best = hex
		if not best.is_empty():
			return best
	return best
