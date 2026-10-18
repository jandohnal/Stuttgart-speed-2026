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

const FLARES := "GameData/Render/flares.json"
const FLARE_TEXTURES := "GameData/Render/common/"
const TICKS_PER_SECOND := 60.0  ## blink ticks; sawhorse lights then blink once a second
const SIZE_SCALE := 0.1  ## m per flare.dat size unit (sawhorse glow 0.6 / 0.9 m, street lamp 1.4 / 5.9 m)
const NIGHT_ENERGY := 3.0  ## sprite colour multiplier; above the glow threshold so flares bloom
const DAY_ENERGY := 1.0
const LIGHT_POOL := 12  ## OmniLight3D at night
const LIGHT_RANGE := 14.0  ## m
const LIGHT_ENERGY := 1.6
const LIGHT_PICK_INTERVAL := 0.25  ## s between re-picking the nearest flares
## Texture names (track .fsh) per HDRI entry whose bright pixels glow at night -> emission energy:
## lit windows, neon tubes. Names are per track, the same name elsewhere is another picture. Not
## the monaco1/2 tunnel walls (ttm1-4): the tunnel ceiling is mapped onto their lamp strip, so even
## a faint glow lit the whole tunnel white; their painted lamps show well enough unlit.
const LIT_TEXTURES := {
	"monaco": {"win1": 0.6, "win4": 0.6, "win5": 0.6, "neo1": 0.6, "neo2": 0.6, "neo5": 0.6, "neo6": 0.6},
}
const LIT_THRESHOLD := Vector2(0.9, 1.0)  ## luminance ramp of the emission mask

var night := false
var flare_count := 0  ## sprites' flares placed (world + on objects)
var lights: Array[OmniLight3D] = []
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
			light.light_energy = LIGHT_ENERGY
			light.shadow_enabled = false
			light.visible = false
			add_child(light)
			lights.append(light)
		glow_textures(track, track_entry)
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
	for layer in 2:
		var mesh := _quad(id, layer)
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
		_sources.append({"id": id, "position": _vec(f["position"]), "color": _light_color(id)})
	flare_count += flares.size()


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
func _quad(id: String, layer: int) -> QuadMesh:
	var spec: Dictionary = _flares[id]["layers"][layer]
	if spec["texture"] == null or float(spec["size"]) <= 0.0:
		return null
	var key := "%s_%d" % [id, layer]
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
		m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, c.a)
		_materials[key] = m
	var quad := QuadMesh.new()
	var size := float(spec["size"]) * SIZE_SCALE
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
			m.emission = Color.WHITE
			m.emission_energy_multiplier = names[tex_name]
			m.emission_texture = _bright_mask(m.albedo_texture)
	return done.size()


static func _bright_mask(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var k := smoothstep(LIT_THRESHOLD.x, LIT_THRESHOLD.y, c.get_luminance())
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
