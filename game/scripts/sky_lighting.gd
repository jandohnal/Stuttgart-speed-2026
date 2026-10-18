extends RefCounted
## Day / night lighting per track from HDRI skies (D-019, IDEA-009). The sky is a
## PanoramaSkyMaterial on the HDRI and also gives the ambient and reflected light; the sun (or
## moon) is the scene's DirectionalLight3D, pointed along the brightest direction of the HDRI so
## shadows match the sun seen in the sky.
##
## Files: <hdri root>/<entry>_<day|night>.hdr, where the entry is the track name without trailing
## digits (monaco1..5 -> monaco), else the Poly Haven sky named for the entry in data/hdri.json
## (tools/fetch_hdri.py, <id>_<res>.hdr). Root: project setting stuttgart/hdri_root (default
## ../assets/hdri, ignored by git). No file: the scene's procedural sky stays and the log says so.
##
## Sun: the peak is found once per file on a 256 px wide copy, refined in the full image and
## cached in user://hdri_sun.cfg (keyed by file size and time). The sun disc of these HDRIs is
## clipped (about 20 against a sky of about 1), so its energy cannot come from the pixels: the sun
## light has a fixed energy and the sky is scaled so its irradiance on the ground is a set share
## of it. A peak much brighter than the sky (an unclipped sun, the moon) is clamped around the
## peak, or it would light the shadows through the ambient light a second time.

const DEFAULT_ROOT := "../assets/hdri"
const CATALOG := "../data/hdri.json"
const CACHE := "user://hdri_sun.cfg"
const CACHE_VERSION := 1
const ANALYSIS_WIDTH := 256
const PEAK_RADIUS_DEG := 3.0  ## window around the peak: refined there, clamped there, left out of the sky irradiance
const PEAK_CLAMP := 50.0  ## peak window clamped to this times the mean sky luminance

const DAY := {
	"sun_energy": 1.5,
	"sun_to_sky": 3.0,  ## sun light energy / sky irradiance on a horizontal surface
	"exposure": 1.3,
	"glow_intensity": 0.4,
	"glow_bloom": 0.03,
	"glow_hdr_threshold": 1.2,
	"fog_light_color": Color(0.72, 0.78, 0.86),
}
const NIGHT := {
	"sun_energy": 0.1,  ## moon
	"sun_color": Color(0.62, 0.72, 1.0),
	"sky_irradiance": 0.05,  ## absolute: the night sky is dimmed to this whatever the HDRI holds
	"exposure": 1.0,
	"glow_intensity": 0.9,
	"glow_bloom": 0.08,
	"glow_hdr_threshold": 0.9,
	"fog_light_color": Color(0.04, 0.05, 0.08),
	"procedural_sky_energy": 0.05,  ## fallback sky without an HDRI
}
## Moon from the HDRI only above this elevation (else city lights on the horizon would be the
## "moon"); otherwise this fixed direction (pitch, yaw in degrees).
const MOON_MIN_ELEVATION_DEG := 8.0
const MOON_FALLBACK := Vector2(-40.0, 30.0)


static func root() -> String:
	var dir: String = ProjectSettings.get_setting("stuttgart/hdri_root", DEFAULT_ROOT)
	if dir.is_relative_path():
		dir = ProjectSettings.globalize_path("res://").path_join(dir).simplify_path()
	return dir


## Track name -> entry shared by its variants (monaco3 -> monaco).
static func entry(track: String) -> String:
	var name := track
	while not name.is_empty() and name[-1].is_valid_int():
		name = name.left(-1)
	return name if not name.is_empty() else track


## HDRI file for the track and time ("day" / "night"), or "" when there is none.
static func hdri_path(track: String, time: String) -> String:
	var own := root().path_join("%s_%s.hdr" % [entry(track), time])
	if FileAccess.file_exists(own):
		return own
	var catalog_file := ProjectSettings.globalize_path("res://").path_join(CATALOG).simplify_path()
	if FileAccess.file_exists(catalog_file):
		var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_file))
		if catalog is Dictionary and catalog.get("tracks", {}).has(entry(track)):
			var id := str(catalog["tracks"][entry(track)].get(time, ""))
			for res: String in ["4k", "2k", "8k", "1k"]:
				var file := root().path_join("%s_%s.hdr" % [id, res])
				if not id.is_empty() and FileAccess.file_exists(file):
					return file
	return ""


## Sets up the environment and the sun for the track and time of day. Returns true when an HDRI
## sky was used, false for the procedural fallback.
static func apply(env: Environment, sun: DirectionalLight3D, track: String, time: String) -> bool:
	var night := time == "night"
	var p: Dictionary = NIGHT if night else DAY
	env.tonemap_exposure = p["exposure"]
	env.glow_intensity = p["glow_intensity"]
	env.glow_bloom = p["glow_bloom"]
	env.glow_hdr_threshold = p["glow_hdr_threshold"]
	env.fog_light_color = p["fog_light_color"]
	sun.light_energy = p["sun_energy"]
	if night:
		sun.light_color = NIGHT["sun_color"]
		sun.rotation_degrees = Vector3(MOON_FALLBACK.x, MOON_FALLBACK.y, 0.0)
	var file := hdri_path(track, time)
	var img := Image.load_from_file(file) if not file.is_empty() else null
	if img == null or img.is_empty():
		print("HDRI sky for %s (%s) not found in %s - using the procedural sky" % [track, time, root()])
		if night and env.sky != null and env.sky.sky_material is PhysicalSkyMaterial:
			(env.sky.sky_material as PhysicalSkyMaterial).energy_multiplier *= NIGHT["procedural_sky_energy"]
		return false
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBF)
	var info := sky_info(file, img)
	_clamp_peak(img, info)
	img.convert(Image.FORMAT_RGBH)  # half the memory, plenty for a sky
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = ImageTexture.create_from_image(img)
	var sky_irradiance: float = maxf(float(info["sky_irradiance"]), 1e-4)
	var target: float = NIGHT["sky_irradiance"] if night else float(DAY["sun_energy"]) / float(DAY["sun_to_sky"])
	sky_material.energy_multiplier = target / sky_irradiance
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	var direction: Vector3 = info["direction"]
	var elevation := rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
	if not night:
		sun.light_color = info["color"]
		_point_light(sun, direction)
	elif elevation >= MOON_MIN_ELEVATION_DEG:
		_point_light(sun, direction)
	print("HDRI sky %s: peak at elevation %.1f deg, sky x%.3f, light %.2f" % [file.get_file(), elevation, sky_material.energy_multiplier, sun.light_energy])
	return true


## The light shines from `direction` (unit vector towards the sun) into the scene.
static func _point_light(light: DirectionalLight3D, direction: Vector3) -> void:
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD
	light.basis = Basis.looking_at(-direction, up)


## Analysis of the HDRI, from the cache when the file has not changed.
static func sky_info(file: String, img: Image) -> Dictionary:
	var stamp := "%d:%d:%d" % [CACHE_VERSION, FileAccess.get_size(file), FileAccess.get_modified_time(file)]
	var cfg := ConfigFile.new()
	cfg.load(CACHE)
	var cached: Variant = cfg.get_value("hdri", file, {})
	if cached is Dictionary and cached.get("stamp", "") == stamp:
		return cached
	var info := analyse(img)
	info["stamp"] = stamp
	cfg.set_value("hdri", file, info)
	cfg.save(CACHE)
	return info


## Peak (brightest spot: sun or moon) and the irradiance of the rest of the sky on a horizontal
## surface. img is an equirectangular RGBF panorama.
static func analyse(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var small := img.duplicate() as Image
	while small.get_width() > ANALYSIS_WIDTH:
		# Halving with bilinear filtering averages 2 x 2 pixels, so a small sun is not missed.
		small.resize(small.get_width() / 2, maxi(small.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
	var sw := small.get_width()
	var sh := small.get_height()
	var best := -1.0
	var bx := 0
	var by := 0
	for y in sh:
		for x in sw:
			var l := small.get_pixel(x, y).get_luminance()
			if l > best:
				best = l
				bx = x
				by = y
	# Refine in the full image: centroid of the pixels near the window's maximum.
	var radius := ceili(PEAK_RADIUS_DEG / 360.0 * w)
	var cx := int((bx + 0.5) * w / sw)
	var cy := int((by + 0.5) * h / sh)
	var peak := 0.0
	for y in range(maxi(cy - radius, 0), mini(cy + radius + 1, h)):
		for x in range(cx - radius, cx + radius + 1):
			peak = maxf(peak, img.get_pixel(posmod(x, w), y).get_luminance())
	var sum := Vector2.ZERO
	var weight := 0.0
	var color := Color(0, 0, 0)
	for y in range(maxi(cy - radius, 0), mini(cy + radius + 1, h)):
		for x in range(cx - radius, cx + radius + 1):
			var c := img.get_pixel(posmod(x, w), y)
			if c.get_luminance() >= peak * 0.9:
				sum += Vector2(x, y)
				weight += 1.0
				color += c
	var px := sum.x / weight + 0.5
	var py := sum.y / weight + 0.5
	color = color / weight
	var brightest := maxf(color.r, maxf(color.g, color.b))
	color = Color(color.r / brightest, color.g / brightest, color.b / brightest) if brightest > 0.0 else Color.WHITE
	# Sky outside the peak window: irradiance on a horizontal surface and mean luminance.
	var direction := direction_of(px / w, py / h)
	var cos_radius := cos(deg_to_rad(PEAK_RADIUS_DEG * 1.5))
	var irradiance := 0.0
	var mean := 0.0
	var solid := 0.0
	for y in sh / 2:
		var v := (y + 0.5) / sh
		var lat := PI * (0.5 - v)
		var d_omega := (TAU / sw) * (PI / sh) * cos(lat)
		for x in sw:
			var u := (x + 0.5) / sw
			if direction_of(u, v).dot(direction) > cos_radius:
				continue
			var l := small.get_pixel(x, y).get_luminance()
			irradiance += l * sin(lat) * d_omega
			mean += l * d_omega
			solid += d_omega
	return {
		"direction": direction,
		"pixel": Vector2(px, py),
		"peak": peak,
		"color": color,
		"sky_irradiance": irradiance,
		"sky_mean": mean / maxf(solid, 1e-6),
	}


## Unit direction for equirectangular coordinates (0..1), as PanoramaSkyMaterial maps them:
## u = atan2(x, -z) / TAU (wrapped to 0..1), v = acos(y) / PI.
static func direction_of(u: float, v: float) -> Vector3:
	var theta := u * TAU
	var phi := v * PI
	return Vector3(sin(phi) * sin(theta), cos(phi), -sin(phi) * cos(theta))


## Limits the peak window to PEAK_CLAMP times the mean sky luminance (keeps the hue).
static func _clamp_peak(img: Image, info: Dictionary) -> void:
	var limit: float = PEAK_CLAMP * maxf(float(info["sky_mean"]), 1e-3)
	if float(info["peak"]) <= limit:
		return
	var w := img.get_width()
	var h := img.get_height()
	var radius := ceili(PEAK_RADIUS_DEG / 360.0 * w)
	var centre: Vector2 = info["pixel"]
	for y in range(maxi(int(centre.y) - radius, 0), mini(int(centre.y) + radius + 1, h)):
		for x in range(int(centre.x) - radius, int(centre.x) + radius + 1):
			var c := img.get_pixel(posmod(x, w), y)
			var l := c.get_luminance()
			if l > limit:
				img.set_pixel(posmod(x, w), y, c * (limit / l))
