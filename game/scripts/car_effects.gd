extends Node3D
## Wheel and body effects of a car (D-028):
## - tyre marks: a dark ribbon under each wheel on the road while its tyre slides (the same slip
##   that makes the tyres squeal in CarAudio), left in the world; the oldest fade out and go;
## - dust and bits of ground behind the wheels off the road (the track's `terrain` group), in the
##   colour of the ground texture under the wheel, so grass throws green, a dirt path brown;
##   green ground also throws blades and tufts of grass, ground strewn with fallen leaves
##   (LEAF_GROUND) dry leaves;
## - sparks where the body hits something or scrapes along it.
## The ground under a wheel comes from its ray: the collider's track group (road, terrain) and the
## triangle's material (needs physics/jolt_physics_3d/queries/enable_ray_cast_face_index).
## Dust and dirt use textures of the Kenney Particle Pack, grass Kenney's Foliage Sprites and leaves
## photos of 50 Dry Leaf Textures (all CC0, assets/particles/, a random frame per particle); without
## them dust and dirt get textures generated here, as do the marks (the original's particle.fsh is
## 16-64 px). The sparks take their count and colours from the
## original's "Sparks" system (particles.json, tools/particles.py).

const Materials := preload("res://scripts/materials.gd")
const PARTICLES := "GameData/Render/particles.json"
const SPARKS_TAG := "SPRK"
const GROUPS := ["road", "terrain", "objects"]
const PACK_DIR := "res://assets/particles"
const PACK := {  ## texture kind -> files in PACK_DIR, one atlas frame each
	"puff": ["kenney/smoke_02", "kenney/smoke_04", "kenney/smoke_05", "kenney/smoke_07"],
	"dirt": ["kenney/dirt_01", "kenney/dirt_02", "kenney/dirt_03"],
	"grass": ["foliage/grass_0063", "foliage/grass_0075", "foliage/grass_0078", "foliage/grass_0079",
		"foliage/grass_0080"],
	"leaf": ["leaves/dry_leaf01", "leaves/dry_leaf03", "leaves/dry_leaf05", "leaves/dry_leaf08",
		"leaves/dry_leaf13", "leaves/dry_leaf26", "leaves/dry_leaf34", "leaves/dry_leaf42"],
}
const PACK_FRAME := 256  ## px per atlas frame

const MARK_STEP := 0.25  ## m between ribbon points
const MARK_BREAK := 3.0  ## m: a longer jump (reset, teleport) starts a new ribbon
const MARK_LIFT := 0.02  ## m above the road along its normal
const MARK_ALPHA := 0.7  ## darkest mark
const MARK_COLOR := Color(0.03, 0.03, 0.03)
const MARK_CHUNK_QUADS := 48  ## quads per mesh; only the open chunk is rebuilt
const MARK_CHUNKS := 40  ## kept per car; the oldest quarter fades out
## Slip (1 = grip peak, as in CarAudio) where marks start and where they are darkest.
const MARK_SLIP_FROM := 0.9
const MARK_SLIP_FULL := 1.6

const DUST_SPEED_FULL := 20.0  ## m/s of the car or of the spinning tyre for the full cloud
const DUST_MIN_SPEED := 1.5
const DUST_AMOUNT := 64
const DUST_LIFETIME := 1.8
const DUST_SIZE := 2.4  ## m, quad of one puff before its scale curve
const DEBRIS_AMOUNT := 32  ## generated chips; the pack's dirt clusters need fewer
const DEBRIS_CLUSTERS := 16
const DEBRIS_LIFETIME := 0.9
const GRASS_AMOUNT := 32
const GRASS_LIFETIME := 1.0
const GRASS_SIZE := 0.22  ## m, one blade or thin tuft
## Ground counts as grass when the hue of its colour is green enough: grass textures are 0.16-0.24,
## a gravel shoulder 0.147, dirt and sand 0.07-0.13.
const GRASS_HUE := Vector2(0.155, 0.45)
const GRASS_MIN_SATURATION := 0.15
const LEAF_AMOUNT := 40
const LEAF_LIFETIME := 2.5
const LEAF_SIZE := 0.2  ## m, as the leaves falling from the crowns (FallingLeaves)
## Ground textures strewn with fallen leaves: leag (grass, forest, farmland, foothills), rdca (road
## edge, farmland, foothills).
const LEAF_GROUND := ["leag", "rdca"]

const SPARK_LIFETIME := 0.45
const SPARK_TRAIL := 0.06  ## s of path each spark draws as a streak
const SPARK_WIDTH := 0.025  ## m
const SPARK_COUNT_SCALE := 4  ## times the original's count: one burst lasts only SPARK_BURST
const SPARK_BRIGHTNESS := 4.0  ## HDR colour, so the streaks stay bright after tone mapping
const SPARK_BURST := 0.15  ## s of emission per impact
const SPARK_MIN_IMPULSE := 1000.0  ## N*s summed over one impact
const SPARK_FULL_IMPULSE := 8000.0
const SPARK_SCRAPE_FROM := 100.0  ## N*s per tick of body contact (CarDamage.scrape)
const SPARK_SCRAPE_FULL := 400.0
const SPARK_MIN_SPEED := 4.0  ## m/s for scrape sparks

static var _ground_cache := {}  ## collider instance id -> {group, mesh, ends, colors}
static var _textures := {}

var _car: Car
var _width := 0.18  ## m, tyre tread width
var _trails := []  ## per wheel: {last: Vector3 or INF, left, right, alpha, normal}
var _dust: Array[GPUParticles3D] = []
var _debris: Array[GPUParticles3D] = []
var _grass: Array[GPUParticles3D] = []  ## null when the pack is missing
var _leaves: Array[GPUParticles3D] = []
var _sparks: GPUParticles3D
var _spark_until := 0.0
var _spark_ratio := 0.0
var _time := 0.0
var _chunks: Array[MeshInstance3D] = []
var _open: MeshInstance3D
var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _dirty := false
var _mark_material: StandardMaterial3D


func setup(car: Car) -> void:
	_car = car
	var tyre: Dictionary = car.params.get("tyre", {})
	_width = float(tyre.get("width_mm", 180.0)) / 1000.0
	_mark_material = _make_mark_material()
	for w in car.wheels:
		_trails.append({"last": Vector3.INF})
		var dust := _make_dust()
		add_child(dust)
		_dust.append(dust)
		var debris := _make_debris()
		add_child(debris)
		_debris.append(debris)
		for list: Array in [[_grass, _make_grass()], [_leaves, _make_leaves()]]:
			if list[1] != null:
				add_child(list[1])
			list[0].append(list[1])
	_sparks = _make_sparks()
	add_child(_sparks)
	if car.damage != null:
		car.damage.impacted.connect(_on_impact)


## Dust emitters currently throwing (tests).
func dust_active() -> int:
	var n := 0
	for d in _dust:
		n += 1 if d.emitting else 0
	return n


## Grass and leaf emitters currently throwing (tests).
func foliage_active() -> Vector2i:
	var n := Vector2i.ZERO
	for i in _grass.size():
		n.x += 1 if _grass[i] != null and _grass[i].emitting else 0
		n.y += 1 if _leaves[i] != null and _leaves[i].emitting else 0
	return n


## Quads of tyre marks laid so far, kept chunks only (tests).
func mark_quads() -> int:
	return (_chunks.size() - 1) * MARK_CHUNK_QUADS + _verts.size() / 6 if _open != null else 0


func sparks_active() -> bool:
	return _sparks != null and _sparks.emitting


func _process(delta: float) -> void:
	if _car == null:
		return
	_time += delta
	var speed := _car.linear_velocity.length()
	for i in _car.wheels.size():
		var w: Car.Wheel = _car.wheels[i]
		var ground := {}
		if w.contact and not w.detached and w.ray.is_colliding():
			ground = ground_under(w.ray.get_collider(), w.ray.get_collision_face_index())
		var group: String = ground.get("group", "")
		var slip := maxf(absf(w.slip_angle) / _car.peak_slip_angle, absf(w.slip_ratio) / _car.peak_slip_ratio)
		var mark := smoothstep(MARK_SLIP_FROM, MARK_SLIP_FULL, slip) if group == "road" else 0.0
		_trail(i, w, mark)
		_wheel_dust(i, w, ground if group == "terrain" else {}, speed)
	if _dirty:
		_rebuild_open()
	_update_sparks(speed)


# --- ground ----------------------------------------------------------------------------------

## Track group ("road", "terrain", "objects" or ""), ground colour, texture name and whether the
## material is see-through (crown cards, fences) under a ray hit: {group, color, texture, alpha}.
## Cached per collider; the colour is the average of the hit triangle's texture.
static func ground_under(collider: Object, face: int) -> Dictionary:
	if collider == null:
		return {}
	var id := collider.get_instance_id()
	var entry: Dictionary = _ground_cache.get(id, {})
	if entry.is_empty():
		entry = _ground_entry(collider as Node)
		_ground_cache[id] = entry
	var mesh := entry.get("mesh") as MeshInstance3D
	if mesh == null or not is_instance_valid(mesh):
		return {"group": entry.get("group", ""), "color": Color(0.5, 0.45, 0.35)}
	var ends: PackedInt32Array = entry["ends"]
	var surface := ends.bsearch(face, false) if face >= 0 else 0
	surface = clampi(surface, 0, ends.size() - 1)
	var colors: Dictionary = entry["colors"]
	if not colors.has(surface):
		var material := mesh.get_active_material(surface)
		var texture := material.resource_name.get_slice(" ", 0) if material != null else ""
		var alpha := material is BaseMaterial3D and (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		colors[surface] = [Materials.average_color(material), texture, alpha]
	return {"group": entry["group"], "color": colors[surface][0], "texture": colors[surface][1], "alpha": colors[surface][2]}


## What the ground throws besides dust and dirt: {grass, leaves}, each 0 or 1.
static func foliage(ground: Dictionary) -> Dictionary:
	var c: Color = ground.get("color", Color.BLACK)
	var green := c.h >= GRASS_HUE.x and c.h <= GRASS_HUE.y and c.s >= GRASS_MIN_SATURATION
	var leaves := String(ground.get("texture", "")) in LEAF_GROUND
	return {"grass": 1.0 if green or leaves else 0.0, "leaves": 1.0 if leaves else 0.0}


## The collider's mesh (its parent from create_trimesh_collision), track group and per surface
## end (exclusive) of its triangles in the shape's face order.
static func _ground_entry(node: Node) -> Dictionary:
	var group := ""
	var mesh: MeshInstance3D = null
	var n := node
	while n != null:
		if mesh == null and n is MeshInstance3D:
			mesh = n as MeshInstance3D
		if String(n.name) in GROUPS:
			group = String(n.name)
			break
		n = n.get_parent()
	var ends := PackedInt32Array()
	if mesh != null and mesh.mesh != null:
		var total := 0
		for s in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += (indices.size() if not indices.is_empty() else verts.size()) / 3
			ends.append(total)
	return {"group": group, "mesh": mesh, "ends": ends, "colors": {}}


# --- tyre marks ------------------------------------------------------------------------------

func _trail(i: int, w: Car.Wheel, alpha: float) -> void:
	var t: Dictionary = _trails[i]
	if alpha <= 0.02:
		t["last"] = Vector3.INF
		return
	var n := w.normal
	var side := _car.global_basis.x
	side = (side - n * side.dot(n)).normalized() * (_width * 0.5)
	var centre := w.point + n * MARK_LIFT
	var last: Vector3 = t["last"]
	if last == Vector3.INF or last.distance_to(centre) > MARK_BREAK:
		t.merge({"last": centre, "left": centre - side, "right": centre + side, "alpha": alpha, "normal": n}, true)
		return
	if last.distance_to(centre) < MARK_STEP:
		return
	_add_quad(t["left"], t["right"], centre - side, centre + side, t["normal"], n, t["alpha"], alpha)
	t.merge({"last": centre, "left": centre - side, "right": centre + side, "alpha": alpha, "normal": n}, true)


func _add_quad(al: Vector3, ar: Vector3, bl: Vector3, br: Vector3, na: Vector3, nb: Vector3, alpha_a: float, alpha_b: float) -> void:
	if _open == null or _verts.size() >= MARK_CHUNK_QUADS * 6:
		_new_chunk()
	var ca := Color(MARK_COLOR, alpha_a * MARK_ALPHA)
	var cb := Color(MARK_COLOR, alpha_b * MARK_ALPHA)
	for v: Array in [[al, na, ca, 0.0], [ar, na, ca, 1.0], [br, nb, cb, 1.0],
			[al, na, ca, 0.0], [br, nb, cb, 1.0], [bl, nb, cb, 0.0]]:
		_verts.append(v[0])
		_normals.append(v[1])
		_colors.append(v[2])
		_uvs.append(Vector2(v[3], 0.0))
	_dirty = true


func _new_chunk() -> void:
	if _open != null:
		_rebuild_open()
	_verts = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_uvs = PackedVector2Array()
	_open = MeshInstance3D.new()
	_open.top_level = true
	_open.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_open.material_override = _mark_material
	_open.mesh = ArrayMesh.new()
	add_child(_open)
	_open.global_transform = Transform3D.IDENTITY
	_chunks.append(_open)
	if _chunks.size() > MARK_CHUNKS:
		_chunks.pop_front().queue_free()
	# The chunks closest to being dropped fade out (only once the list is nearly full).
	var fading := MARK_CHUNKS / 4
	for k in _chunks.size():
		var left := MARK_CHUNKS - _chunks.size() + k  # chunks laid before this one goes
		_chunks[k].transparency = 1.0 - clampf(float(left + 1) / float(fading + 1), 0.0, 1.0)


func _rebuild_open() -> void:
	_dirty = false
	var mesh := _open.mesh as ArrayMesh
	mesh.clear_surfaces()
	if _verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _make_mark_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _texture("mark")
	m.roughness = 0.95
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# --- dust off the road -----------------------------------------------------------------------

func _wheel_dust(i: int, w: Car.Wheel, ground: Dictionary, speed: float) -> void:
	var dust := _dust[i]
	var debris := _debris[i]
	var spin := absf(w.omega) * _car.wheel_radius
	var amount := 0.0
	if not ground.is_empty():
		amount = smoothstep(DUST_MIN_SPEED, DUST_SPEED_FULL, maxf(speed, spin))
	dust.emitting = amount > 0.05
	debris.emitting = amount > 0.15
	var throws := foliage(ground) if debris.emitting else {}
	var grass := _grass[i]
	var leaves := _leaves[i]
	if grass != null:
		grass.emitting = throws.get("grass", 0.0) > 0.0
	if leaves != null:
		leaves.emitting = throws.get("leaves", 0.0) > 0.0
	if not dust.emitting:
		return
	dust.amount_ratio = amount
	debris.amount_ratio = amount
	# Thrown behind the way the tyre turns (backwards when reversing).
	var basis := _car.global_basis if w.omega >= 0.0 else _car.global_basis.rotated(_car.global_basis.y, PI)
	var at := Transform3D(basis, w.point + w.normal * 0.05)
	dust.global_transform = at
	debris.global_transform = at
	var color: Color = ground["color"]
	(dust.process_material as ParticleProcessMaterial).color = color.lightened(0.3)
	(debris.process_material as ParticleProcessMaterial).color = color.darkened(0.25)
	if grass != null and grass.emitting:
		grass.amount_ratio = amount
		grass.global_transform = at
		# The texture average is greyer than the blades in it.
		(grass.process_material as ParticleProcessMaterial).color = Color.from_hsv(color.h, minf(color.s * 1.5, 1.0), minf(color.v * 1.2, 1.0))
	if leaves != null and leaves.emitting:
		leaves.amount_ratio = amount
		leaves.global_transform = at


func _make_dust() -> GPUParticles3D:
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3(0, 0.6, 1)  # car front is -Z: behind and up
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.inherit_velocity_ratio = 0.15
	p.gravity = Vector3(0, -0.6, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_min = 0.6
	p.scale_max = 1.2
	p.scale_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.8)])
	p.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.1, Color(1, 1, 1, 0.55)], [1.0, Color(1, 1, 1, 0)]])
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(_width * 0.5, 0.05, 0.1)
	var m := _billboard("puff", false, p)
	m.proximity_fade_enabled = true  # no hard line where the quad cuts into the ground
	m.proximity_fade_distance = 0.6
	return _emitter(p, m, DUST_SIZE, DUST_AMOUNT, DUST_LIFETIME)


func _make_debris() -> GPUParticles3D:
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3(0, 1, 1)
	p.spread = 25.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.inherit_velocity_ratio = 0.3
	p.gravity = Vector3(0, -9.81, 0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_min = 0.5
	p.scale_max = 1.5
	p.color_ramp = _ramp([[0.0, Color.WHITE], [0.8, Color.WHITE], [1.0, Color(1, 1, 1, 0)]])
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(_width * 0.5, 0.02, 0.05)
	var m := _billboard("dirt", false, p)
	if m.particles_anim_h_frames > 1:  # clusters of clods from the pack
		p.scale_curve = _curve([Vector2(0, 0.6), Vector2(1, 1.0)])
		return _emitter(p, m, 0.5, DEBRIS_CLUSTERS, DEBRIS_LIFETIME)
	m = _billboard("chip", false)
	return _emitter(p, m, 0.1, DEBRIS_AMOUNT, DEBRIS_LIFETIME)


## Tufts and blades of grass torn out by the tyre (white sprites tinted by the ground colour).
func _make_grass() -> GPUParticles3D:
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3(0, 1, 1)
	p.spread = 30.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.inherit_velocity_ratio = 0.3
	p.gravity = Vector3(0, -7.0, 0)
	p.damping_min = 0.5
	p.damping_max = 1.0
	p.angle_min = -40.0  # mostly upright, as torn out
	p.angle_max = 40.0
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_min = 0.6
	p.scale_max = 1.2
	p.color_ramp = _ramp([[0.0, Color.WHITE], [0.8, Color.WHITE], [1.0, Color(1, 1, 1, 0)]])
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(_width * 0.5, 0.02, 0.05)
	var m := _billboard("grass", false, p)
	if m.particles_anim_h_frames <= 1:
		return null
	m.alpha_scissor_threshold = 0.4
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return _emitter(p, m, GRASS_SIZE, GRASS_AMOUNT, GRASS_LIFETIME)


## Dry leaves whirled up: light, tumbling, slow to settle (photos keep their own colours).
func _make_leaves() -> GPUParticles3D:
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3(0, 1.5, 1)
	p.spread = 45.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.inherit_velocity_ratio = 0.25
	p.gravity = Vector3(0, -2.0, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_min = 0.6
	p.scale_max = 1.0
	p.turbulence_enabled = true  # flutter
	p.turbulence_noise_strength = 2.0
	p.turbulence_noise_scale = 3.0
	p.turbulence_influence_min = 0.05
	p.turbulence_influence_max = 0.2
	p.color_ramp = _ramp([[0.0, Color.WHITE], [0.85, Color.WHITE], [1.0, Color(1, 1, 1, 0)]])
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(_width * 0.5, 0.02, 0.05)
	var m := _billboard("leaf", false, p)
	if m.particles_anim_h_frames <= 1:
		return null
	m.alpha_scissor_threshold = 0.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return _emitter(p, m, LEAF_SIZE, LEAF_AMOUNT, LEAF_LIFETIME)


# --- sparks ----------------------------------------------------------------------------------

func _on_impact(_kmh: float, point: Vector3, impulse: float) -> void:
	if impulse < SPARK_MIN_IMPULSE:
		return
	_spark_until = _time + SPARK_BURST
	_spark_ratio = clampf(impulse / SPARK_FULL_IMPULSE, 0.3, 1.0)
	_aim_sparks(point)


func _update_sparks(speed: float) -> void:
	var ratio := _spark_ratio if _time < _spark_until else 0.0
	if _car.damage != null and _car.damage.scrape > SPARK_SCRAPE_FROM and speed > SPARK_MIN_SPEED:
		var scrape := smoothstep(SPARK_SCRAPE_FROM, SPARK_SCRAPE_FULL, _car.damage.scrape) \
			* smoothstep(SPARK_MIN_SPEED, SPARK_MIN_SPEED + 10.0, speed)
		if scrape > ratio:
			ratio = scrape
			_aim_sparks(_car.damage.scrape_point)
	_sparks.emitting = ratio > 0.05
	_sparks.amount_ratio = maxf(ratio, 0.05)


## Puts the emitter at `point` (car space), up and outwards from the car's centre.
func _aim_sparks(point: Vector3) -> void:
	var out := Vector3(point.x, 0.0, point.z).normalized()
	var y := (out + Vector3.UP).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_sparks.global_transform = _car.global_transform * Transform3D(Basis(x, y, x.cross(y)), point)


func _make_sparks() -> GPUParticles3D:
	# The original's system: count and colours over life (white, then orange fading out).
	var count := 47
	var colors: Array = [Color.WHITE, Color(1.0, 0.6, 0.0, 0.0)]
	var data: Variant = OriginalAssets.load_json(PARTICLES) if OriginalAssets.exists(PARTICLES) else null
	if data is Dictionary:
		for s: Dictionary in data["systems"]:
			if s["tag"] == SPARKS_TAG:
				count = int(s["count"])
				colors = []
				for c: String in s["colors"]:
					colors.append(_argb(c))
				break
	# White when thrown, the second colour (fully opaque) soon after, fading out to its alpha.
	var first: Color = colors[0]
	var last: Color = colors[colors.size() - 1]
	var stops := [[0.0, first * SPARK_BRIGHTNESS], [0.25, Color(last, 1.0) * SPARK_BRIGHTNESS],
		[1.0, Color(last, 1.0) * SPARK_BRIGHTNESS]]
	for st: Array in stops:
		st[1].a = 1.0
	stops[2][1].a = last.a
	var p := ParticleProcessMaterial.new()
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.inherit_velocity_ratio = 0.6
	p.gravity = Vector3(0, -9.81, 0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.color_ramp = _ramp(stops, true)
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.1
	# Streaks: each spark draws a short ribbon along its path (crossed, seen from any side).
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.use_particle_trails = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ribbon := RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_CROSS
	ribbon.size = SPARK_WIDTH
	ribbon.sections = 4
	ribbon.section_length = 0.05
	ribbon.curve = _curve([Vector2(0, 0.2), Vector2(1, 1.0)]).curve
	ribbon.material = m
	var sparks := _emitter(p, m, 0.0, count * SPARK_COUNT_SCALE, SPARK_LIFETIME)
	sparks.draw_pass_1 = ribbon
	sparks.trail_enabled = true
	sparks.trail_lifetime = SPARK_TRAIL
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sparks


static func _argb(hex: String) -> Color:
	var v := hex.trim_prefix("#").hex_to_int()
	return Color8((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, (v >> 24) & 0xFF)


# --- shared ----------------------------------------------------------------------------------

## World-space emitter: particles stay where they were thrown while the car drives on.
func _emitter(p: ParticleProcessMaterial, m: StandardMaterial3D, size: float, amount: int, lifetime: float) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.process_material = p
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = m
	e.draw_pass_1 = quad
	e.amount = amount
	e.lifetime = lifetime
	e.local_coords = false
	e.emitting = false
	e.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 20, 60))
	return e


## Particle material; with `p`, the texture comes from the pack when it has `texture` (a random
## frame of the atlas per particle), else it is generated.
func _billboard(texture: String, glow: bool, p: ParticleProcessMaterial = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	var atlas := _pack_atlas(texture) if p != null and PACK.has(texture) else null
	if atlas != null:
		m.albedo_texture = atlas
		m.particles_anim_h_frames = PACK[texture].size()
		m.particles_anim_v_frames = 1
		m.particles_anim_loop = false
		p.anim_speed_min = 0.0
		p.anim_speed_max = 0.0
		p.anim_offset_min = 0.0
		p.anim_offset_max = 1.0
	else:
		m.albedo_texture = _texture(texture if texture in ["chip", "mark"] else "puff")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 1.0
	return m


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 4.0
	for pt: Vector2 in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _ramp(stops: Array, hdr := false) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for s: Array in stops:
		g.add_point(s[0], s[1])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = hdr
	return t


## The pack's files for `kind` side by side in one atlas row; null when a file is missing.
static func _pack_atlas(kind: String) -> Texture2D:
	var key := "pack_" + kind
	if _textures.has(key):
		return _textures[key]
	var files: Array = PACK[kind]
	var atlas := Image.create(PACK_FRAME * files.size(), PACK_FRAME, false, Image.FORMAT_RGBA8)
	for i in files.size():
		var path: String = PACK_DIR.path_join(files[i] + ".png")
		var img := Image.new()
		# Read as a plain PNG: the pack is not imported as Godot textures.
		if not FileAccess.file_exists(path) or img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			push_warning("Missing particle texture %s - generated texture used" % path)
			_textures[key] = null
			return null
		img.convert(Image.FORMAT_RGBA8)
		img.resize(PACK_FRAME, PACK_FRAME, Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(img, Rect2i(0, 0, PACK_FRAME, PACK_FRAME), Vector2i(PACK_FRAME * i, 0))
	atlas.generate_mipmaps()
	var tex := ImageTexture.create_from_image(atlas)
	_textures[key] = tex
	return tex


## Generated particle textures, white with alpha (tinted by the particle colour):
## puff (soft noisy cloud), chip (small hard blob), mark (tyre mark across its width: soft edges, tread streaks).
static func _texture(kind: String) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var size := 128 if kind != "chip" else 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.05 * 128.0 / size
	noise.fractal_octaves = 4
	var half := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var a := 0.0
			match kind:
				"puff":
					var n := 0.5 + 0.5 * noise.get_noise_2d(x, y)
					a = pow(clampf(1.0 - d, 0.0, 1.0), 1.5) * clampf(0.3 + n, 0.0, 1.0)
				"chip":
					a = 1.0 - smoothstep(0.55, 0.8, d + 0.15 * noise.get_noise_2d(x * 4.0, y * 4.0))
				"mark":
					var u := float(x) / (size - 1)
					var edge := smoothstep(0.0, 0.18, u) * smoothstep(1.0, 0.82, u)
					var tread := 0.8 + 0.2 * sin(u * TAU * 5.0)
					a = edge * tread * (0.85 + 0.15 * noise.get_noise_2d(x, y * 0.2))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[kind] = tex
	return tex
