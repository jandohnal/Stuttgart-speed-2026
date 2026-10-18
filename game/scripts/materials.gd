extends RefCounted
## Material setup for the models loaded from decomposed/ (IDEA-009, D-013). The converters only
## write base colour textures; here they get PBR parameters by what they show.
##
## Car: materials are texture pages named "tpage<n> <texture file>" (tools/crp2gltf.py), so the
## kind comes from the page (exterior, glass, intglass, interior, extint) and, for the exterior
## atlas, from the part name (chrome exhaust and handles, lamps). Everything else on the exterior
## page is paint.
## The atlases' alpha is not transparency: on CarExtEnv pages it is the reflection strength (paint
## 204, trim 77, interior 50), so with the glTF alpha mask (cut at 0.5) trim, roof gutters, seats
## and the underbody were holes. Only decals keep the cut-out; paint, chrome, interior and the
## underbody are opaque.
## Reflections: the car is on its own visual layer (CAR_LAYER) and carries a reflection probe
## that captures the track and sky but not the car, and lights only the car. Glass uses
## premultiplied alpha so the pane's reflection is not dimmed by its low alpha.
## Paint colour (menu, D-020): the original tints the grey body texture; setup_car bakes the chosen
## colour into the paint material's copy of the exterior atlas on the body (alpha 204), the stripe
## zones (153, 166, 179, 230, tinted by the .clr stripe package in the original) and the sills and
## stripe borders (77), so the whole body is one colour. Decals get the same: some (the 935 stripes
## on the engine lid) are body texels; their printed parts keep the texture, as do chrome and lamps.
## Track: anisotropic filtering everywhere, procedural detail noise on road and terrain
## (world-space triplanar on UV2, no new assets).

const ANISO := BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

const PAINT := {"roughness": 0.3, "metallic": 0.1, "clearcoat": 1.0, "clearcoat_roughness": 0.1}
const CHROME := {"roughness": 0.1, "metallic": 1.0}
const LAMP := {"roughness": 0.1, "metallic": 0.3, "clearcoat": 1.0, "clearcoat_roughness": 0.05}
const INTERIOR := {"roughness": 0.85, "metallic": 0.0}
const GLASS := {"alpha": 0.3, "roughness": 0.05, "priority": 1}
const INNER_GLASS := {"alpha": 0.15, "roughness": 0.05, "priority": 0}
## Exterior-page parts that are chrome or lamps (prefix of the node name).
const CHROME_PARTS := ["Exhaust", "Handle", "SideMirror"]
const LAMP_PARTS := ["Light"]
## extint page (wheels, tyres, steering wheel, wipers): bright grey pixels are chrome hubs and
## spokes, dark ones rubber and plastic.
const RUBBER_ROUGHNESS := 0.9
## Kinds drawn opaque whatever the texture alpha says (see above).
const OPAQUE_KINDS := ["paint", "chrome", "interior", "underbody"]
const BRIGHT_ROUGHNESS := 0.12
## Atlas alpha (0-255) of the texels painted in the body colour: body 204, stripe zones, sills and
## stripe borders 77.
const PAINT_ALPHAS: Array[int] = [77, 153, 166, 179, 204, 230]
const PAINT_ALPHA_TOLERANCE := 2
## Visual layer of the car's meshes (bit 2), kept out of its own reflection probe.
const CAR_LAYER := 2
## Probe box (m) around the body centre, its height above the car origin and capture range.
const PROBE_SIZE := Vector3(8.0, 4.0, 8.0)
const PROBE_HEIGHT := 0.8
const PROBE_RANGE := 300.0


## paint: body colour from the original palette (FEData/Data/car_colors.json); alpha 0 keeps the
## texture as it is.
static func setup_car(model: Node3D, paint := Color(0, 0, 0, 0)) -> void:
	if model == null:
		return
	var cache := {}
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		(child as MeshInstance3D).layers = CAR_LAYER
		for surface in mesh.get_surface_count():
			var base := mesh.surface_get_material(surface) as StandardMaterial3D
			if base == null:
				continue
			var kind := _car_kind(base.resource_name, String(child.name))
			var key := "%s/%s" % [base.resource_name, kind]
			if not cache.has(key):
				cache[key] = _car_material(base, kind)
				if kind in ["paint", "decal"] and paint.a > 0.0:
					_paint(cache[key], paint)
			mesh.surface_set_material(surface, cache[key])


## Reflection probe riding with the car: the surroundings in paint, chrome and glass.
static func add_car_reflections(car: Node3D) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.name = "Reflections"
	probe.position = Vector3(0.0, PROBE_HEIGHT, 0.0)
	probe.size = PROBE_SIZE
	probe.blend_distance = 0.5
	probe.max_distance = PROBE_RANGE
	probe.cull_mask = ~CAR_LAYER & 0xFFFFF
	probe.reflection_mask = CAR_LAYER
	probe.update_mode = ReflectionProbe.UPDATE_ONCE  # re-captured over six frames when it moves
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	car.add_child(probe)
	return probe


static func _car_kind(material_name: String, part: String) -> String:
	var page := material_name.get_slice(" ", 1)
	var decal := part.begins_with("Decal")
	match page:
		"glass", "intglass", "shadow":
			return page
		"interior":
			return "interior_decal" if decal else "interior"
		"extint":
			return "underbody" if part.begins_with("Bottom") else "extint"
		"exterior":
			if decal:
				return "decal"
			for prefix: String in CHROME_PARTS:
				if part.begins_with(prefix):
					return "chrome"
			for prefix: String in LAMP_PARTS:
				if part.begins_with(prefix):
					return "lamp"
			return "paint"
	return ""


static func _car_material(base: StandardMaterial3D, kind: String) -> StandardMaterial3D:
	var m := base.duplicate() as StandardMaterial3D
	m.texture_filter = ANISO
	if kind in OPAQUE_KINDS:
		m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	match kind:
		"paint", "decal":
			_apply(m, PAINT)
		"chrome":
			_apply(m, CHROME)
		"lamp":
			_apply(m, LAMP)
		"interior", "interior_decal":
			_apply(m, INTERIOR)
			# Seen from inside only. Double-sided, the 935 headliner (in the roof plane, facing down)
			# showed through the roof from above, more so once roof damage pushes the roof into it.
			m.cull_mode = BaseMaterial3D.CULL_BACK
		"underbody":
			m.roughness = RUBBER_ROUGHNESS
			m.metallic = 0.0
		"glass", "intglass":
			var p: Dictionary = GLASS if kind == "glass" else INNER_GLASS
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA  # full-strength reflection on the pane
			m.albedo_texture = _glass_texture(m.albedo_texture, p["alpha"])
			m.roughness = p["roughness"]
			m.metallic = 0.0
			m.metallic_specular = 1.0
			m.render_priority = p["priority"]  # outer glass over the inner one, seen from outside
			m.cull_mode = BaseMaterial3D.CULL_BACK
		"extint":
			var mr := _metal_rough_texture(m.albedo_texture)
			if mr != null:
				m.metallic = 1.0
				m.metallic_texture = mr
				m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
				m.roughness = 1.0
				m.roughness_texture = mr
				m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			else:
				m.roughness = RUBBER_ROUGHNESS
	return m


## Tints the paint texels so that each zone (body, stripes, sills) averages to `paint`, keeping the
## texture's shading. A page without paint texels gets the colour as a plain albedo tint.
static func _paint(m: StandardMaterial3D, paint: Color) -> void:
	var img := _image(m.albedo_texture)
	if img == null:
		m.albedo_color = paint
		return
	var w := img.get_width()
	var zones := PackedInt32Array()  # texel -> zone index + 1, 0 = not paint
	zones.resize(w * img.get_height())
	var total := PackedFloat64Array()
	var count := PackedInt32Array()
	total.resize(PAINT_ALPHAS.size())
	count.resize(PAINT_ALPHAS.size())
	for y in img.get_height():
		for x in w:
			var c := img.get_pixel(x, y)
			var zone := paint_zone(c.a8)
			if zone >= 0:
				zones[y * w + x] = zone + 1
				total[zone] += c.get_luminance()
				count[zone] += 1
	if count[PAINT_ALPHAS.find(204)] == 0:
		m.albedo_color = paint
		return
	for y in img.get_height():
		for x in w:
			var zone := zones[y * w + x] - 1
			if zone < 0 or total[zone] <= 0.0:
				continue
			var c := img.get_pixel(x, y)
			var k := c.get_luminance() * count[zone] / total[zone]
			img.set_pixel(x, y, Color(minf(paint.r * k, 1.0), minf(paint.g * k, 1.0), minf(paint.b * k, 1.0), c.a))
	img.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(img)


## Index in PAINT_ALPHAS of the paint zone with this atlas alpha (0-255), -1 when not paint.
static func paint_zone(alpha: int) -> int:
	for i in PAINT_ALPHAS.size():
		if absi(alpha - PAINT_ALPHAS[i]) <= PAINT_ALPHA_TOLERANCE:
			return i
	return -1


static func _apply(m: StandardMaterial3D, p: Dictionary) -> void:
	m.roughness = p["roughness"]
	m.metallic = p["metallic"]
	if p.has("clearcoat"):
		m.clearcoat_enabled = true
		m.clearcoat = p["clearcoat"]
		m.clearcoat_roughness = p["clearcoat_roughness"]


## Window page: a pane framed by a rubber seal and trim. The pane (the even area around the
## centre) gets the given alpha, the frame stays opaque.
static func _glass_texture(tex: Texture2D, alpha: float) -> Texture2D:
	var img := _image(tex)
	if img == null:
		return tex
	var w := img.get_width()
	var h := img.get_height()
	var centre := img.get_pixel(w / 2, h / 2)
	var x0 := _pane_edge(img, centre, Vector2i(w / 2, h / 2), Vector2i(-1, 0))
	var x1 := _pane_edge(img, centre, Vector2i(w / 2, h / 2), Vector2i(1, 0))
	var y0 := _pane_edge(img, centre, Vector2i(w / 2, h / 2), Vector2i(0, -1))
	var y1 := _pane_edge(img, centre, Vector2i(w / 2, h / 2), Vector2i(0, 1))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := img.get_pixel(x, y)
			c.a = alpha
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Last pixel from start in direction dir that still looks like the pane (close to its centre colour).
static func _pane_edge(img: Image, centre: Color, start: Vector2i, dir: Vector2i) -> int:
	var p := start
	var size := Vector2i(img.get_width(), img.get_height())
	while true:
		var n := p + dir
		if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
			break
		var c := img.get_pixel(n.x, n.y)
		if absf(c.get_luminance() - centre.get_luminance()) > 0.2:
			break
		p = n
	return p.x if dir.x != 0 else p.y


## Roughness (R) and metallic (G) from the brightness of a texture: low-saturation bright pixels
## are chrome, the rest rubber.
static func _metal_rough_texture(tex: Texture2D) -> Texture2D:
	var img := _image(tex)
	if img == null:
		return null
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var metal := smoothstep(0.3, 0.55, c.get_luminance()) * (1.0 - smoothstep(0.1, 0.3, c.s))
			out.set_pixel(x, y, Color(lerpf(RUBBER_ROUGHNESS, BRIGHT_ROUGHNESS, metal), metal, 0.0))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


static func _image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


# --- track ---------------------------------------------------------------------------------

## Detail noise per track group: world metres per tile, noise frequency (per pixel of 256),
## darkest and brightest multiplier.
const DETAIL := {
	"road": {"tile": 1.5, "frequency": 0.12, "dark": 0.78, "bright": 1.0},
	"terrain": {"tile": 2.0, "frequency": 0.08, "dark": 0.72, "bright": 1.0},
}
## The detail darkens on average by about (dark + bright) / 2; the base colour makes up for it.
const DETAIL_COMPENSATION := 1.1


static func setup_track(track: Node3D) -> void:
	if track == null:
		return
	var seen := {}
	var details := {}
	for group: String in DETAIL:
		details[group] = _detail_texture(DETAIL[group])
	# Road first: a material used by the road and the terrain counts as road.
	for group: String in ["road", "terrain"]:
		var node := track.find_child(group, true, false)
		if node == null:
			continue
		for m in _materials(node):
			if seen.has(m):
				continue
			seen[m] = true
			_prepare(m)
			if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue  # fences, bushes: alpha cut-outs keep their look
			var p: Dictionary = DETAIL[group]
			m.roughness = 0.85 if group == "road" else 0.95
			m.detail_enabled = true
			m.detail_albedo = details[group]
			m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
			m.uv2_triplanar = true
			m.uv2_world_triplanar = true
			m.uv2_scale = Vector3.ONE / float(p["tile"])
			m.albedo_color = m.albedo_color * Color(DETAIL_COMPENSATION, DETAIL_COMPENSATION, DETAIL_COMPENSATION)
	for m in _materials(track):
		if not seen.has(m):
			seen[m] = true
			_prepare(m)


static func _materials(node: Node) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var m := mesh.surface_get_material(surface) as StandardMaterial3D
			if m != null and not out.has(m):
				out.append(m)
	return out


## Anisotropic filtering (needs mipmaps on the runtime-loaded textures).
static func _prepare(m: StandardMaterial3D) -> void:
	m.texture_filter = ANISO
	var tex := m.albedo_texture
	if tex == null:
		return
	var img := tex.get_image()
	if img != null and not img.has_mipmaps() and not img.is_compressed():
		img = img.duplicate() as Image
		img.generate_mipmaps()
		m.albedo_texture = ImageTexture.create_from_image(img)


static func _detail_texture(p: Dictionary) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = p["frequency"]
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(p["dark"], p["dark"], p["dark"]))
	ramp.set_color(1, Color(p["bright"], p["bright"], p["bright"]))
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	tex.generate_mipmaps = true
	return tex
