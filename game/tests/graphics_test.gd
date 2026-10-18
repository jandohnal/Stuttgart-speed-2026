extends Node
## Graphics check (needs a window, not --headless): same views every run for before/after
## screenshots and FPS.
##   godot --path game res://tests/graphics_test.tscn -- <output folder> [--track=<name>] [--slice=<n>] [--time=day|night] [--windowed=1]
##     [--env|--sky|--sun|--vp|--head=<property>:<value>] (repeatable)
## --env, --sky, --sun, --vp and --head set a property of the Environment, the sky material, the sun, the viewport or both
## headlights (night) for trying
## settings without editing the scene, e.g. --env=sdfgi_enabled:true --vp=use_taa:true.
## --shadow_atlas=<px> and --shadow_filter=<0..5> override the project's directional shadow settings.
## The car settles on the slice, then: chase view (standing), chase view while driving (no cockpit
## view, the inside of the car is not checked in this phase). Each phase saves <phase>.png and
## prints the average and worst-frame FPS (vsync off). README uses farmland slice 1284.

const SETTLE := 2.0
const PHASE := 4.0  ## seconds measured per phase
const PHASES := ["chase", "drive"]

var main: Node3D
var car: Node3D
var camera: Camera3D
var out_dir := "user://"
var t := 0.0
var phase := -1
var frames := 0
var phase_time := 0.0
var worst := 0.0
var skip_frame := true
var results: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		out_dir = args[0]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	add_child(main)
	car = main.get_node("Car")
	camera = main.get_node("Camera")
	var env := (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var targets := {"env": [env], "sky": [env.sky.sky_material], "sun": [main.get_node("Sun")], "vp": [get_viewport()],
		"head": main.lights.headlights if main.lights != null else []}
	var atlas := _arg(args, "shadow_atlas")
	if atlas.is_valid_int():
		RenderingServer.directional_shadow_atlas_set_size(atlas.to_int(), true)
	var shadow_filter := _arg(args, "shadow_filter")
	if shadow_filter.is_valid_int():
		RenderingServer.directional_soft_shadow_filter_set_quality(shadow_filter.to_int() as RenderingServer.ShadowQuality)
	for arg in args:
		var key := arg.get_slice("=", 0).trim_prefix("--")
		if targets.has(key) and arg.contains(":"):
			var setting := arg.get_slice("=", 1)
			var prop := setting.get_slice(":", 0)
			var value: Variant = str_to_var(setting.substr(prop.length() + 1))
			for target: Object in targets[key]:
				target.set(prop, value)
				print("%s.%s = %s" % [key, prop, target.get(prop)])


func _process(delta: float) -> void:
	t += delta
	if phase < 0:
		if t >= SETTLE:
			_start(0)
		return
	if skip_frame:  # the previous phase's screenshot save stalls this frame
		skip_frame = false
		return
	frames += 1
	phase_time += delta
	worst = maxf(worst, delta)
	if phase_time >= PHASE:
		var name: String = PHASES[phase]
		var path := out_dir.path_join("%s.png" % name)
		get_viewport().get_texture().get_image().save_png(path)
		results.append("%s: %.1f FPS avg, %.1f FPS worst frame (%s)" % [name, frames / phase_time, 1.0 / worst, path])
		if phase + 1 < PHASES.size():
			_start(phase + 1)
		else:
			var vp := get_viewport()
			print("window %s, MSAA %d, TAA %s, scaling mode %d x %.2f" % [DisplayServer.window_get_size(), vp.msaa_3d, vp.use_taa, vp.scaling_3d_mode, vp.scaling_3d_scale])
			for line in results:
				print(line)
			get_tree().quit()


func _start(index: int) -> void:
	phase = index
	frames = 0
	phase_time = 0.0
	worst = 0.0
	skip_frame = true
	var name: String = PHASES[index]
	if name == "drive":
		Input.action_press("accelerate")


func _arg(args: PackedStringArray, name: String) -> String:
	for arg in args:
		if arg.begins_with("--%s=" % name):
			return arg.trim_prefix("--%s=" % name)
	return ""
