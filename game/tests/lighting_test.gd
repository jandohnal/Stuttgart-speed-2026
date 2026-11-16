extends Node
## Headless test of day / night lighting (D-019):
##   godot --headless --path game res://tests/lighting_test.tscn
## Checks the HDRI lookup (monaco1..5 share "monaco"), that a track without sky data keeps the
## procedural sky without failing, that the original's sky (D-045) is the default and an HDRI (with
## the original's horizon ring) the option, that a day HDRI gives a sun above the horizon pointed at the
## sky's brightest direction, and that at night the car has headlights with shadows and tail lights
## that brighten under the brake. Tracks or HDRIs missing locally skip their checks.

const Main := preload("res://scripts/main.gd")
const SkyLighting := preload("res://scripts/sky_lighting.gd")

var failures := 0


func _ready() -> void:
	print("LIGHTING TEST")
	_expect(SkyLighting.entry("monaco3") == "monaco" and SkyLighting.entry("farmland") == "farmland", "track entries")
	_expect(SkyLighting.hdri_path("no_such_track", "day") == "", "missing HDRI not found")
	# Fallback: no HDRI, the scene's procedural sky stays and nothing fails.
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = PhysicalSkyMaterial.new()
	env.sky = sky
	var sun := DirectionalLight3D.new()
	_expect(SkyLighting.apply(env, sun, "no_such_track", "night") == "procedural", "fallback reported")
	_expect(env.sky.sky_material is PhysicalSkyMaterial and sun.light_energy < 0.5, "fallback: procedural sky, moonlight")
	sun.free()
	# Panorama mapping (PanoramaSkyMaterial): u = 0 looks along -Z, u = 0.25 along +X, v = 0.5 is the horizon.
	_expect(SkyLighting.direction_of(0.25, 0.5).is_equal_approx(Vector3(1, 0, 0)), "panorama u 0.25 -> +X")
	_expect(SkyLighting.direction_of(0.0, 0.5).is_equal_approx(Vector3(0, 0, -1)), "panorama u 0 -> -Z")
	if not Main.track_available("farmland"):
		print("  skip scene checks: farmland missing in decomposed/")
		_finish()
		return
	var saved_sky: bool = GameSettings.options.get("original_sky", true)
	for run: Array in [["day", true], ["day", false], ["night", false]]:
		var time: String = run[0]
		GameSettings.options["original_sky"] = run[1]
		var main: Node3D = preload("res://scenes/main.tscn").instantiate()
		main.track_name = "farmland"
		main.time_of_day = time
		add_child(main)
		var world_env: Environment = (main.get_node("WorldEnvironment") as WorldEnvironment).environment
		var light: DirectionalLight3D = main.get_node("Sun")
		var has_hdri: bool = SkyLighting.hdri_path("farmland", time) != "" and not run[1]
		var has_sky := not OriginalSky.load_data("farmland").is_empty()
		var expected := "hdri" if has_hdri else ("original" if has_sky else "procedural")
		_expect(main.sky_source == expected, "%s, %s: sky %s (expected %s)" % [time, "original" if run[1] else "hdri option", main.sky_source, expected])
		if main.sky_source != "procedural":
			_expect(world_env.sky.sky_material is ShaderMaterial, "%s: sky shader with the horizon ring" % time)
		if main.sky_source == "original":
			_expect(main.original_sky != null, "%s: original sky follows the camera" % time)
		if time == "day" and has_hdri:
			var towards: Vector3 = light.global_basis.z
			var info := SkyLighting.sky_info(SkyLighting.hdri_path("farmland", "day"), Image.new())
			_expect(towards.y > 0.0 and towards.dot(info["direction"]) > 0.999, "day: sun above the horizon along the HDRI peak")
		var lights: Node = main.lights
		_expect(lights != null and lights.headlights.size() == 2 and lights.tail_lights.size() == 2,
			"%s: two headlights and two tail lights" % time)
		if lights == null:
			continue
		for head: SpotLight3D in lights.headlights:
			_expect(head.visible == (time == "night") and head.shadow_enabled, "%s: headlight %s" % [time, "on" if time == "night" else "off"])
		var car: Car = main.get_node("Car")
		var idle: float = lights.tail_lights[0].light_energy
		_expect((idle > 0.0) == (time == "night"), "%s: tail light %.2f" % [time, idle])
		car.brake = 1.0
		lights._process(0.0)
		_expect(lights.tail_lights[0].light_energy > idle and lights.tail_lights[0].visible, "%s: brake light" % time)
		main.queue_free()
	GameSettings.options["original_sky"] = saved_sky
	_finish()


func _finish() -> void:
	print("  %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", what)
