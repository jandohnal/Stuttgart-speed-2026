extends Node
## Headless test of the menu's LOW QUALITY option (GameSettings.is_low_quality):
##   godot --headless --path game res://tests/low_quality_test.tscn [-- --track=<name>]
## Loads main.tscn twice, at night so the car and track lights are there: without the option the
## sun casts shadows and glow is on; with it the sun casts cheap shadows (one split,
## LOW_SHADOW_DISTANCE), glow and SSAO are off, the camera sees LOW_VIEW_DISTANCE with at least LOW_FOG_DENSITY fog, the headlights cast no shadows
## and the track has at most LOW_LIGHT_POOL lamp lights; the track materials have no detail noise or
## parallax and only the ground (Materials.low_vertex_lit, no walls or trees) is lit per vertex.
## Then feeds GameSettings' adaptive 3D resolution made-up frame times: slow frames lower it step by step to LOW_MIN_RENDER_HEIGHT, fast ones raise it again.

const Materials := preload("res://scripts/materials.gd")

var failures := 0


func _ready() -> void:
	print("LOW QUALITY TEST")
	for low in [false, true]:
		GameSettings.options["low_quality"] = low
		var main: Node3D = preload("res://scenes/main.tscn").instantiate()
		main.time_of_day = "night"
		add_child(main)
		await get_tree().process_frame
		var sun := main.get_node("Sun") as DirectionalLight3D
		var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
		var camera := main.get_node("Camera") as Camera3D
		var head_shadows: Array = main.lights.headlights.map(func(l: Light3D) -> bool: return l.shadow_enabled) if main.lights != null else []
		var lamps := main.find_children("*", "OmniLight3D", true, false).filter(
			func(n: Node) -> bool: return main.track_lights != null and main.track_lights.is_ancestor_of(n)).size()
		print("  low=%s: sun shadow %s (%.0f m), glow %s, ssao %s, far %.0f m, fog %.4f, headlight shadows %s, lamp lights %d" % [
			low, sun.shadow_enabled, sun.directional_shadow_max_distance, env.glow_enabled, env.ssao_enabled, camera.far, env.fog_density, head_shadows, lamps])
		if low:
			_expect(sun.shadow_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL
				and is_equal_approx(sun.directional_shadow_max_distance, GameSettings.LOW_SHADOW_DISTANCE), "cheap sun shadows")
			_expect(not env.glow_enabled and not env.ssao_enabled, "no glow and SSAO")
			_expect(is_equal_approx(camera.far, GameSettings.LOW_VIEW_DISTANCE), "view distance")
			_expect(env.fog_density >= GameSettings.LOW_FOG_DENSITY, "thicker fog")
			_expect(not head_shadows.has(true), "no headlight shadows")
			_expect(lamps <= GameSettings.LOW_LIGHT_POOL, "lamp lights %d" % lamps)
			var track := main.find_child("road", true, false).get_parent() as Node3D
			var track_mats := Materials._materials(track)
			var ground := Materials.low_vertex_lit(track)
			var vertex_lit := track_mats.filter(func(m: StandardMaterial3D) -> bool:
				return m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX)
			var heavy := track_mats.filter(func(m: StandardMaterial3D) -> bool:
				return m.detail_enabled or m.heightmap_enabled)
			print("  track materials %d, per vertex %d (ground %d), detail / parallax %d" % [
				track_mats.size(), vertex_lit.size(), ground.size(), heavy.size()])
			_expect(not ground.is_empty() and vertex_lit.size() == ground.size() and ground.all(
				func(m: StandardMaterial3D) -> bool: return vertex_lit.has(m)), "only the ground lit per vertex")
			_expect(heavy.is_empty(), "no detail or parallax")
		else:
			_expect(sun.shadow_enabled and env.glow_enabled, "full quality keeps shadows and glow")
		main.queue_free()
		await get_tree().process_frame
	_test_adaptive()
	GameSettings.options["low_quality"] = false
	print("LOW QUALITY TEST %s" % ("OK" if failures == 0 else "FAILED (%d)" % failures))
	get_tree().quit(1 if failures > 0 else 0)


## 30 FPS for 20 s lowers the lines to the minimum, 60 FPS for 60 s brings them back to the top;
## a step up that drops below the limit again becomes the ceiling.
func _test_adaptive() -> void:
	GameSettings.options["low_quality"] = true
	GameSettings.adaptive_lines = 0
	_feed(1.0 / 30.0, 20.0)
	print("  adaptive: 30 FPS -> %d lines" % GameSettings.adaptive_lines)
	_expect(GameSettings.adaptive_lines == GameSettings.LOW_MIN_RENDER_HEIGHT, "lowered to the minimum")
	_feed(1.0 / 60.0, 120.0)
	print("  adaptive: 60 FPS -> %d lines" % GameSettings.adaptive_lines)
	_expect(GameSettings.adaptive_lines == GameSettings.LOW_RENDER_HEIGHT, "raised to the top")
	_feed(1.0 / 30.0, 2.0)
	var dropped := GameSettings.adaptive_lines
	_feed(1.0 / 60.0, 10.0)  # one step up ...
	_expect(GameSettings.adaptive_lines == GameSettings.LOW_RENDER_HEIGHT, "one step up")
	_feed(1.0 / 30.0, 2.0)  # ... that is too much
	_feed(1.0 / 60.0, 60.0)
	print("  adaptive: step up too much -> ceiling %d lines" % GameSettings.adaptive_lines)
	_expect(GameSettings.adaptive_lines == dropped, "keeps the ceiling")
	GameSettings.adaptive_lines = 0
	GameSettings._adapt_ceiling = 0


## Each phase starts a fresh measuring window, so it is not mixed with the previous one.
func _feed(frame: float, seconds: float) -> void:
	GameSettings._adapt_frames = 0
	GameSettings._adapt_time = 0.0
	for i in roundi(seconds / frame):
		GameSettings._adapt_render_height(frame)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL %s" % what)
