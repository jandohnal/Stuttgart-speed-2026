class_name OriginalSky
extends Node
## The original's sky (D-045, docs/formats/sky.md): <track>_sky.json from tools/sky.py drawn by
## shaders/original_sky.gdshader. The dome takes the sky level of <Track>.txt (HIGH, MEDIUM with
## low quality), the horizon ring the horz panorama of <Track>.fsh with the hzcl tint. With the HDRI
## option the same shader draws the HDRI and the ring in front of it (horizon_only).
## Weather region A blends into B along the track (region_blend keyed by road slice); this node
## follows the camera's slice and updates the blend.
## Day / night: the original has one time per track (Monaco 1-5 and Industrial night, the rest day;
## Main.is_night_track). Night tracks always run at night; NIGHT RACE on a day track scales the sky by
## NIGHT_SCALE (DAY_SCALE would brighten a night sky by day; user's choice, 15. 11. 2026).

const SHADER := preload("res://shaders/original_sky.gdshader")
const DAY_ENERGY := 1.0
const NIGHT_SCALE := 0.06  ## a day sky at night
const DAY_SCALE := 3.0  ## a night sky (Monaco) by day
const TICKS := 30.0  ## Porsche.exe moves the sky layers 30 times a second
const WIND_FACTOR := 0.00025  ## UV per tick per unit of wind speed (FUN_0045f1b0)
const SUN_SIZE_DEG := 3.5
const MODES := {"multinormal": 0, "multiadditive": 1, "multiattenuate": 2, "multimodulate": 3, "basic": 0}
const SEARCH := 8  ## slices around the last one searched for the camera
const LOST_DISTANCE := 60.0

var material: ShaderMaterial
var blend_keys: Array = []  ## [[slice, value], ...]
var road: Road
var camera: Camera3D
var _levels: Array = []  ## the level's regions A and B (for the scales between them)
var _slice := -1
var _blend := -1.0


## The sky's data for the track (or null) and its textures by name.
static func load_data(track: String) -> Dictionary:
	var file := "GameData/Track/%s/%s_sky.json" % [track, track]
	if not OriginalAssets.exists(file):
		return {}
	var data: Variant = OriginalAssets.load_json(file)
	return data if data is Dictionary else {}


## Sky material for the track: the original's dome and ring, or (horizon_only) the ring alone over
## `panorama`. {} data: null.
static func make_material(data: Dictionary, low: bool, panorama: Texture2D = null, panorama_energy := 1.0) -> ShaderMaterial:
	if data.is_empty():
		return null
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var textures := {}
	for key: String in data.get("textures", {}):
		textures[key] = str(data["folder"]).path_join(str(data["textures"][key]))
	var horizon: Variant = data.get("horizon")
	if horizon is Dictionary and textures.has("horz") and textures.has("hzcl"):
		m.set_shader_parameter("horizon_enabled", true)
		m.set_shader_parameter("horizon", _texture(textures["horz"], false))
		m.set_shader_parameter("horizon_colors", _texture(textures["hzcl"], false))
		m.set_shader_parameter("horizon_start", float(horizon["start_turns"]))
		m.set_shader_parameter("horizon_offset", float(horizon["colour_offset"]))
		m.set_shader_parameter("horizon_grid", Vector2(horizon["grid"][0], maxf(horizon["grid"][1], 1)))
		m.set_shader_parameter("horizon_base", float(horizon["base"]))
		m.set_shader_parameter("horizon_top", float(horizon["base"]) + float(horizon["height"]))
		m.set_shader_parameter("horizon_radius", float(horizon["radius"]))
		var tiles := PackedVector4Array()
		for t: Dictionary in horizon["tiles"]:
			tiles.append(Vector4(float(t["tile"]), 1.0 if t["flip"] else 0.0, 0.0, 0.0))
		m.set_shader_parameter("horizon_tiles", tiles)
		m.set_shader_parameter("below_color", _average(textures["hzcl"], 1))
	if panorama != null:
		m.set_shader_parameter("use_panorama", true)
		m.set_shader_parameter("panorama", panorama)
		m.set_shader_parameter("panorama_energy", panorama_energy)
		return m
	var dome: Variant = data.get("dome")
	if dome is Dictionary:
		m.set_shader_parameter("dome_rotation", float(dome["rotation_turns"]))
		m.set_shader_parameter("dome_size", float(dome["size"]))
		m.set_shader_parameter("dome_curvature", float(dome["curvature"]))
		m.set_shader_parameter("dome_height", float(dome["height"]))
		m.set_shader_parameter("dome_cells", float(dome["cells"]))
	var level := pick_level(data, low)
	if level.is_empty():
		return m
	m.set_shader_parameter("blend_mode", MODES.get(str(level["type"]), 0))
	var regions: Array = level["regions"]
	var a: Dictionary = regions[0]
	var b: Dictionary = regions[1] if regions.size() > 1 else a
	var clouds: Array = level["clouds"]
	var count := 0
	for k in 3:
		var layer: Dictionary = a["layers"][k] if k < a["layers"].size() else {}
		var cloud: Variant = clouds[k] if k < clouds.size() else null
		if layer.is_empty() or (layer.get("map") == null and cloud == null):
			break
		if level["type"] == "basic":
			cloud = layer.get("texture")
		var map_b: Dictionary = b["layers"][k] if k < b["layers"].size() else layer
		m.set_shader_parameter("map_a%d" % k, _map(textures, layer.get("map")))
		m.set_shader_parameter("map_b%d" % k, _map(textures, map_b.get("map")))
		m.set_shader_parameter("cloud%d" % k, _map(textures, cloud))
		count += 1
	m.set_shader_parameter("layer_count", maxi(count, 1))
	m.set_shader_parameter("move_ratio", float(a["move_ratio"]))
	m.set_shader_parameter("warp", Vector2(a["warp"][0], a["warp"][1]))
	set_layers(m, level, 0.0)
	if textures.has("suna"):
		m.set_shader_parameter("sun_enabled", true)
		m.set_shader_parameter("sun", _texture(textures["suna"], false))
		m.set_shader_parameter("sun_size", sin(deg_to_rad(SUN_SIZE_DEG)))
	return m


## The level for the computer capability (HIGH, MEDIUM with low quality), else the first one.
static func pick_level(data: Dictionary, low: bool) -> Dictionary:
	var levels: Array = data.get("levels", [])
	var wanted := "MEDIUM" if low else "HIGH"
	for level: Dictionary in levels:
		if str(level["capability"]) == wanted and not level["regions"].is_empty():
			return level
	return levels[0] if not levels.is_empty() else {}


## Layer scales and wind blended between regions A and B (region_blend 0..1).
static func set_layers(m: ShaderMaterial, level: Dictionary, blend: float) -> void:
	var regions: Array = level["regions"]
	var a: Dictionary = regions[0]
	var b: Dictionary = regions[1] if regions.size() > 1 else a
	for k in mini(3, a["layers"].size()):
		var la: Dictionary = a["layers"][k]
		var lb: Dictionary = b["layers"][k] if k < b["layers"].size() else la
		var inv := Vector2(_inverse(la["scale"][0]), _inverse(la["scale"][1])).lerp(
			Vector2(_inverse(lb["scale"][0]), _inverse(lb["scale"][1])), blend)
		var wind := _wind(la["wind"]).lerp(_wind(lb["wind"]), blend)
		m.set_shader_parameter("layer%d" % k, Vector4(inv.x, inv.y, wind.x, wind.y))
	m.set_shader_parameter("region_blend", blend)


## Mean colour of the horizon (horz weighted by alpha, tinted by hzcl): the fog colour that joins
## the distant track to the ring.
static func horizon_color(data: Dictionary) -> Color:
	var textures: Dictionary = data.get("textures", {})
	if not textures.has("horz") or not textures.has("hzcl"):
		return Color(0, 0, 0, 0)
	var folder := str(data["folder"])
	var land := _average(folder.path_join(str(textures["horz"])), -2)
	var tint := _average(folder.path_join(str(textures["hzcl"])), -1)
	return Color(land.r * tint.r, land.g * tint.g, land.b * tint.b)


static func _inverse(scale: Variant) -> float:
	return 1.0 / float(scale) if absf(float(scale)) > 1e-4 else 0.0


## UV per second from the .txt wind (speed, direction in degrees), as FUN_0045f1b0.
static func _wind(w: Array) -> Vector2:
	var angle := -float(w[1]) / 360.0 * TAU
	return Vector2(sin(angle), cos(angle)) * float(w[0]) * WIND_FACTOR * TICKS


static func _map(textures: Dictionary, name: Variant) -> Texture2D:
	if name == null or str(name) == "flat" or not textures.has(str(name)):
		return _white()
	return _texture(textures[str(name)], true)


static func _texture(relative: String, mipmaps: bool) -> Texture2D:
	var img := Image.load_from_file(OriginalAssets.path(relative))
	if img == null or img.is_empty():
		return _white()
	img.convert(Image.FORMAT_RGBA8)
	if mipmaps:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _white() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


## Mean colour of an image: of row `row`, of all pixels (-1) or weighted by alpha (-2).
static func _average(relative: String, row: int) -> Color:
	var img := Image.load_from_file(OriginalAssets.path(relative))
	if img == null or img.is_empty():
		return Color(0.5, 0.5, 0.5)
	img.convert(Image.FORMAT_RGBA8)
	var sum := Color(0, 0, 0, 0)
	var weight := 0.0
	for y in img.get_height():
		if row >= 0 and y != row:
			continue
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var w := c.a if row == -2 else 1.0
			sum += Color(c.r * w, c.g * w, c.b * w, 0.0)
			weight += w
	return Color(sum.r / weight, sum.g / weight, sum.b / weight) if weight > 0.0 else Color(0.5, 0.5, 0.5)


## Follows the camera along the road and blends the weather regions (region_blend keys).
func setup(data: Dictionary, track_road: Road, view: Camera3D, low: bool) -> void:
	blend_keys = data.get("region_blend", [])
	road = track_road
	camera = view
	var level := pick_level(data, low)
	_levels = [level] if not level.is_empty() else []
	set_process(material != null and not _levels.is_empty() and road != null and road.size() > 0
		and blend_keys.size() > 1 and camera != null)


func _process(_delta: float) -> void:
	var pos := camera.global_position
	var best := -1
	var best_dist := INF
	if _slice >= 0:
		for i in range(maxi(_slice - SEARCH, 0), mini(_slice + SEARCH + 1, road.size())):
			var d := road.positions[i].distance_squared_to(pos)
			if d < best_dist:
				best_dist = d
				best = i
	if best < 0 or best_dist > LOST_DISTANCE * LOST_DISTANCE:
		best = road.nearest(pos)
	_slice = best
	var blend := blend_at(best)
	if absf(blend - _blend) > 0.005:
		_blend = blend
		set_layers(material, _levels[0], blend)


## Region blend at `slice`: linear between the keys around it (FUN_0045a2c0).
func blend_at(slice: int) -> float:
	var prev: Array = blend_keys[0]
	for key: Array in blend_keys:
		if int(key[0]) >= slice:
			if int(key[0]) == int(prev[0]):
				return float(key[1])
			var t := float(slice - int(prev[0])) / float(int(key[0]) - int(prev[0]))
			return lerpf(float(prev[1]), float(key[1]), clampf(t, 0.0, 1.0))
		prev = key
	return float(prev[1])
