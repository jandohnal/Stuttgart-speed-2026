extends Node3D
## Model check of the original cars (needs a window, not --headless):
##   godot --path game res://tests/car_orbit_test.tscn -- <output folder> [--model=<name>] [--style=<n>] [--color=<#rrggbb>]
##     [--hide=<part prefix>,...] [--top_up=1]
## Puts every car model of decomposed/GameData/CarModel, once per style (CarStyle, D-022), standing
## on the skidpad start line and saves <model>_style<n>.png: a contact sheet of VIEWS (eight views
## around the car at eye height, one from above and one from low down). Looking for gaps, parts of
## two styles at once (overlapping or z-fighting) and missing polygons. Outside only: the cockpit
## view is not checked in this phase. Without --color the body keeps its untinted texture; --hide
## removes parts whose name starts with a prefix (to find which part shows), --top_up=1 shows
## convertibles with the top up.

const Materials := preload("res://scripts/materials.gd")
const TRACK := "skidpad"
const MODELS_DIR := "GameData/CarModel"
## Camera azimuth (degrees, 0 = in front of the car) and elevation (degrees) per tile.
const VIEWS: Array[Vector2] = [Vector2(0, 12), Vector2(45, 12), Vector2(90, 12), Vector2(135, 12),
	Vector2(180, 12), Vector2(225, 12), Vector2(270, 12), Vector2(315, 12), Vector2(30, 70), Vector2(60, 4)]
const COLUMNS := 5
const TILE := Vector2i(640, 400)
const SETTLE_FRAMES := 4  ## frames rendered before each capture (textures, shadows)
## A covered window stops redrawing (macOS) and the capture repeats the last frame: a view whose
## image equals the previous one is taken again, up to this many times.
const STALE_RETRIES := 50

var out_dir := "user://"
var jobs: Array[Dictionary] = []  ## {model, style}
var job := -1
var view := 0
var wait := 0
var car_root: Node3D
var camera: Camera3D
var fill: DirectionalLight3D
var ground := Transform3D.IDENTITY
var sheet: Image
var paint := Color(0, 0, 0, 0)
var center := Vector3.ZERO
var radius := 2.5
var hide: PackedStringArray = []
var top_up := false
var last_shot := PackedByteArray()
var tyre_gap := NAN  ## m, tyre bottom above (+) or in (-) the road, worst tyre of the car
var road_tris := PackedVector3Array()  ## world-space triangles of the track's road group
var retries := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = TILE
	get_window().always_on_top = true  # a covered window is not redrawn
	var color := _arg(args, "color")
	if not color.is_empty():
		paint = Color.from_string(color, paint)
	if not _arg(args, "hide").is_empty():
		hide = _arg(args, "hide").split(",")
	top_up = _arg(args, "top_up") == "1"
	_setup_world()
	var only_model := _arg(args, "model")
	var only_style := _arg(args, "style")
	var dir := DirAccess.open(OriginalAssets.path(MODELS_DIR))
	if dir == null:
		push_error("No car models in %s" % OriginalAssets.path(MODELS_DIR))
		get_tree().quit(1)
		return
	var models := dir.get_directories()
	models.sort()
	for model: String in models:
		var path := "%s/%s/%s.gltf" % [MODELS_DIR, model, model]
		if not OriginalAssets.exists(path) or (not only_model.is_empty() and model != only_model):
			continue
		var styles: Array = CarStyle.load_styles(path).get("styles", [])
		if styles.is_empty():
			jobs.append({"model": model, "path": path, "style": 0})
		for entry: Dictionary in styles:
			if only_style.is_empty() or int(entry["style"]) == only_style.to_int():
				jobs.append({"model": model, "path": path, "style": int(entry["style"]), "name": str(entry["name"])})
	print("CAR ORBIT TEST: %d models x styles -> %s" % [jobs.size(), out_dir])
	_next_job()


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	# Fill light from the camera so the side away from the sun still shows its seams.
	fill = DirectionalLight3D.new()
	fill.light_energy = 0.5
	add_child(fill)
	camera = Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.make_current()
	var folder := "GameData/Track/%s/" % TRACK
	var track := OriginalAssets.load_gltf(folder + TRACK + ".gltf")
	if track != null:
		Materials.setup_track(track)
		add_child(track)
		var simd := track.find_child("simd", true, false) as Node3D
		if simd != null:
			simd.visible = false
	if track != null:
		var road_group := track.find_child("road", true, false)
		if road_group != null:
			for child in road_group.find_children("*", "MeshInstance3D", true, false):
				var mi := child as MeshInstance3D
				var xf := _world_transform(mi)
				for v in mi.mesh.get_faces():
					road_tris.append(xf * v)
	var road: Variant = OriginalAssets.load_json(folder + TRACK + "_road.json")
	if road is Dictionary and not road["slices"].is_empty():
		var s: Dictionary = road["slices"][int(road.get("start", {}).get("slice", 0))]
		var up := _vec(s["up"])
		ground = Transform3D(Basis.looking_at(_vec(s["forward"]), up), _vec(s["position"]))


func _next_job() -> void:
	if car_root != null:
		car_root.free()
		car_root = null
	job += 1
	if job >= jobs.size():
		print("  done")
		get_tree().quit(0)
		return
	var j := jobs[job]
	var model := OriginalAssets.load_gltf(j["path"])
	if model == null:
		_next_job()
		return
	CarStyle.apply(model, j["path"], j["style"], top_up)
	for child in model.find_children("*", "MeshInstance3D", true, false):
		for prefix in hide:
			if String(child.name).begins_with(prefix):
				child.get_parent().remove_child(child)
				child.free()
				break
	Materials.setup_car(model, paint)
	car_root = Node3D.new()
	car_root.add_child(model)
	add_child(car_root)
	# Standing on the start line: lowest point (tyres) at the slice, then each tyre on the road
	# surface itself (the skidpad start is banked although its slice says level).
	var box := _bounds(model)
	tyre_gap = NAN
	car_root.transform = ground * Transform3D(Basis.IDENTITY, Vector3(0.0, -box.position.y, 0.0))
	_settle_on_road(model)
	center = car_root.transform * box.get_center()
	radius = box.size.length() * 0.5
	sheet = Image.create(TILE.x * COLUMNS, TILE.y * ceili(VIEWS.size() / float(COLUMNS)), false, Image.FORMAT_RGBA8)
	view = 0
	_place_camera()


func _place_camera() -> void:
	var v := VIEWS[view]
	var az := deg_to_rad(v.x)
	var el := deg_to_rad(v.y)
	var distance := radius / tan(deg_to_rad(camera.fov) * 0.5) * 0.8
	# Azimuth 0 looks at the car's front (-Z in model space).
	var dir := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	var basis := ground.basis
	var eye := center + basis * dir * distance
	camera.look_at_from_position(eye, center, basis.y if absf(v.y) < 80.0 else basis * Vector3(0, 0, -1))
	fill.global_transform = camera.global_transform
	wait = SETTLE_FRAMES


func _process(_delta: float) -> void:
	if job < 0 or job >= jobs.size():
		return
	if wait > 0:
		wait -= 1
		return
	var shot := get_viewport().get_texture().get_image()
	shot.convert(Image.FORMAT_RGBA8)
	if view > 0 and shot.get_data() == last_shot and retries < STALE_RETRIES:
		retries += 1
		wait = SETTLE_FRAMES
		return
	if retries >= STALE_RETRIES:
		push_warning("%s style %d view %d: no new frame, image repeats" % [jobs[job]["model"], jobs[job]["style"], view])
	retries = 0
	last_shot = shot.get_data()
	if shot.get_size() != TILE:
		shot.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, TILE), Vector2i(view % COLUMNS * TILE.x, view / COLUMNS * TILE.y))
	view += 1
	if view < VIEWS.size():
		_place_camera()
		return
	var j := jobs[job]
	var file := out_dir.path_join("%s_style%d.png" % [j["model"], j["style"]])
	sheet.save_png(file)
	print("  %s style %d %s, tyres %+.3f m from the road -> %s" % [j["model"], j["style"], j.get("name", ""), tyre_gap, file])
	_next_job()


## Moves car_root so the bottom of every tyre (WheelFront*, WheelRear* parts) lies on the road:
## the four contact points give the car's tilt and height.
func _settle_on_road(model: Node3D) -> void:
	var model_pts: Array[Vector3] = []
	var road_pts: Array[Vector3] = []
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var part := String(mi.name)
		if not (part.begins_with("WheelFront") or part.begins_with("WheelRear")):
			continue
		var box := _model_transform(mi, model) * mi.get_aabb()
		var bottom := box.get_center() - Vector3(0.0, box.size.y * 0.5, 0.0)
		var world := car_root.transform * bottom
		var y := _road_height(world)
		if is_nan(y):
			continue
		model_pts.append(bottom)
		road_pts.append(Vector3(world.x, y, world.z))
	if model_pts.size() < 4:
		return
	# Axle and side midpoints in model space and on the road, matched by a rotation and a shift.
	var mean := func(points: Array[Vector3], pick: Callable) -> Vector3:
		var sum := Vector3.ZERO
		var n := 0
		for i in points.size():
			if pick.call(model_pts[i]):
				sum += points[i]
				n += 1
		return sum / maxf(n, 1)
	var model_center := Vector3.ZERO
	var road_center := Vector3.ZERO
	for i in model_pts.size():
		model_center += model_pts[i]
		road_center += road_pts[i]
	model_center /= model_pts.size()
	road_center /= road_pts.size()
	var front := func(p: Vector3) -> bool: return p.z < model_center.z
	var rear := func(p: Vector3) -> bool: return p.z >= model_center.z
	var left := func(p: Vector3) -> bool: return p.x < model_center.x
	var right := func(p: Vector3) -> bool: return p.x >= model_center.x
	var model_basis := _frame(mean.call(model_pts, rear) - mean.call(model_pts, front),
		mean.call(model_pts, right) - mean.call(model_pts, left))
	var road_basis := _frame(mean.call(road_pts, rear) - mean.call(road_pts, front),
		mean.call(road_pts, right) - mean.call(road_pts, left))
	var rotation := road_basis * model_basis.inverse()
	car_root.transform = Transform3D(rotation, road_center - rotation * model_center)
	tyre_gap = 0.0
	for i in model_pts.size():
		var world := car_root.transform * model_pts[i]
		var gap := world.y - _road_height(world)
		if absf(gap) > absf(tyre_gap):
			tyre_gap = gap


## Orthonormal basis from a backward (+Z) and a rightward (+X) direction.
func _frame(back: Vector3, right: Vector3) -> Basis:
	var z := back.normalized()
	var y := z.cross(right).normalized()
	return Basis(y.cross(z), y, z)


## Height of the highest road triangle under p (within 2 m of it), NAN when there is none.
func _road_height(p: Vector3) -> float:
	var best := NAN
	var from := p + Vector3.UP * 2.0
	for i in range(0, road_tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, road_tris[i], road_tris[i + 1], road_tris[i + 2])
		if hit != null and (hit as Vector3).y > p.y - 2.0 and (is_nan(best) or (hit as Vector3).y > best):
			best = (hit as Vector3).y
	return best


func _world_transform(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Transform of node relative to model.
func _model_transform(node: Node3D, model: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != model:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Bounds of the model's meshes in model space.
func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != model:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _arg(args: PackedStringArray, key: String) -> String:
	for a in args:
		if a.begins_with("--%s=" % key):
			return a.get_slice("=", 1)
	return ""
