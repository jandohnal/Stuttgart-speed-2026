extends Node3D
## Water of the track (D-033, docs/water.md): the original's water particle systems where its
## emitters are (waterfalls, rapids, fountains), flowing waterfall and fountain textures, cars
## getting wet in the spray and stirring the mist.
## - Emitters: <track>_emitters.json (tools/emitters.py: ef entries with both basis rows), systems:
##   particles.json (tools/particles.py). Reading of particle.ini (hypothesis, docs/formats/particle.md):
##   emit.y is the speed along the emitter's "up" row per tick (TICK), emit.x and emit.z the size
##   of the emitting area across it, randemit the random part of the speed, weight times g pulls down
##   (negative: rises), lifetime in ticks, size start -> end in m, colours over life.
## - Flowing water: the track materials in FLOWING (track and texture: the same name is something
##   else on another track) scroll their texture.
## - A car inside a spray zone (along an emitter's throw, as wide as its particles) gets wet
##   (CarEffects.wet); a moving car near the water carries an attractor that pushes the particles away.

const CarEffects := preload("res://scripts/car_effects.gd")
const Waterfall := preload("res://scripts/waterfall.gd")

const PARTICLES := "GameData/Render/particles.json"
const PARTICLE_DIR := "GameData/Render/particle"
const WATER := ["WF01", "WF02", "WF03", "WF04", "WF05", "WF06", "WF07", "WF08", "RPD1", "RPD2", "RPD3",
	"RPD4", "CTM1", "CTD1", "CTD2", "CTD3", "CSF1", "CSF2"]
const MIST_TEXTURES := ["sstk"]  ## drawn with the Kenney puffs (the original's are 64 px)
## Track -> textures of flowing water -> scroll speed in texture heights per second. Positive
## where the texture's v grows upwards on the mesh (forest and canyon falls, castle wfw4), negative
## where it grows downwards (castle wfw1 and wfw2, the rapids, the casino fountain), so the water
## always runs down.
const FLOWING := {
	"forest": {"rvr2": -0.25},
	"castle": {"wfw1": -0.6, "wfw2": -0.6, "wfw4": 0.45},
	"canyon": {"wfw2": 0.6, "wfw4": 0.45},
	"monaco1": {"fnt1": -1.0, "fnt2": -1.0, "fnt3": -1.0},
	"monaco2": {"fnt1": -1.0, "fnt2": -1.0, "fnt3": -1.0},
	"monaco3": {"fnt1": -1.0, "fnt2": -1.0, "fnt3": -1.0},
	"monaco4": {"fnt1": -1.0, "fnt2": -1.0, "fnt3": -1.0},
}

## Track -> materials of a waterfall drawn by Waterfall (flow shader, droplets, splash, sound)
## instead of a scrolling texture.
const WATERFALLS := {"forest": ["wfw2", "wfw4"]}
const FOOT_MIST := ["WF02", "WF06"]  ## the original's mist where a fall lands: the feet of a Waterfall

const TICK := 1.0 / 30.0  ## s, unit of particle.ini speeds and lifetimes (fits: a fall's spray drops its 90 m height in its lifetime, the castle fountain rises about 1 m)
const COUNT_SCALE := 2.0  ## times the original's count (spray)
const MIST_COUNT_SCALE := 1.5  ## mist puffs, a few more than the original's
const MIST_COUNT_BY_TAG := {"WF08": 3.0}  ## the slow share of the spray over the forest bridge (the rest: Waterfall's blast)
const MIST_SIZE_SCALE := 1.0  ## as the original (10 m): unlit they are affordable
const MIST_SLOW := 2.0  ## slow motion on the same path: 1/x the speed, x times the life, 1/x² the gravity and drag
const ACTIVE_RANGE := 350.0  ## m from the camera an emitter runs
const MIST_FADE := 1.5  ## m of soft edge where a puff meets the ground or a car
const WET_REACH := 40.0  ## m of an emitter's throw that wets a car at most
## Mist is drawn unlit (lighting the big overlapping puffs cost 11 of 31 FPS by the forest bridge),
## at this brightness of its colour by day and by night.
const MIST_LIGHT := {"day": 0.8, "night": 0.15}
## What particle.ini leaves out of the mist (weight 0 flew in a straight line at a steady speed):
const MIST_SINK := 0.12  ## m/s² down when the system has no weight: WF08 crosses the road at about car height, then settles
const MIST_DRAG := 0.25  ## m/s² of slowing in the air
const MIST_SPEED_SPREAD := 0.35  ## share of the speed each puff differs by
const MIST_MIN_SPREAD := 22.0  ## degrees
const MIST_OPACITY := 2.0  ## times the original's alpha: the puffs spread out on the way
const MIST_GROWTH := 0.7  ## share of its full size a puff starts at when the system keeps its size
const STIR_RADIUS := 3.5  ## m
const STIR_STRENGTH := 40.0  ## attractor strength at STIR_FULL
const STIR_FULL := 20.0  ## m/s
const STIR_MIN := 3.0  ## m/s
const STIR_RANGE := 80.0  ## m from an emitter a car stirs

var _emitters: Array[GPUParticles3D] = []
var _zones := []  ## {from, to, radius}: spray that wets
var _flowing := []  ## {material, speed}
var _cars: Array[Car] = []
var _stirs := {}  ## car -> GPUParticlesAttractorSphere3D
var _textures := {}
var _mist_light := 0.8
var _waterfall: Node3D


func setup(track_name: String, track: Node3D, cars: Array[Car]) -> void:
	_cars = cars
	_mist_light = MIST_LIGHT.get(str(get_parent().get("time_of_day")), MIST_LIGHT["day"])
	var systems := {}
	var data: Variant = OriginalAssets.load_json(PARTICLES) if OriginalAssets.exists(PARTICLES) else null
	if data is Dictionary:
		for s: Dictionary in data["systems"]:
			if s["tag"] in WATER and not systems.has(s["tag"]):
				systems[s["tag"]] = s
	var path := "GameData/Track/%s/%s_emitters.json" % [track_name, track_name]
	var list: Variant = OriginalAssets.load_json(path) if OriginalAssets.exists(path) else null
	if list is Dictionary and not systems.is_empty():
		for e: Dictionary in list["emitters"]:
			if systems.has(e["id"]):
				_add_emitter(e, systems[e["id"]])
	_find_flowing(track, FLOWING.get(track_name, {}))
	if WATERFALLS.has(track_name) and track != null and list is Dictionary:
		var feet := []
		for e: Dictionary in list["emitters"]:
			if e["id"] in FOOT_MIST:
				feet.append(_vec(e["position"]))
		var w := Waterfall.new()
		w.name = "Waterfall"
		add_child(w)
		if w.setup(track, WATERFALLS[track_name], feet, _mist_light, _original_texture("WFAL")):
			_waterfall = w
			_emitters.append_array(w.emitters)
		else:
			w.queue_free()
	if not _emitters.is_empty():
		for car in cars:
			var a := GPUParticlesAttractorSphere3D.new()
			a.radius = STIR_RADIUS
			a.strength = 0.0
			a.attenuation = 1.0
			a.position = Vector3(0, 0.6, 0)
			car.add_child(a)
			_stirs[car] = a
	print("TrackWater: %d emitters, %d flowing materials" % [_emitters.size(), _flowing.size()])


## Emitters on the track, emitters running now, flowing materials (tests).
func counts() -> Dictionary:
	var active := 0
	for e in _emitters:
		active += 1 if e.emitting else 0
	return {"emitters": _emitters.size(), "active": active, "flowing": _flowing.size(),
		"waterfall_sound": _waterfall != null and _waterfall.sound_playing()}


func _process(delta: float) -> void:
	for f: Dictionary in _flowing:
		var m: BaseMaterial3D = f["material"]
		m.uv1_offset.y = fposmod(m.uv1_offset.y + float(f["speed"]) * delta, 1.0)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var eye := camera.global_position
		for e in _emitters:
			var on := e.global_position.distance_to(eye) < ACTIVE_RANGE
			e.emitting = on
			e.visible = on
	for car in _cars:
		if not is_instance_valid(car):
			continue
		var p := car.global_position
		var near := INF
		for z: Dictionary in _zones:
			var d := _segment_distance(p, z["from"], z["to"])
			near = minf(near, d - float(z["radius"]))
			if d < float(z["radius"]):
				var effects := car.get_node_or_null("Effects")
				if effects != null:
					effects.wet(1.0 - 0.5 * d / float(z["radius"]))
		var stir: GPUParticlesAttractorSphere3D = _stirs.get(car)
		if stir != null:
			var speed := car.linear_velocity.length()
			stir.strength = -STIR_STRENGTH * smoothstep(STIR_MIN, STIR_FULL, speed) if near < STIR_RANGE else 0.0


static func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- emitters --------------------------------------------------------------------------------

func _add_emitter(e: Dictionary, s: Dictionary) -> void:
	var up := _vec(e["up"]).normalized()
	var x := _vec(e["direction"])
	x = (x - up * x.dot(up)).normalized()
	if x.length() < 0.5:
		x = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(x, up, x.cross(up))
	var emit: Array = s["emit"]
	var rnd: Array = s["emit_random"]
	var mist: bool = s["texture"] in MIST_TEXTURES
	var slow: float = MIST_SLOW if mist else 1.0
	var speed := float(emit[1]) / TICK / slow
	var spread_speed := Vector2(float(rnd[0]), float(rnd[2])).length() / TICK / slow
	var lifetime := float(s["lifetime"]) * TICK * slow
	var size: Array = s["size"]
	var big := maxf(maxf(float(size[0]), float(size[1])), 0.05) * (MIST_SIZE_SCALE if mist else 1.0)
	var g := 9.81 * float(s["weight"])
	if mist and is_zero_approx(g):
		g = MIST_SINK
	g /= slow * slow
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3.UP  # the emitter's up row
	p.spread = rad_to_deg(atan2(spread_speed, maxf(speed, 0.01))) if speed > 0.0 else 180.0
	p.initial_velocity_min = maxf(speed - float(rnd[1]) / TICK / slow, 0.0)
	p.initial_velocity_max = speed + float(rnd[1]) / TICK / slow
	p.gravity = Vector3(0, -g, 0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	var top := maxf(maxf(float(size[0]), float(size[1])), 0.05)
	var start := float(size[0]) / top
	if mist:  # it spreads as it drifts, on air that slows and swirls it
		start = minf(start, MIST_GROWTH)
		p.spread = maxf(p.spread, MIST_MIN_SPREAD)
		p.initial_velocity_min = minf(p.initial_velocity_min, speed * (1.0 - MIST_SPEED_SPREAD))
		p.initial_velocity_max = maxf(p.initial_velocity_max, speed * (1.0 + MIST_SPEED_SPREAD))
		p.damping_min = MIST_DRAG * 0.6 / (slow * slow)
		p.damping_max = MIST_DRAG * 1.4 / (slow * slow)
		p.turbulence_enabled = true
		p.turbulence_noise_strength = 3.0
		p.turbulence_noise_scale = 6.0
		p.turbulence_noise_speed_random = 0.3
		p.turbulence_influence_min = 0.005  # a share of the velocity replaced per frame: more stops it short of the road
		p.turbulence_influence_max = 0.025
	p.scale_curve = CarEffects._curve([Vector2(0, start), Vector2(1, float(size[1]) / top)])
	var stops := []
	var colors: Array = s["colors"]
	for i in colors.size():
		var color: Color = CarEffects._argb(colors[i])
		if mist:
			color.a = minf(color.a * MIST_OPACITY, 1.0)
		stops.append([float(i) / maxf(colors.size() - 1, 1.0), color])
	p.color_ramp = CarEffects._ramp(stops)
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(float(emit[0]) * 0.5, 0.05, float(emit[2]) * 0.5)
	p.attractor_interaction_enabled = true  # cars push it
	var m := _material(s["texture"], p, mist)
	var quad := QuadMesh.new()
	quad.size = Vector2(big, big)
	quad.material = m
	var em := GPUParticles3D.new()
	em.process_material = p
	em.draw_pass_1 = quad
	var scale: float = MIST_COUNT_BY_TAG.get(s["tag"], MIST_COUNT_SCALE) if mist else COUNT_SCALE
	em.amount = maxi(int(round(float(s["count"]) * scale)), 1)
	em.lifetime = lifetime
	em.preprocess = lifetime  # running already when the camera gets there
	em.local_coords = false
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	em.emitting = false
	em.visible = false
	var reach := speed * lifetime + 0.5 * absf(g) * lifetime * lifetime + big
	em.visibility_aabb = AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	add_child(em)
	em.global_transform = Transform3D(basis, _vec(e["position"]))
	_emitters.append(em)
	# Spray zone along the throw (straight: the drop by gravity is left out).
	var throw := minf(speed * lifetime, WET_REACH)
	var origin := _vec(e["position"])
	_zones.append({"from": origin, "to": origin + up * throw, "radius": top * 0.5 + 1.0})  # as wide as the original's puffs


func _material(texture: String, p: ParticleProcessMaterial, mist: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if mist:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(_mist_light, _mist_light, _mist_light)
	m.proximity_fade_enabled = true  # no hard line where a puff cuts into the ground or a car
	m.proximity_fade_distance = MIST_FADE if mist else 0.3
	var atlas := CarEffects._pack_atlas("puff") if mist else null
	if atlas != null:
		m.albedo_texture = atlas
		m.particles_anim_h_frames = CarEffects.PACK["puff"].size()
		m.particles_anim_v_frames = 1
		m.particles_anim_loop = false
		p.anim_speed_min = 0.0
		p.anim_speed_max = 0.0
		p.anim_offset_min = 0.0
		p.anim_offset_max = 1.0
	else:
		m.albedo_texture = _original_texture(texture)
	return m


## A texture of the original's particle.fsh (decomposed/GameData/Render/particle, index.json).
func _original_texture(name: String) -> Texture2D:
	if _textures.has(name):
		return _textures[name]
	var tex: Texture2D = CarEffects._texture("puff")
	var index: Variant = OriginalAssets.load_json(PARTICLE_DIR.path_join("index.json")) if OriginalAssets.exists(PARTICLE_DIR.path_join("index.json")) else null
	if index is Dictionary:
		for entry: Dictionary in index["entries"]:
			if entry["name"] == name:
				var img := Image.new()
				var file := OriginalAssets.path(PARTICLE_DIR.path_join(entry["file"]))
				if img.load_png_from_buffer(FileAccess.get_file_as_bytes(file)) == OK:
					img.generate_mipmaps()
					tex = ImageTexture.create_from_image(img)
				break
	_textures[name] = tex
	return tex


# --- flowing water ---------------------------------------------------------------------------

func _find_flowing(track: Node3D, speeds: Dictionary) -> void:
	if track == null or speeds.is_empty():
		return
	var seen := {}
	for node in track.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := (node as MeshInstance3D).get_active_material(s) as BaseMaterial3D
			if m == null or seen.has(m):
				continue
			seen[m] = true
			var name := m.resource_name.get_slice(" ", 0)
			if speeds.has(name):
				_flowing.append({"material": m, "speed": speeds[name]})


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
