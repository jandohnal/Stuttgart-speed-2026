extends Node3D
## Leaves falling from autumn tree crowns over and beside the road (D-028), simulated one by one so
## they land on the real ground, lie there a while and are whirled up by passing cars.
## - Crowns: at load, triangles of the track's see-through materials (crown cards; fences and
##   bushes are low, bridges opaque) in a colour that is not green (a green crown keeps its
##   leaves), at least CANOPY_MIN m above the road and within CANOPY_REACH m of its centre line,
##   filed under their nearest road slice.
## - Leaves start at a random point of a crown triangle along the road ahead of the player's car
##   (AHEAD m, following the road through bends), so they are already falling when the camera gets
##   there. A leaf out of the camera's view or far ahead may start part way down or already on the
##   ground; one the camera sees close starts at its crown.
## - A falling leaf sinks slowly, tumbles and sways; on the ground (found by a ray down past the
##   crowns) it lies flat for at least REST s, then goes once the camera no longer sees it.
## - Every car (player and opponents) moving through a leaf throws it up, along and out to the side,
##   lying or falling.
## Leaf photos as in CarEffects (assets/particles/leaves); without them there are no leaves.

const CarEffects := preload("res://scripts/car_effects.gd")

const MAX_LEAVES := 195
const SIZE := 0.2  ## m
const CANOPY_MIN := 4.0  ## m above the road
const CANOPY_REACH := 10.0  ## m from the road centre line
const AHEAD := 60.0  ## m of road ahead of the player's car where leaves start
const DROP_BEHIND := 15.0  ## m behind the car where an unseen leaf is dropped
const SPAWN_PER_FRAME := 4
const NEAR_VIEW := 45.0  ## m: a leaf the camera sees closer than this starts at its crown
const ON_GROUND_SHARE := 0.2  ## of the leaves started out of view: already lying
const FALL_SPEED := 1.95  ## m/s, a leaf's steady sinking
const GRAVITY := 5.0  ## m/s², light leaf
const AIR_DRAG := 1.5  ## 1/s, horizontal
const SWAY := 0.35  ## m
const REST := 4.0  ## s on the ground at least
const REST_MAX := 15.0  ## s on the ground at most, even in view
const LIFT := 0.02  ## m above the ground
const SHRINK := 0.4  ## s to vanish
const CAR_HALF := Vector3(1.0, 1.0, 2.3)  ## m, the box around a car that throws leaves
const CAR_WAKE := 2.5  ## m behind the car the box reaches further
const KICK_SPEED := 3.0  ## m/s of the car to stir leaves
const KICK_FULL := 25.0  ## m/s for the strongest throw
const RAY_TRIES := 6  ## crown layers a ground ray passes through

enum { FALLING, LYING, GONE }

var _road: Road
var _cars: Array[Car] = []
var _player: Car
var _canopy := {}  ## slice -> PackedVector3Array of crown triangles (3 points each)
var _slice := -1  ## player's slice
var _mm: MultiMesh
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _frames := 1
# Per leaf
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _ground := PackedVector3Array()  ## ground point under the leaf
var _normal := PackedVector3Array()  ## ground normal
var _axis := PackedVector3Array()  ## tumbling axis
var _sway := PackedVector3Array()  ## sway direction * amplitude
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()  ## s lying, or s shrinking when GONE
var _phase := PackedFloat32Array()
var _spin := PackedFloat32Array()  ## rad/s
var _frame := PackedFloat32Array()  ## atlas frame
var _cool := PackedFloat32Array()  ## s before the next throw
var kicks := 0  ## leaves thrown by cars so far (tests)


func setup(road: Road, track: Node3D, player: Car, cars: Array[Car]) -> void:
	_road = road
	_player = player
	_cars = cars
	_rng.seed = 5
	var atlas := CarEffects._pack_atlas("leaf")
	if atlas == null or road == null or road.size() == 0:
		return
	_frames = CarEffects.PACK["leaf"].size()
	var triangles := _collect_canopy(track)
	if _canopy.is_empty():
		return
	print("FallingLeaves: %d crown triangles over %d slices" % [triangles, _canopy.size()])
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(SIZE, SIZE)
	_mm.mesh = quad
	_mm.instance_count = MAX_LEAVES
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.material_override = _material(atlas)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY


## Leaves now: {falling, lying, in_view (closer than NEAR_VIEW)} (tests).
func counts() -> Dictionary:
	var c := {"falling": 0, "lying": 0}
	for s in _state:
		if s == FALLING:
			c["falling"] += 1
		elif s == LYING:
			c["lying"] += 1
	var camera := get_viewport().get_camera_3d()
	c["in_view"] = 0
	for i in _pos.size():
		if camera != null and camera.is_position_in_frustum(_pos[i]) and camera.global_position.distance_to(_pos[i]) < NEAR_VIEW:
			c["in_view"] += 1
	return c


# --- crowns ----------------------------------------------------------------------------------

func _collect_canopy(track: Node3D) -> int:
	if track == null:
		return 0
	# Slices in a coarse grid for the nearest-slice lookup.
	var cell := 20.0
	var grid := {}
	for i in _road.size():
		var p := _road.positions[i]
		var key := Vector2i(floori(p.x / cell), floori(p.z / cell))
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		grid[key].append(i)
	var count := 0
	for group in ["terrain", "objects", "drivethrough"]:
		var root := track.find_child(group, true, false)
		if root == null:
			continue
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null:
				continue
			var xf := mesh.global_transform
			for s in mesh.mesh.get_surface_count():
				if not _autumn_crown(mesh.get_active_material(s)):
					continue
				var arrays := mesh.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var n := indices.size() if not indices.is_empty() else verts.size()
				for t in range(0, n - 2, 3):
					var a := xf * verts[indices[t] if not indices.is_empty() else t]
					var b := xf * verts[indices[t + 1] if not indices.is_empty() else t + 1]
					var c := xf * verts[indices[t + 2] if not indices.is_empty() else t + 2]
					var centre := (a + b + c) / 3.0
					var slice := _nearest_in_grid(grid, cell, centre)
					if slice < 0:
						continue
					var road_p := _road.positions[slice]
					var flat := Vector2(centre.x - road_p.x, centre.z - road_p.z)
					if flat.length() > CANOPY_REACH or centre.y - road_p.y < CANOPY_MIN:
						continue
					if not _canopy.has(slice):
						_canopy[slice] = PackedVector3Array()
					_canopy[slice].append_array([a, b, c])
					count += 1
	return count


static func _autumn_crown(material: Material) -> bool:
	if not (material is BaseMaterial3D) or (material as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	var c := CarEffects.Materials.average_color(material)
	return not (c.h >= CarEffects.GRASS_HUE.x and c.h <= CarEffects.GRASS_HUE.y and c.s >= CarEffects.GRASS_MIN_SATURATION)


func _nearest_in_grid(grid: Dictionary, cell: float, p: Vector3) -> int:
	var key := Vector2i(floori(p.x / cell), floori(p.z / cell))
	var best := -1
	var best_d := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var list: PackedInt32Array = grid.get(key + Vector2i(dx, dz), PackedInt32Array())
			for i in list:
				var q := _road.positions[i]
				var d := Vector2(p.x - q.x, p.z - q.z).length_squared()
				if d < best_d:
					best_d = d
					best = i
	return best


# --- simulation ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _mm == null or _player == null:
		return
	_time += delta
	_slice = _road.nearest(_player.global_position) if _slice < 0 else _road.nearest_ahead(_player.global_position, _slice, 40)
	var camera := get_viewport().get_camera_3d()
	var window := _window()
	for k in SPAWN_PER_FRAME:
		if _pos.size() >= MAX_LEAVES or window.is_empty():
			break
		_spawn(window[_rng.randi() % window.size()], camera)
	_kick_by_cars()
	var i := 0
	while i < _pos.size():
		if _step(i, delta, camera):
			i += 1
		else:
			_remove(i)
	_upload()


## Slices with crowns from the player's car to AHEAD m ahead along the road.
func _window() -> Array:
	var out := []
	var i := _slice
	var dist := 0.0
	var last := _road.positions[i]
	for n in 400:
		if _canopy.has(i):
			out.append(i)
		var j := _road.ahead(i, 1)
		if j == i:
			break
		dist += _road.positions[j].distance_to(last)
		last = _road.positions[j]
		i = j
		if dist > AHEAD:
			break
	return out


func _spawn(slice: int, camera: Camera3D) -> void:
	var tris: PackedVector3Array = _canopy[slice]
	var t := _rng.randi() % (tris.size() / 3) * 3
	var u := _rng.randf()
	var v := _rng.randf()
	if u + v > 1.0:
		u = 1.0 - u
		v = 1.0 - v
	var start := tris[t] + (tris[t + 1] - tris[t]) * u + (tris[t + 2] - tris[t]) * v
	var hit := _ground_below(start + Vector3.DOWN * 0.1)
	if hit.is_empty():
		return
	var ground: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var state := FALLING
	var pos := start
	var seen := camera != null and camera.is_position_in_frustum(ground) \
		and camera.global_position.distance_to(ground) < NEAR_VIEW
	if not seen:
		if _rng.randf() < ON_GROUND_SHARE:
			state = LYING
			pos = ground + normal * LIFT
		else:
			pos.y = lerpf(ground.y + 0.5, start.y, pow(_rng.randf(), 2.0))  # more of them low, in view
	_pos.append(pos)
	_vel.append(Vector3(0, -FALL_SPEED, 0))
	_ground.append(ground)
	_normal.append(normal)
	_axis.append(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized())
	var a := _rng.randf() * TAU
	_sway.append(Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.5, 1.0) * SWAY)
	_state.append(state)
	_timer.append(_rng.randf() * REST if state == LYING else 0.0)
	_phase.append(_rng.randf() * TAU)
	_spin.append(_rng.randf_range(1.5, 4.0) * (1.0 if _rng.randf() < 0.5 else -1.0))
	_frame.append(float(_rng.randi() % _frames))
	_cool.append(0.0)


## Ground under `from`: the first hit that is not a crown card or a car; {} when none.
func _ground_below(from: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for c in _cars:
		if is_instance_valid(c):
			exclude.append(c.get_rid())
	var top := from
	for k in RAY_TRIES:
		var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 80.0)
		q.exclude = exclude
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var g := CarEffects.ground_under(hit["collider"], hit.get("face_index", -1))
		if not g.get("alpha", false):
			if hit["normal"].y < 0.0:
				hit["normal"] = -hit["normal"]
			return hit
		top = hit["position"] + Vector3.DOWN * 0.05
	return {}


## Advances leaf i; false when it is to be removed.
func _step(i: int, delta: float, camera: Camera3D) -> bool:
	_cool[i] = maxf(_cool[i] - delta, 0.0)
	var state := _state[i]
	if state == GONE:
		_timer[i] += delta
		return _timer[i] < SHRINK
	var pos := _pos[i]
	var seen := camera != null and camera.is_position_in_frustum(pos)
	var to_leaf := pos - _player.global_position
	var behind := to_leaf.dot(-_player.global_basis.z) < -DROP_BEHIND
	if behind and not seen:
		return false
	if state == LYING:
		_timer[i] += delta
		if _timer[i] > REST_MAX or (_timer[i] > REST and not seen):
			_state[i] = GONE
			_timer[i] = 0.0
		return true
	var vel := _vel[i]
	vel.y -= GRAVITY * delta
	if vel.y < -FALL_SPEED:
		vel.y = move_toward(vel.y, -FALL_SPEED, 8.0 * delta)
	var drag := exp(-AIR_DRAG * delta)
	vel.x *= drag
	vel.z *= drag
	pos += vel * delta
	# Thrown away from where it would land: find the ground under it again.
	if Vector2(pos.x - _ground[i].x, pos.z - _ground[i].z).length() > 1.5 and vel.y < 0.0 and pos.y - _ground[i].y < 3.0:
		var hit := _ground_below(Vector3(pos.x, pos.y + 2.0, pos.z))
		if not hit.is_empty():
			_ground[i] = hit["position"]
			_normal[i] = hit["normal"]
		else:
			_ground[i] = Vector3(pos.x, _ground[i].y, pos.z)
	var floor_y := _floor_at(i, pos)
	if pos.y <= floor_y and vel.y <= 0.0:
		pos.y = floor_y
		vel = Vector3.ZERO
		_state[i] = LYING
		_timer[i] = 0.0
	_pos[i] = pos
	_vel[i] = vel
	return true


## Height of the ground plane under leaf i at `pos` (plus the lift).
func _floor_at(i: int, pos: Vector3) -> float:
	var n := _normal[i]
	var g := _ground[i]
	if absf(n.y) < 0.2:
		return g.y + LIFT
	return g.y - (n.x * (pos.x - g.x) + n.z * (pos.z - g.z)) / n.y + LIFT


func _kick_by_cars() -> void:
	for car in _cars:
		if not is_instance_valid(car):
			continue
		var v := car.linear_velocity
		var speed := v.length()
		if speed < KICK_SPEED or car.global_position.distance_to(_player.global_position) > AHEAD + 30.0:
			continue
		var inv := car.global_transform.affine_inverse()
		var reach := CAR_HALF.length() + CAR_WAKE
		var strength := clampf(speed / KICK_FULL, 0.2, 1.5)
		for i in _pos.size():
			if _state[i] == GONE or _cool[i] > 0.0:
				continue
			if _pos[i].distance_squared_to(car.global_position) > reach * reach:
				continue
			var local := inv * _pos[i]
			# The car's front is -Z; the wake reaches further behind (+Z).
			if absf(local.x) > CAR_HALF.x or local.y > CAR_HALF.y or local.z < -CAR_HALF.z or local.z > CAR_HALF.z + CAR_WAKE:
				continue
			var side := car.global_basis.x * (1.0 if local.x >= 0.0 else -1.0)
			var wake := 1.0 - clampf((local.z - CAR_HALF.z) / CAR_WAKE, 0.0, 1.0) * 0.6
			_vel[i] = v * _rng.randf_range(0.3, 0.7) * wake \
				+ Vector3.UP * _rng.randf_range(1.5, 4.0) * strength * wake \
				+ side * _rng.randf_range(0.5, 2.5) * strength * wake
			_state[i] = FALLING
			_timer[i] = 0.0
			_cool[i] = 0.4
			_spin[i] = _rng.randf_range(6.0, 12.0) * signf(_spin[i])
			kicks += 1


func _remove(i: int) -> void:
	for a: Variant in [_pos, _vel, _ground, _normal, _axis, _sway, _state, _timer, _phase, _spin, _frame, _cool]:
		var last: int = a.size() - 1
		a[i] = a[last]
		a.resize(last)


# --- drawing ---------------------------------------------------------------------------------

func _upload() -> void:
	var n := _pos.size()
	var buf := PackedFloat32Array()
	buf.resize(MAX_LEAVES * 16)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in n:
		var b: Basis
		var p := _pos[i]
		var scale := 1.0
		if _state[i] == FALLING:
			b = Basis(_axis[i], _phase[i] + _time * _spin[i])
			# Sways while it sinks, less near the ground so it lands where it is drawn.
			var height := clampf((p.y - _floor_at(i, p)) / 1.0, 0.0, 1.0)
			p += _sway[i] * sin(_time * 1.7 + _phase[i]) * height
			_spin[i] = move_toward(_spin[i], signf(_spin[i]) * 2.5, 4.0 * get_physics_process_delta_time())
		else:
			# Flat on the ground, the quad's face (+Z) along the normal.
			var nz := _normal[i]
			var nx := nz.cross(Vector3.FORWARD if absf(nz.z) < 0.9 else Vector3.RIGHT).normalized().rotated(nz, _phase[i])
			b = Basis(nx, nz.cross(nx), nz)
			if _state[i] == GONE:
				scale = 1.0 - clampf(_timer[i] / SHRINK, 0.0, 1.0)
		b = b.scaled(Vector3.ONE * scale)
		var o := i * 16
		buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = p.x
		buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = p.y
		buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = p.z
		buf[o + 12] = _frame[i]
		lo = lo.min(p)
		hi = hi.max(p)
	_mm.buffer = buf
	_mm.visible_instance_count = n
	if n > 0:
		_mm.custom_aabb = AABB(lo - Vector3.ONE, hi - lo + Vector3.ONE * 2.0)


func _material(atlas: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float frames = 1.0;
varying float frame;
void vertex() {
	frame = INSTANCE_CUSTOM.x;
}
void fragment() {
	vec4 c = texture(atlas, vec2((UV.x + frame) / frames, UV.y));
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	BACKLIGHT = vec3(0.7) * c.rgb;  // thin leaf: light through it, not a dark back
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("atlas", atlas)
	m.set_shader_parameter("frames", float(_frames))
	return m
