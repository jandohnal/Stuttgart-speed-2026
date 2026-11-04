extends Node3D
## One waterfall of the original's track made more real (D-033): its mesh drawn with a flow shader,
## droplets and spray thrown off the sheet, a splash where it lands and the original's sound.
## The sheet's triangles come from the track's meshes; the particles start on them. The feet are
## where the original puts the mist at the bottom (WF02, WF06). TrackWater starts and stops
## `emitters` with the camera's distance like its own.

const CarEffects := preload("res://scripts/car_effects.gd")
const SHADER := preload("res://shaders/waterfall.gdshader")
const SOUND := "GameData/Sounds/track/waterfall huge_129"
const SOUND_UNIT := 35.0  ## m of full loudness
const SOUND_RANGE := 400.0  ## m

const POINTS := 512  ## emission points on the sheet
const DROPLETS := 420
const DROPLET_LIFETIME := 2.4  ## s
const DROPLET_SPEED := Vector2(1.0, 4.5)  ## m/s off the sheet
const DROPLET_WIDTH := 0.14  ## m at the head of a streak, wider than a drop: seen from tens of metres
const DROPLET_TRAIL := 0.14  ## s of path drawn
const SPRAY := 80
const SPRAY_LIFETIME := 7.0
const SPRAY_SIZE := 10.0  ## m
## Thrown back at the landing, as shares of the fall's impact speed sqrt(2 g h) (forest 91 m: 42 m/s).
const BLAST_PUFFS := 170  ## per foot: most of the spray, water with a real mass and speed
## Puffs are slowed down as a whole, like slow motion on the same path: 1/SLOW the speed, SLOW times
## the life, 1/SLOW² the gravity and drag.
const SLOW := 2.0
const BLAST_SPEED := Vector2(0.3, 0.7)
const BLAST_LIFETIME := 2.2
const BLAST_DRAG := Vector2(5.0, 10.0)  ## m/s² in the air
const BLAST_SIZE := 10.0  ## m at the end of its life
const BLAST_RISE := 0.45  ## of the level throw, upwards
const SPLASH_DROPLETS := 200  ## per foot
const SPLASH_LIFETIME := 1.8
const SPLASH_SPEED := Vector2(0.2, 0.55)
const SPLASH_PUFFS := 24  ## per foot
const SPLASH_PUFF_SIZE := 10.0
const SPLASH_AREA := Vector3(6.0, 0.2, 6.5)  ## m, as the original's WF02

var emitters: Array[GPUParticles3D] = []
var _light := 0.8
var _spray_texture: Texture2D
var _sound: AudioStreamPlayer3D


## textures: names of the waterfall's materials; feet: world points at its bottom.
func setup(track: Node3D, textures: Array, feet: Array, light: float, spray_texture: Texture2D) -> bool:
	_light = light
	_spray_texture = spray_texture
	var triangles := PackedVector3Array()
	var noise := _noise_texture()
	for node in track.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s) as BaseMaterial3D
			if base == null or not base.resource_name.get_slice(" ", 0) in textures:
				continue
			var first := triangles.size()
			triangles.append_array(_world_triangles(mi, s))
			mi.set_surface_override_material(s, _sheet_material(base, noise, triangles, first))
	if triangles.is_empty():
		return false
	var box := AABB(triangles[0], Vector3.ZERO)
	for v in triangles:
		box = box.expand(v)
	var out := _fall_direction(triangles, box)
	_add_droplets(triangles, box, out)
	_add_spray(triangles, box, out)
	var impact := sqrt(2.0 * 9.81 * box.size.y)
	for foot: Vector3 in feet:
		_add_splash(foot, out, impact)
	_add_sound(feet, box)
	return true


func _world_triangles(mi: MeshInstance3D, surface: int) -> PackedVector3Array:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var xf := mi.global_transform
	var out := PackedVector3Array()
	var n := indices.size() if not indices.is_empty() else verts.size()
	for i in n:
		out.append(xf * verts[indices[i] if not indices.is_empty() else i])
	return out


func _sheet_material(base: BaseMaterial3D, noise: Texture2D, triangles: PackedVector3Array, first: int) -> ShaderMaterial:
	var top := -INF
	for i in range(first, triangles.size()):
		top = maxf(top, triangles[i].y)
	var m := ShaderMaterial.new()
	m.resource_name = base.resource_name
	m.shader = SHADER
	m.set_shader_parameter("sheet", base.albedo_texture)
	m.set_shader_parameter("noise", noise)
	m.set_shader_parameter("top", top)
	return m


static func _noise_texture() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = 0.02
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.normalize = true
	t.noise = n
	return t


## Level direction the water falls away from the cliff: from the top of the sheet to its bottom.
static func _fall_direction(triangles: PackedVector3Array, box: AABB) -> Vector3:
	var high := Vector3.ZERO
	var low := Vector3.ZERO
	var nh := 0
	var nl := 0
	var mid := box.position.y + box.size.y * 0.5
	for v in triangles:
		if v.y > mid:
			high += v
			nh += 1
		else:
			low += v
			nl += 1
	var d := low / maxf(nl, 1) - high / maxf(nh, 1)
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


## Random points on the triangles below share `up_to` (0 = bottom, 1 = top) of the height, by area,
## relative to `origin`, in a float texture for the particle emission shape.
func _points(triangles: PackedVector3Array, box: AABB, origin: Vector3, up_to: float) -> ImageTexture:
	var areas := PackedFloat32Array()
	var total := 0.0
	var limit := box.position.y + box.size.y * up_to
	for t in range(0, triangles.size() - 2, 3):
		var a := triangles[t]
		var b := triangles[t + 1]
		var c := triangles[t + 2]
		if (a.y + b.y + c.y) / 3.0 <= limit:
			total += (b - a).cross(c - a).length()
		areas.append(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var data := PackedFloat32Array()
	data.resize(POINTS * 3)
	for k in POINTS:
		var pick := areas.bsearch(rng.randf() * total)
		var t := mini(pick, areas.size() - 1) * 3
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var p := triangles[t] + (triangles[t + 1] - triangles[t]) * u + (triangles[t + 2] - triangles[t]) * v - origin
		data[k * 3] = p.x
		data[k * 3 + 1] = p.y
		data[k * 3 + 2] = p.z
	var img := Image.create_from_data(POINTS, 1, false, Image.FORMAT_RGBF, data.to_byte_array())
	return ImageTexture.create_from_image(img)


func _add_droplets(triangles: PackedVector3Array, box: AABB, out: Vector3) -> void:
	var centre := box.get_center()
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	p.emission_point_texture = _points(triangles, box, centre, 1.0)
	p.emission_point_count = POINTS
	p.direction = (out + Vector3.UP * 0.2).normalized()
	p.spread = 30.0
	p.initial_velocity_min = DROPLET_SPEED.x
	p.initial_velocity_max = DROPLET_SPEED.y
	p.gravity = Vector3(0, -9.81, 0)
	p.color_ramp = CarEffects._ramp([[0.0, Color(1, 1, 1, 0)], [0.15, Color(1, 1, 1, 0.75)], [1.0, Color(1, 1, 1, 0)]])
	var e := _ribbons(p, DROPLETS, DROPLET_LIFETIME)
	_place(e, centre, box.size.length() + 40.0)


func _add_spray(triangles: PackedVector3Array, box: AABB, out: Vector3) -> void:
	var centre := box.get_center()
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	p.emission_point_texture = _points(triangles, box, centre, 0.7)
	p.emission_point_count = POINTS
	p.direction = out
	p.spread = 40.0
	p.initial_velocity_min = 1.0 / SLOW
	p.initial_velocity_max = 3.0 / SLOW
	p.gravity = Vector3(0, -2.5 / (SLOW * SLOW), 0)
	p.damping_min = 0.3 / (SLOW * SLOW)
	p.damping_max = 0.6 / (SLOW * SLOW)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_curve = CarEffects._curve([Vector2(0, 0.45), Vector2(1, 1.0)])
	p.color_ramp = CarEffects._ramp([[0.0, Color(1, 1, 1, 0)], [0.2, Color(1, 1, 1, 0.7)], [1.0, Color(1, 1, 1, 0)]])
	p.attractor_interaction_enabled = true
	var e := _puffs(p, SPRAY, SPRAY_LIFETIME, SPRAY_SIZE)
	_place(e, centre, box.size.length() + 40.0)


## Where the water lands: a blast of water thrown out at a share of the impact speed, falling back
## under full gravity, droplets among it and slower spray rising.
func _add_splash(foot: Vector3, out: Vector3, impact: float) -> void:
	var throw := (out + Vector3.UP * BLAST_RISE).normalized()
	var b := ParticleProcessMaterial.new()
	b.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	b.emission_box_extents = SPLASH_AREA * 0.5
	b.direction = throw
	b.spread = 28.0
	b.initial_velocity_min = impact * BLAST_SPEED.x / SLOW
	b.initial_velocity_max = impact * BLAST_SPEED.y / SLOW
	b.gravity = Vector3(0, -9.81 / (SLOW * SLOW), 0)
	b.damping_min = BLAST_DRAG.x / (SLOW * SLOW)
	b.damping_max = BLAST_DRAG.y / (SLOW * SLOW)
	b.angle_min = -180.0
	b.angle_max = 180.0
	b.scale_min = 0.6
	b.scale_max = 1.0
	b.scale_curve = CarEffects._curve([Vector2(0, 0.3), Vector2(1, 1.0)])
	b.color_ramp = CarEffects._ramp([[0.0, Color(1, 1, 1, 0.75)], [0.5, Color(1, 1, 1, 0.45)], [1.0, Color(1, 1, 1, 0)]])
	b.attractor_interaction_enabled = true
	_place(_puffs(b, BLAST_PUFFS, BLAST_LIFETIME * SLOW, BLAST_SIZE), foot, 70.0)
	var d := ParticleProcessMaterial.new()
	d.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	d.emission_box_extents = SPLASH_AREA * 0.5
	d.direction = throw
	d.spread = 40.0
	d.initial_velocity_min = impact * SPLASH_SPEED.x
	d.initial_velocity_max = impact * SPLASH_SPEED.y
	d.gravity = Vector3(0, -9.81, 0)
	d.color_ramp = CarEffects._ramp([[0.0, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0)]])
	_place(_ribbons(d, SPLASH_DROPLETS, SPLASH_LIFETIME), foot, 50.0)
	var s := ParticleProcessMaterial.new()
	s.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	s.emission_box_extents = SPLASH_AREA * 0.5
	s.direction = Vector3.UP
	s.spread = 25.0
	s.initial_velocity_min = 2.0 / SLOW
	s.initial_velocity_max = 5.0 / SLOW
	s.gravity = Vector3(0, -1.5 / (SLOW * SLOW), 0)
	s.angle_min = -180.0
	s.angle_max = 180.0
	s.scale_curve = CarEffects._curve([Vector2(0, 0.4), Vector2(1, 1.0)])
	s.color_ramp = CarEffects._ramp([[0.0, Color(1, 1, 1, 0.4)], [1.0, Color(1, 1, 1, 0)]])
	s.attractor_interaction_enabled = true
	_place(_puffs(s, SPLASH_PUFFS, 2.2 * SLOW, SPLASH_PUFF_SIZE), foot, 40.0)


## Streaks: each droplet draws a short ribbon along its path, unlit like the sparks.
func _ribbons(p: ParticleProcessMaterial, amount: int, lifetime: float) -> GPUParticles3D:
	p.attractor_interaction_enabled = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.use_particle_trails = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(_light, _light, _light)
	var ribbon := RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_CROSS
	ribbon.size = DROPLET_WIDTH
	ribbon.sections = 2
	ribbon.section_length = 0.2
	ribbon.curve = CarEffects._curve([Vector2(0, 0.0), Vector2(0.7, 1.0), Vector2(1, 0.6)]).curve  # no blunt rectangles close up
	ribbon.material = m
	var e := _emitter(p, amount, lifetime)
	e.draw_pass_1 = ribbon
	e.trail_enabled = true
	e.trail_lifetime = DROPLET_TRAIL
	return e


## Unlit spray clouds: lighting big overlapping quads is what costs frames (TrackWater).
func _puffs(p: ParticleProcessMaterial, amount: int, lifetime: float, size: float) -> GPUParticles3D:
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(_light, _light, _light)
	m.albedo_texture = _spray_texture
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 1.5
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = m
	var e := _emitter(p, amount, lifetime)
	e.draw_pass_1 = quad
	return e


func _emitter(p: ParticleProcessMaterial, amount: int, lifetime: float) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.process_material = p
	e.amount = amount
	e.lifetime = lifetime
	e.preprocess = lifetime
	e.local_coords = false
	e.emitting = false
	e.visible = false
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return e


func _place(e: GPUParticles3D, at: Vector3, reach: float) -> void:
	e.visibility_aabb = AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	add_child(e)
	e.global_position = at
	emitters.append(e)


func _add_sound(feet: Array, box: AABB) -> void:
	var dir := SOUND
	var index: Variant = OriginalAssets.load_json(dir.path_join("index.json")) if OriginalAssets.exists(dir.path_join("index.json")) else null
	if not (index is Dictionary) or index["sounds"].is_empty():
		push_warning("Missing %s - run tools/snd2wav.py" % dir)
		return
	var entry: Dictionary = index["sounds"][0]
	var stream := AudioStreamWAV.load_from_file(OriginalAssets.path(dir.path_join(entry["file"])))
	if stream == null:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = int(entry.get("loop_start", 0))
	stream.loop_end = int(entry.get("loop_end", entry["samples"]))
	_sound = AudioStreamPlayer3D.new()
	_sound.stream = stream
	_sound.bus = "Sfx"
	_sound.unit_size = SOUND_UNIT
	_sound.max_distance = SOUND_RANGE
	add_child(_sound)
	var at := box.get_center()
	if not feet.is_empty():
		at = Vector3.ZERO
		for f: Vector3 in feet:
			at += f
		at /= feet.size()
	_sound.global_position = at
	_sound.play()


## Is the sound playing (tests).
func sound_playing() -> bool:
	return _sound != null and _sound.playing
