extends Node3D
## Light flares of an original track (D-021): street and tunnel lamps, lit buildings, orange
## warning lights on sawhorses and pylons, arrow flashers. Where they are comes from the track
## articles' ef entries (<track>_lights.json from tools/track2gltf.py), what they look like from
## GameData/Render/flare.dat (GameData/Render/flares.json from tools/flare.py, docs/formats/flare.md).
##
## Every flare is two additive glow sprites (core and halo, texture from GameData/Render/common),
## world flares batched in one MultiMesh per flare ID and layer, flares on placed objects as
## sprites on the object's body so they fall with a knocked sawhorse. Blinking flares share one
## clock: lit while (tick - phase) mod (on + off) < on. At night a small pool of OmniLight3D (no
## shadows) moves to the flares nearest the camera, so the lamps also light the road around them.
## Original textures with lit windows and neon glow at night through an emission mask of their
## brightest pixels.
## Lamps with modelled glass (LAMPS, Monaco) look like the car's tail lights at night: the glass
## glows (emission strong enough for the environment glow to draw the halo), the flare is one small
## sprite that fades out near the camera, and each lamp has its own warm OmniLight3D that fades
## with distance instead of a light from the pool.

const FLARES := "GameData/Render/flares.json"
const FLARE_TEXTURES := "GameData/Render/common/"
const TICKS_PER_SECOND := 60.0  ## blink ticks; sawhorse lights then blink once a second
const SIZE_SCALE := 0.1  ## m per flare.dat size unit (sawhorse glow 0.6 / 0.9 m, street lamp 1.4 / 5.9 m)
const NIGHT_ENERGY := 3.0  ## sprite colour multiplier; above the glow threshold so flares bloom
const DAY_ENERGY := 1.0
const LIGHT_POOL := 12  ## OmniLight3D at night
## Pool lights (warning lights, flashers, tunnel lamps) are small lamps: at 14 m and energy 1.6 a
## sawhorse flooded the whole street orange.
const LIGHT_RANGE := 7.0  ## m
const LIGHT_ENERGY := 0.5
const LIGHT_ATTENUATION := 0.5
const LIGHT_PICK_INTERVAL := 0.25  ## s between re-picking the nearest flares
## Flare IDs per HDRI entry whose lamps have their own glass in the track model (glowing via
## LIT_TEXTURES): at night they get the lamp treatment described above.
const LAMPS := {
	"monaco": ["lamp", "lmpy", "strg", "stry"],
}
const LAMP_WARM := Color(1.0, 0.7, 0.42)  ## about 2700 K, mixed into the flare colour
const LAMP_WARMTH := 0.6
const LAMP_LIGHT_ENERGY := 1.4
## Distance falloff exponent; flatter than inverse square, which blew out the lamp's own bracket
## and the wall right next to the light.
const LAMP_LIGHT_ATTENUATION := 0.5
const LAMP_LIGHT_RANGE := 16.0  ## m
const LAMP_FADE_BEGIN := 45.0  ## m from the camera where a lamp's light starts to fade out
const LAMP_FADE_LENGTH := 15.0
## Warning lights whose lens is part of the object's texture (LENS_TEXTURES): the lens glows with
## the flare's blink and the flare sprite shrinks to this fraction.
const LENS_TEXTURES := {
	"monaco": {"abda": {"flare": "wrna", "energy": 2.5}},  ## amber lamp on sawhorses
}
const LENS_SPRITE_SCALE := 0.4
## Amber of the lens glow, its sprite and its light. Kept below overexposure: brighter orange
## clipped to white in the tonemapper, and the flare's own red-orange lit the paving red.
const LENS_COLOR := Color(1.0, 0.5, 0.08)
const LENS_SPRITE_ENERGY := 1.4
const LAMP_SPRITE_FADE := Vector2(8.0, 30.0)  ## m: sprite invisible nearer, full from the far end
## Texture names (track .fsh) per HDRI entry whose bright pixels glow at night -> emission energy:
## lit windows, neon tubes. Names are per track, the same name elsewhere is another picture. Not
## the monaco1/2 tunnel walls (ttm1-4): the tunnel ceiling is mapped onto their lamp strip, so even
## a faint glow lit the whole tunnel white; their painted lamps show well enough unlit.
## Lamp glass (inlp lamp posts, trl4 lanterns and hanging lamps, lmp1 wall lanterns, lyte bulbs of
## BLD_LIGHT) glows strongly; its mask starts lower so the whole pane lights up.
const LIT_TEXTURES := {
	"monaco": {"win1": 0.6, "win4": 0.6, "win5": 0.6, "neo1": 0.6, "neo2": 0.6, "neo5": 0.6, "neo6": 0.6,
		"inlp": 4.0, "trl4": 4.0, "lmp1": 4.0, "lyte": 3.0},
}
const LIT_THRESHOLD := Vector2(0.9, 1.0)  ## luminance ramp of the emission mask
## Lit windows (texture names starting with "win"): the whole texture glows through a contrast
## curve and a warm tint, so the rooms behind the glass stay visible and only the brightest spots
## bloom. The bright-pixel mask let almost the whole pale pane through as flat white.
const WINDOW_TINT := Color(1.0, 0.72, 0.42)
const WINDOW_GAMMA := 2.6
const WINDOW_ENERGY := 2.0
const GLASS_TINT := Color(1.0, 0.86, 0.66)  ## warm lamp glass (the textures are white)
const GLASS_THRESHOLD := Vector2(0.55, 0.85)  ## the same for textures with energy >= 1 (lamp glass)

var night := false
var flare_count := 0  ## sprites' flares placed (world + on objects)
var lights: Array[OmniLight3D] = []  ## the pool
var lamp_lights: Array[OmniLight3D] = []  ## one per lamp (LAMPS)
var _lamp_ids: Array = []
var _lens_ids: Array = []  ## flare IDs with a glowing lens (LENS_TEXTURES)
## {id, material, energy} lens materials blinking with their flare.
var _lens_materials: Array[Dictionary] = []
## {id, layer, node (MultiMeshInstance3D / MeshInstance3D)} for blinking.
var _blinkers: Array[Dictionary] = []
## Candidates for the light pool: {id, position (world flares) or node (on objects), color}.
var _sources: Array[Dictionary] = []
var _flares: Dictionary = {}
var _materials: Dictionary = {}
var _time := 0.0
var _pick_wait := 0.0


## Builds the flares of a loaded track (after TrackProps.build); lights = parsed _lights.json.
func setup(track: Node3D, data: Dictionary, track_entry: String, is_night: bool) -> void:
	name = "TrackLights"
	night = is_night
	var defs: Variant = OriginalAssets.load_json(FLARES)
	if not defs is Dictionary:
		return
	_flares = defs["flares"]
	if night:
		_lamp_ids = LAMPS.get(track_entry, [])
		for lens: Dictionary in LENS_TEXTURES.get(track_entry, {}).values():
			_lens_ids.append(lens["flare"])
	var by_id := {}
	for f: Dictionary in data.get("world", []):
		if _flares.has(f["id"]):
			by_id.get_or_add(f["id"], []).append(f)
	for id: String in by_id:
		_add_world(id, by_id[id])
	var props := track.find_child("props", true, false)
	if props != null:
		_add_props(props, data.get("props", {}))
	if night:
		for i in LIGHT_POOL:
			var light := OmniLight3D.new()
			light.omni_range = LIGHT_RANGE
			light.omni_attenuation = LIGHT_ATTENUATION
			light.light_energy = LIGHT_ENERGY
			light.shadow_enabled = false
			light.visible = false
			add_child(light)
			lights.append(light)
		glow_textures(track, track_entry)
		_glow_lenses(track, track_entry)
	_update_blink()


func _process(delta: float) -> void:
	_time += delta
	_update_blink()
	_pick_wait -= delta
	if _pick_wait <= 0.0 and not lights.is_empty():
		_pick_wait = LIGHT_PICK_INTERVAL
		_pick_lights()


## True when flare ID is lit at time t (s).
func is_lit(id: String, t: float) -> bool:
	var blink: Variant = _flares.get(id, {}).get("blink")
	if not blink is Dictionary:
		return true
	var on := int(blink["on"])
	var period := on + int(blink["off"])
	var tick := int(t * TICKS_PER_SECOND) - int(blink["phase"])
	return posmod(tick, period) < on


func _add_world(id: String, flares: Array) -> void:
	var lamp := id in _lamp_ids
	for layer in 2:
		if lamp and layer != _small_layer(id):
			continue
		var mesh := _quad(id, layer, lamp)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = flares.size()
		for i in flares.size():
			mm.set_instance_transform(i, Transform3D(Basis(), _vec(flares[i]["position"])))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [id, layer]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_track_blink(id, mmi)
	for f: Dictionary in flares:
		if lamp:
			_add_lamp_light(id, _vec(f["position"]))
		else:
			_sources.append({"id": id, "position": _vec(f["position"]), "color": _light_color(id)})
	flare_count += flares.size()


func _add_lamp_light(id: String, pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.name = "lamp_%s_%d" % [id, lamp_lights.size()]
	light.position = pos
	light.light_color = _light_color(id).lerp(LAMP_WARM, LAMP_WARMTH)
	light.light_energy = LAMP_LIGHT_ENERGY
	light.omni_range = LAMP_LIGHT_RANGE
	light.omni_attenuation = LAMP_LIGHT_ATTENUATION
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = LAMP_FADE_BEGIN
	light.distance_fade_length = LAMP_FADE_LENGTH
	add_child(light)
	lamp_lights.append(light)


## The sprite layer kept for a lamp: the smaller of the two that have a texture.
func _small_layer(id: String) -> int:
	var layers: Array = _flares[id]["layers"]
	if layers[1]["texture"] == null or float(layers[1]["size"]) <= 0.0:
		return 0
	if layers[0]["texture"] == null or float(layers[0]["size"]) <= 0.0:
		return 1
	return 0 if float(layers[0]["size"]) <= float(layers[1]["size"]) else 1


## Flares local to placed objects: on the body TrackProps made (its child "mesh" holds the
## scale), or on the mesh itself for visual-only objects.
func _add_props(props: Node, by_node: Dictionary) -> void:
	var by_index := {}
	for key: String in by_node:
		by_index[key.substr(0, 3).to_int()] = by_node[key]
	for child in props.get_children():
		var prefix := str(child.name).substr(0, 3)
		if not prefix.is_valid_int() or not by_index.has(prefix.to_int()):
			continue
		var host := child as Node3D
		var scale := Vector3.ONE
		var mesh := host.get_node_or_null("mesh") as Node3D
		if mesh != null:
			scale = mesh.transform.basis.get_scale()
		var flares: Array = by_index[prefix.to_int()]
		for k in flares.size():
			var id: String = flares[k]["id"]
			if not _flares.has(id):
				continue
			var anchor := Node3D.new()
			anchor.name = "flare_%s_%d" % [id, k]
			anchor.position = _vec(flares[k]["position"]) * scale
			host.add_child(anchor)
			for layer in 2:
				var quad := _quad(id, layer)
				if quad == null:
					continue
				var mi := MeshInstance3D.new()
				mi.mesh = quad
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				anchor.add_child(mi)
				_track_blink(id, mi)
			_sources.append({"id": id, "node": anchor, "color": _light_color(id)})
			flare_count += 1


func _track_blink(id: String, node: Node3D) -> void:
	if _flares[id].get("blink") is Dictionary:
		_blinkers.append({"id": id, "node": node})


func _update_blink() -> void:
	for b in _blinkers:
		(b["node"] as Node3D).visible = is_lit(b["id"], _time)
	for l in _lens_materials:
		(l["material"] as StandardMaterial3D).emission_energy_multiplier = l["energy"] if is_lit(l["id"], _time) else 0.0


## Lenses of LENS_TEXTURES glow amber (mask of saturated orange pixels) and blink with their flare.
func _glow_lenses(track: Node3D, track_entry: String) -> void:
	var lenses: Dictionary = LENS_TEXTURES.get(track_entry, {})
	if lenses.is_empty():
		return
	var done := {}
	for child in track.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var m := mesh.surface_get_material(surface) as StandardMaterial3D
			if m == null or done.has(m) or m.albedo_texture == null:
				continue
			var lens: Variant = lenses.get(str(m.resource_name).get_slice(" ", 0))
			if not lens is Dictionary:
				continue
			done[m] = true
			m.emission_enabled = true
			m.emission = LENS_COLOR
			m.emission_texture = _amber_mask(m.albedo_texture)
			_lens_materials.append({"id": lens["flare"], "material": m, "energy": float(lens["energy"])})


## Emission texture of an amber lens: bright orange pixels (red high, green in between, blue low).
static func _amber_mask(tex: Texture2D) -> Texture2D:
	var img := _rgba(tex)
	if img == null:
		return null
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var k := smoothstep(0.75, 0.9, c.r) * smoothstep(0.3, 0.45, c.g) * (1.0 - smoothstep(0.35, 0.55, c.b)) * c.a
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Moves the light pool to the lit flares nearest the camera.
func _pick_lights() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var near: Array = []
	for s in _sources:
		if not is_lit(s["id"], _time):
			continue
		var p: Vector3 = (s["node"] as Node3D).global_position if s.has("node") else s["position"]
		near.append([eye.distance_squared_to(p), p, s["color"]])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in lights.size():
		lights[i].visible = i < near.size()
		if i < near.size():
			lights[i].global_position = near[i][1]
			lights[i].light_color = near[i][2]


## Billboard quad for one sprite layer of a flare, or null when the layer has no texture.
func _quad(id: String, layer: int, fade_near := false) -> QuadMesh:
	var spec: Dictionary = _flares[id]["layers"][layer]
	if spec["texture"] == null or float(spec["size"]) <= 0.0:
		return null
	var key := "%s_%d%s" % [id, layer, "_fade" if fade_near else ""]
	if not _materials.has(key):
		var tex := _texture(str(spec["texture"]))
		if tex == null:
			return null
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.no_depth_test = false
		m.disable_fog = true
		m.albedo_texture = tex
		var c := _color(spec["color"])
		var energy := NIGHT_ENERGY if night else DAY_ENERGY
		if id in _lens_ids:
			c = Color(LENS_COLOR.r, LENS_COLOR.g, LENS_COLOR.b, c.a)
			energy = LENS_SPRITE_ENERGY
		m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, c.a)
		if fade_near:
			m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
			m.distance_fade_min_distance = LAMP_SPRITE_FADE.x
			m.distance_fade_max_distance = LAMP_SPRITE_FADE.y
		_materials[key] = m
	var quad := QuadMesh.new()
	var size := float(spec["size"]) * SIZE_SCALE * (LENS_SPRITE_SCALE if id in _lens_ids else 1.0)
	quad.size = Vector2(size, size)
	quad.material = _materials[key]
	return quad


static var _textures := {}


static func _texture(texture_name: String) -> Texture2D:
	if _textures.has(texture_name):
		return _textures[texture_name]
	var tex: Texture2D = null
	var index: Variant = OriginalAssets.load_json(FLARE_TEXTURES + "index.json")
	if index is Dictionary:
		for e: Dictionary in index["entries"]:
			if e["name"] == texture_name and e.has("file"):
				var img := Image.load_from_file(OriginalAssets.path(FLARE_TEXTURES + str(e["file"])))
				if img != null:
					img.generate_mipmaps()
					tex = ImageTexture.create_from_image(img)
				break
	_textures[texture_name] = tex
	return tex


## Light colour of a flare: its core and halo colours mixed, at full brightness.
func _light_color(id: String) -> Color:
	if id in _lens_ids:
		return LENS_COLOR
	var layers: Array = _flares[id]["layers"]
	var c := _color(layers[0]["color"]).lerp(_color(layers[1]["color"]), 0.5 if layers[1]["texture"] != null else 0.0)
	var top := maxf(c.r, maxf(c.g, c.b))
	return Color(c.r / top, c.g / top, c.b / top) if top > 0.0 else Color.WHITE


static func _color(a: Array) -> Color:
	return Color(a[0], a[1], a[2], a[3])


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Night glow for the textures in LIT_TEXTURES of the track entry; returns how many materials.
static func glow_textures(track: Node3D, track_entry: String) -> int:
	var names: Dictionary = LIT_TEXTURES.get(track_entry, {})
	if names.is_empty():
		return 0
	var done := {}
	for child in track.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var m := mesh.surface_get_material(surface) as StandardMaterial3D
			if m == null or done.has(m) or m.albedo_texture == null:
				continue
			var tex_name := str(m.resource_name).get_slice(" ", 0)
			if not names.has(tex_name):
				continue
			done[m] = true
			m.emission_enabled = true
			var energy: float = names[tex_name]
			if tex_name.begins_with("win"):
				m.emission = WINDOW_TINT
				m.emission_energy_multiplier = WINDOW_ENERGY
				m.emission_texture = _contrast(m.albedo_texture, WINDOW_GAMMA)
				continue
			m.emission = GLASS_TINT if energy >= 1.0 else Color.WHITE
			m.emission_energy_multiplier = energy
			m.emission_texture = _bright_mask(m.albedo_texture, GLASS_THRESHOLD if energy >= 1.0 else LIT_THRESHOLD)
	return done.size()


## Emission texture: the pixels brighter than the threshold ramp, times their alpha (cut-out lamp
## textures are white where transparent).
static func _bright_mask(tex: Texture2D, threshold: Vector2) -> Texture2D:
	var img := _rgba(tex)
	if img == null:
		return null
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var k := smoothstep(threshold.x, threshold.y, c.get_luminance()) * c.a
			img.set_pixel(x, y, Color(k, k, k, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Emission texture keeping the picture: colours raised to a power (darker midtones, more
## contrast), times alpha.
static func _contrast(tex: Texture2D, gamma: float) -> Texture2D:
	var img := _rgba(tex)
	if img == null:
		return null
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(pow(c.r, gamma) * c.a, pow(c.g, gamma) * c.a, pow(c.b, gamma) * c.a, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Editable RGBA8 copy of a texture's image without mipmaps, or null.
static func _rgba(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img
