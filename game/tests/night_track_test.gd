extends Node
## Headless test of the original's night tracks (IDEA-015):
##   godot --headless --path game res://tests/night_track_test.tscn
## Main.is_night_track: Monaco 1-5 and Industrial, the rest day. With LOW QUALITY: monaco1 and
## industrial asked for day run at night anyway, with the original's sky at full energy (not dimmed
## like a day sky at night), fog from the horizon and the track undarkened (painted at night);
## NIGHT RACE on farmland darkens the track to LOW_TRACK_LIGHT and dims the sky. The player's car
## lights the track with the original's nght texture (CarBeam), and lamps with glass (TrackLights.LAMPS,
## Monaco and Industrial) get no lights of their own on the unshaded track. Missing tracks skip.

const Main := preload("res://scripts/main.gd")
const Materials := preload("res://scripts/materials.gd")
const NIGHT_TRACKS := ["monaco1", "monaco2", "monaco3", "monaco4", "monaco5", "industrial"]

var failures := 0


func _ready() -> void:
	print("NIGHT TRACK TEST")
	for track: String in Main.TRACKS:
		if Main.track_available(track):
			_expect(Main.is_night_track(track) == (track in NIGHT_TRACKS), "%s: %s" % [track, "night" if Main.is_night_track(track) else "day"])
	if OriginalAssets.exists(CarBeam.POOL):
		var pool := CarBeam.pool_texture()
		_expect(pool.get_width() == 128 and pool.get_image().get_pixel(64, 64).r > 0.9 and pool.get_image().get_pixel(0, 0).r < 0.1,
			"nght: 128 px, bright in the middle, dark in the corner")
	else:
		print("  skip nght: %s missing (tools/fsh2png.py)" % CarBeam.POOL)
	var saved_low: bool = GameSettings.options.get("low_quality", false)
	var saved_sky: bool = GameSettings.options.get("original_sky", true)
	GameSettings.options["low_quality"] = true
	GameSettings.options["original_sky"] = true
	for run: Array in [["monaco1", "day"], ["industrial", "day"], ["farmland", "night"]]:
		var track: String = run[0]
		if not Main.track_available(track):
			print("  skip %s: missing in decomposed/" % track)
			continue
		var main: Node3D = preload("res://scenes/main.tscn").instantiate()
		main.track_name = track
		main.time_of_day = run[1]
		add_child(main)
		await get_tree().process_frame
		var own_night: bool = track in NIGHT_TRACKS
		_expect(main.time_of_day == "night" and main.night_track == own_night, "%s asked %s: runs %s" % [track, run[1], main.time_of_day])
		var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
		_expect(main.find_children("*", "CarBeam", true, false).size() == 1, "%s: the player's headlight light" % track)
		if own_night and main.track_lights != null:
			_expect(main.track_lights.lamp_lights.is_empty(), "%s: no lamp lights on the unshaded track" % track)
		if main.sky_source == "original":
			var energy: float = (env.sky.sky_material as ShaderMaterial).get_shader_parameter("energy")
			var expected := OriginalSky.DAY_ENERGY * (1.0 if own_night else OriginalSky.NIGHT_SCALE)
			_expect(is_equal_approx(energy, expected), "%s: sky energy %.2f (%.2f)" % [track, energy, expected])
			if own_night:
				var fog := OriginalSky.horizon_color(OriginalSky.load_data(track))
				_expect(env.fog_light_color.is_equal_approx(fog.srgb_to_linear()), "%s: fog from the horizon %s" % [track, env.fog_light_color])
		# Glowing lenses and windows (emission) and flare sprites (additive) of TrackLights have their own colour.
		var road := main.find_child("road", true, false) as Node3D
		if road != null:
			var light := 1.0 if own_night else float(Materials.LOW_TRACK_LIGHT["night"])
			var wrong := Materials._materials(road.get_parent()).filter(func(m: StandardMaterial3D) -> bool:
				return not m.emission_enabled and m.blend_mode == BaseMaterial3D.BLEND_MODE_MIX and not is_equal_approx(maxf(m.albedo_color.r, maxf(m.albedo_color.g, m.albedo_color.b)), light))
			_expect(wrong.is_empty(), "%s: track brightness %.1f (%d materials differ: %s)" % [track, light, wrong.size(),
				wrong.map(func(m: StandardMaterial3D) -> String: return "%s %s" % [m.resource_name, m.albedo_color])])
		main.queue_free()
		await get_tree().process_frame
	GameSettings.options["low_quality"] = saved_low
	GameSettings.options["original_sky"] = saved_sky
	print("  %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1
