extends Node
## Headless test of the menu's LOW QUALITY option (GameSettings.is_low_quality):
##   godot --headless --path game res://tests/low_quality_test.tscn [-- --track=<name>]
## Loads main.tscn twice with one opponent, at night so the car and track lights are there: without
## the option the sun casts shadows and glow is on; with it the scene is drawn like the original:
## the sun casts no shadows, every track material is unshaded (no detail noise or parallax), every
## car has a CarShadow blob and the player's car a CarBeam pool of light; glow, SSAO, the colour
## adjustment and the fog's aerial perspective are off, the sky's radiance map is Main.LOW_SKY_RADIANCE
## and incremental, the camera sees LOW_VIEW_DISTANCE with at least LOW_FOG_DENSITY fog, the
## headlights cast no shadows and only the player's car has them, the track has no lamp lights, the
## cars no light decals and no leaves fall from the crowns
## (FallingLeaves); the opponents drive on the rail (RailDrive, D-052), in full quality not.
## Then feeds GameSettings' adaptive 3D resolution made-up frame times: slow frames lower it step by step to LOW_MIN_RENDER_HEIGHT, fast ones raise it again.

const Materials := preload("res://scripts/materials.gd")

var failures := 0


func _ready() -> void:
	print("LOW QUALITY TEST")
	for low in [false, true]:
		GameSettings.options["low_quality"] = low
		var main: Node3D = preload("res://scenes/main.tscn").instantiate()
		main.time_of_day = "night"
		main.opponent_count = 1
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
			_expect(not sun.shadow_enabled, "no sun shadows")
			_expect(not env.glow_enabled and not env.ssao_enabled, "no glow and SSAO")
			_expect(is_equal_approx(camera.far, GameSettings.LOW_VIEW_DISTANCE), "view distance")
			_expect(env.fog_density >= GameSettings.LOW_FOG_DENSITY, "thicker fog")
			_expect(not head_shadows.has(true), "no headlight shadows")
			_expect(lamps == 0, "no lamp lights (%d)" % lamps)
			_expect(not env.adjustment_enabled and is_zero_approx(env.fog_aerial_perspective), "no adjustment and aerial perspective")
			_expect(env.sky.radiance_size == main.LOW_SKY_RADIANCE and env.sky.process_mode == Sky.PROCESS_MODE_INCREMENTAL,
				"small incremental sky radiance (%d, mode %d)" % [env.sky.radiance_size, env.sky.process_mode])
			_expect(main.light_decals == null, "no light decals")
			var foreign_heads := 0
			for o: Node in main.opponents:
				foreign_heads += o.find_children("*", "SpotLight3D", true, false).size()
			_expect(not main.lights.headlights.is_empty() and foreign_heads == 0, "headlights only on the player's car (opponents %d)" % foreign_heads)
			var track := main.find_child("road", true, false).get_parent() as Node3D
			var track_mats := Materials._materials(track)
			var lit := track_mats.filter(func(m: StandardMaterial3D) -> bool:
				return m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED)
			var heavy := track_mats.filter(func(m: StandardMaterial3D) -> bool:
				return m.detail_enabled or m.heightmap_enabled)
			var cars := main.find_children("*", "Car", true, false)
			var blobs := main.find_children("*", "CarShadow", true, false).size()
			var beams := main.find_children("*", "CarBeam", true, false).size()
			print("  track materials %d, lit %d, detail / parallax %d, cars %d, shadow blobs %d, beams %d" % [
				track_mats.size(), lit.size(), heavy.size(), cars.size(), blobs, beams])
			_expect(not track_mats.is_empty() and lit.is_empty(), "unshaded track")
			_expect(heavy.is_empty(), "no detail or parallax")
			_expect(not cars.is_empty() and blobs == cars.size(), "a shadow blob under every car")
			_expect(beams == 1, "the player's headlight pool")
			_expect(main.get_node_or_null("FallingLeaves") == null, "no falling leaves")
			var railed: Array = main.opponents.filter(func(o: Car) -> bool: return (o.get_node("AIDriver") as AIDriver).rail != null)
			_expect(not main.opponents.is_empty() and railed.size() == main.opponents.size(), "opponents on the rail (RailDrive, D-052)")
		else:
			_expect(sun.shadow_enabled and env.glow_enabled, "full quality keeps shadows and glow")
			_expect(main.find_children("*", "CarShadow", true, false).is_empty(), "no shadow blobs in full quality")
			_expect(main.opponents.all(func(o: Car) -> bool: return (o.get_node("AIDriver") as AIDriver).rail == null), "full quality opponents with the full physics")
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
