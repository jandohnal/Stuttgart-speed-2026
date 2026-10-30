extends RefCounted
## Car damage from the original's damage zones (<car>_damage.json from tools/crp2gltf.py).
## The body's contact impulses are summed over the first `window` ticks of an impact; the next
## impact counts once the body has come off the obstacle (no resting or scraping contact adds up).
## Like the original, an impact is measured by its speed: the car's speed change (impulse / mass,
## contacts with another car count `car_factor` times). From `threshold_kmh` up it dents one zone by
## speed / `full_kmh`, chosen like the original by the impact's direction (zone_hit()); the two ring
## zones beside it get at least the average of their neighbours. A zone keeps its hardest impact like
## the original (maximum) and smaller ones still add `accumulate` of their damage. Each zone's damage (0..1)
## drives the blend shape "dz<zone>" on every part of the model (the original's offsets for a
## fully damaged car). Car reads the zone values for the mechanical consequences.
## Detachable parts (from the json) come off as loose bodies once their zone is fully damaged.
## Hood, engine lid and doors first come unlatched and swing on their hinges (a rigid body on a
## HingeJoint3D): the hood when the front is damaged over `unlatch_damage` or hit at
## `unlatch_speed_kmh`, the engine lid likewise at the rear, the doors when either end is. An impact
## at `tear_speed_kmh` tears the hood (front) or engine lid (rear) off. Both speeds are for the
## 356 A and scale with the car's top speed (`speed_factor`). With `enabled` off (past the finish
## line, like the original) impacts still sound but damage nothing. repair() puts everything back.

const TrackProps := preload("res://scripts/track_props.gd")

signal impacted(kmh: float, point: Vector3, impulse: float)  ## every resolved impact, point in car space
signal part_changed(kind: String, state: String, point: Vector3)  ## a part came loose ("hinged") or off
const ZONE_COUNT := 10
const CORNER_ZONES := [0, 2, 4, 6]  ## front left, front right, rear right, rear left
const RING := 8  ## zones 0..7 go round the car: FL, front, FR, right, RR, rear, RL, left
const ROOF := 8
const BOTTOM := 9

var threshold_kmh := 24.0  ## speed change of one impact below which nothing dents (the original's threshold)
var full_kmh := 240.0  ## speed change that fully damages the zone hit (the original into a wall)
var accumulate := 0.3  ## share of a smaller impact's damage that still adds to a zone (0 = the original's maximum)
var car_factor := 2.0  ## contacts with another car: closing speed is about twice each car's speed change
var straight := 0.1  ## impact direction across (or along) the car below this counts as straight on (the original's sectors)
var underside_factor := 0.2  ## impacts from below (bottoming out) dent the bottom zone less; the original never dents it
var log_impacts := false  ## print every resolved impact (tests, tuning)
var tick_min := 30.0  ## N*s in one tick that still counts as contact
var window := 12  ## physics ticks (0.1 s at 120 Hz) summed per impact
var unlatch_damage := 0.5  ## front / rear damage that unlatches the hood, engine lid and doors
var unlatch_speed_kmh := 80.0  ## impact speed (along the contact normal) that unlatches them at once (356 A)
var tear_speed_kmh := 130.0  ## impact speed that tears the hood or engine lid off (356 A)
var speed_factor := 1.0  ## car's top speed / the 356 A 1.6's (100 mph): scales the two speeds above
var enabled := true  ## off past the finish line: nothing dents or comes loose any more
var last_impact_kmh := 0.0
var scrape := 0.0  ## N*s of body contact in the last tick (scraping, resting)
var scrape_point := Vector3.ZERO  ## car-space centre of that contact (sparks)

var zone_damage := PackedFloat32Array()
var centroids: Array[Vector3] = []  ## per zone id, car space (Vector3.INF where unknown)
var names: Array[String] = []
var impacts := 0
var last_impact := 0.0  ## N*s of the last impact that dented something
var last_impact_dv := 0.0  ## km/h, speed change of the last resolved impact (car contacts weighted)

## {group, kind, zone, mass, nodes, parents, xforms, bounds (car space), state on|hinged|off, body, joint}
var parts: Array[Dictionary] = []
var _car: RigidBody3D
var _meshes: Array[MeshInstance3D] = []
var _sum := 0.0
var _dv := 0.0  ## m/s, speed change of the current impact (car contacts weighted)
var _point := Vector3.ZERO
var _normal := Vector3.ZERO
var _ticks := 0
var _blocked := false  ## impact resolved, still in contact
var _impact_speed := 0.0  ## m/s along the normal when the current impact began
var _prev_velocity := Vector3.ZERO  ## car space, last tick: the speed just before an impact

const STATE_RANK := {"on": 0, "hinged": 1, "off": 2}
## Maximum opening per kind. 356: hood (front luggage lid) hinged at its rear edge, engine lid at
## its top edge, doors at their front edge.
const OPEN_DEG := {"hood": 80.0, "engine_lid": 70.0, "door": 70.0}


func _init(car: RigidBody3D, model: Node3D, info: Dictionary) -> void:
	_car = car
	var zones: Array = info.get("zones", [])
	zone_damage.resize(ZONE_COUNT)
	for i in ZONE_COUNT:
		centroids.append(Vector3.INF)
		names.append("zone%d" % i)
	for zone_info: Dictionary in zones:
		var z := int(zone_info["zone"])
		if z >= 0 and z < ZONE_COUNT:
			var c: Array = zone_info["centroid"]
			centroids[z] = Vector3(c[0], c[1], c[2])
			names[z] = str(zone_info.get("name", names[z]))
	if model != null:
		for entry: Dictionary in info.get("detachable", []):
			var nodes: Array[Node3D] = []
			for node_name: String in entry["nodes"]:
				var node := model.find_child(node_name, true, false) as Node3D
				if node != null:
					nodes.append(node)
			if not nodes.is_empty() and int(entry["zone"]) >= 0:
				parts.append({"group": entry["group"], "kind": str(entry.get("kind", "")), "zone": int(entry["zone"]),
					"mass": float(entry["mass_kg"]), "nodes": nodes, "parents": [], "xforms": [],
					"bounds": _bounds(nodes), "state": "on", "body": null, "joint": null})
		for child in model.find_children("*", "MeshInstance3D", true, false):
			if (child as MeshInstance3D).mesh != null and (child as MeshInstance3D).mesh.get_blend_shape_count() > 0:
				_meshes.append(child as MeshInstance3D)


## Feeds one physics tick of body contacts: [{point, normal, impulse, car}] in car space
## (car: the contact is with another car).
func add_tick(contacts: Array) -> void:
	var tick := 0.0
	var weighted := 0.0
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	for c: Dictionary in contacts:
		var impulse: float = c["impulse"]
		tick += impulse
		weighted += impulse * (car_factor if c.get("car", false) else 1.0)
		point += c["point"] * impulse
		normal += c["normal"] * impulse
	scrape = tick
	if tick > 0.0:
		scrape_point = point / tick
	var velocity := _car.global_basis.inverse() * _car.linear_velocity
	var before := _prev_velocity
	_prev_velocity = velocity
	if tick < tick_min:
		if _sum > 0.0:
			_resolve()
		_blocked = false
		return
	if _blocked:
		return
	if _sum == 0.0:  # the impact begins: how fast did we hit (normal points from the obstacle into the car)?
		_impact_speed = maxf(0.0, -before.dot(normal.normalized()))
	_sum += tick
	_dv += weighted / _car.mass
	_point += point
	_normal += normal
	_ticks += 1
	if _ticks >= window:
		_resolve()
		_blocked = true


func repair() -> void:
	for z in ZONE_COUNT:
		zone_damage[z] = 0.0
	for part in parts:
		part["pending"] = ""
		var body: RigidBody3D = part["body"]
		if body == null:
			continue
		if part["joint"] != null:
			(part["joint"] as Node).queue_free()
		for i in part["nodes"].size():
			var node: Node3D = part["nodes"][i]
			node.reparent(part["parents"][i], false)
			node.transform = part["xforms"][i]
		body.queue_free()
		part["body"] = null
		part["joint"] = null
		part["state"] = "on"
		part["parents"] = []
		part["xforms"] = []
	_apply_visuals()


func detached_count() -> int:
	return parts.filter(func(p: Dictionary) -> bool: return p["state"] == "off").size()


func hinged_count() -> int:
	return parts.filter(func(p: Dictionary) -> bool: return p["state"] == "hinged").size()


## How far a swinging part has opened (deg, positive = open), or -1 when it is not swinging.
func opening_deg(group: String) -> float:
	for part in parts:
		if part["group"] == group and part["state"] == "hinged":
			var axis: Vector3 = part["hinge_axis"]  # car space
			var rest: Basis = part["rest_basis"]  # part basis in car space when it came loose
			var now := (_car.global_basis.inverse() * (part["body"] as Node3D).global_basis) * rest.inverse()
			var q := now.get_rotation_quaternion()
			return rad_to_deg(q.get_angle()) * signf(q.get_axis().dot(axis))
	return -1.0


## Turns the given nodes of the car into one loose rigid body thrown off with the car's motion.
## shape: collision for the body (body space); null = hull of the nodes' meshes.
static func make_debris(car: RigidBody3D, nodes: Array, mass: float, shape: CollisionShape3D = null,
		throw := true) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	body.continuous_cd = true
	var first: Node3D = nodes[0]
	var origin := first.global_transform
	car.get_parent().add_child(body)
	body.global_transform = Transform3D(origin.basis.orthonormalized(), origin.origin)
	var points := PackedVector3Array()
	for node: Node3D in nodes:
		node.reparent(body, true)
		var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		for mi: MeshInstance3D in meshes:
			var to_body := body.global_transform.affine_inverse() * mi.global_transform
			for surface in mi.mesh.get_surface_count():
				for p: Vector3 in mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					points.append(to_body * p)
	body.add_child(shape if shape != null else TrackProps.collision_for(points))
	body.add_collision_exception_with(car)  # it starts inside the car's hull
	var r := body.global_position - car.global_position
	body.linear_velocity = car.linear_velocity + car.angular_velocity.cross(r)
	body.angular_velocity = car.angular_velocity
	if throw:
		_throw(car, body)
	return body


static func _throw(car: RigidBody3D, body: RigidBody3D) -> void:
	var r := body.global_position - car.global_position
	body.linear_velocity += Vector3(r.x, 0.0, r.z).normalized() * 1.5 + Vector3.UP


func zone(z: int) -> float:
	return zone_damage[z] if z >= 0 and z < ZONE_COUNT else 0.0


func total() -> float:
	var s := 0.0
	for d in zone_damage:
		s += d
	return s / ZONE_COUNT


## The corner zone nearest to a wheel position (car space).
func corner_of(position: Vector3) -> int:
	var best := -1
	var best_d := INF
	for z: int in CORNER_ZONES:
		if centroids[z] == Vector3.INF:
			continue
		var d := Vector2(centroids[z].x - position.x, centroids[z].z - position.z).length()
		if d < best_d:
			best_d = d
			best = z
	return best


func _resolve() -> void:
	var point := _point / _sum
	var normal := _normal.normalized()
	var hit := zone_hit(normal)
	var dv := _dv * 3.6
	if hit == BOTTOM:
		dv *= underside_factor
	var amount := dv / full_kmh if dv >= threshold_kmh else 0.0
	if log_impacts:
		print("  impact: %.0f N*s over %d ticks at %s, normal %s, %.0f km/h, speed change %.0f km/h -> %s %.2f%s" % [
			_sum, _ticks, point.snapped(Vector3.ONE * 0.01), normal.snapped(Vector3.ONE * 0.01),
			_impact_speed * 3.6, dv, names[hit], amount, "" if enabled else " (damage off)"])
	last_impact_kmh = _impact_speed * 3.6
	last_impact_dv = dv
	impacted.emit.call_deferred(last_impact_kmh, point, _sum)  # we are inside the physics callback
	var end := "front" if point.z < 0.0 else "rear"
	var hard := end if last_impact_kmh >= tear_speed_kmh * speed_factor else ""
	var knock := end if last_impact_kmh >= unlatch_speed_kmh * speed_factor else ""
	if enabled and amount > 0.0:
		_dent(hit, amount, hard, knock)
		impacts += 1
		last_impact = _sum
	elif enabled and knock != "":
		_check_parts(hard, knock)
	_sum = 0.0
	_dv = 0.0
	_point = Vector3.ZERO
	_normal = Vector3.ZERO
	_ticks = 0


func _dent(hit: int, amount: float, hard := "", knock := "") -> void:
	var old := zone_damage[hit]
	zone_damage[hit] = minf(1.0, maxf(old, amount) + accumulate * minf(old, amount))
	if hit < RING:
		# Like the original: each ring zone beside the one hit gets at least the average of its
		# own two neighbours.
		for side: int in [(hit + RING - 1) % RING, (hit + 1) % RING]:
			var around := (zone_damage[(side + RING - 1) % RING] + zone_damage[(side + 1) % RING]) / 2.0
			zone_damage[side] = maxf(zone_damage[side], around)
	_apply_visuals()
	_check_parts(hard, knock)


## The zone an impact dents, from its direction like the original (not from where it touched):
## 8 sectors round the car, the roof when it comes from above, the bottom from below.
## normal: car space, from the obstacle into the car.
func zone_hit(normal: Vector3) -> int:
	var d := -normal.normalized()  # from the car towards the obstacle; the car faces -Z
	if d.y > 0.5:
		return ROOF
	if d.y < -0.7:
		return BOTTOM
	var lon := 0 if d.z < -straight else (2 if d.z > straight else 1)  # front, middle, rear
	var lat := 0 if d.x < -straight else (2 if d.x > straight else 1)  # left, centre, right
	return [[0, 1, 2], [7, ROOF, 3], [6, 5, 4]][lon][lat]


## Sets a zone's damage directly (tests, debugging); hard = "front" / "rear" simulates a hard impact.
func set_damage(z: int, value: float, hard := "") -> void:
	zone_damage[z] = clampf(value, 0.0, 1.0)
	_apply_visuals()
	_check_parts(hard, hard)


## Decides what each part should do; hard = "front" / "rear" after an impact at that end fast
## enough to tear a lid off, knock = one fast enough to unlatch the lids and doors.
func _check_parts(hard := "", knock := "") -> void:
	var front := maxf(zone(1), maxf(zone(0), zone(2)))
	var rear := maxf(zone(5), maxf(zone(4), zone(6)))
	for part in parts:
		var want := "on"
		match part["kind"]:
			"hood", "engine_lid":
				var end := "front" if part["kind"] == "hood" else "rear"
				if hard == end:
					want = "off"
				elif knock == end or (front if end == "front" else rear) > unlatch_damage:
					want = "hinged"
			"door":
				if zone_damage[part["zone"]] >= 1.0:
					want = "off"
				elif front > unlatch_damage or rear > unlatch_damage or knock != "":
					want = "hinged"
			_:
				if zone_damage[part["zone"]] >= 1.0:
					want = "off"
		var pending: String = part.get("pending", "")
		var current: String = pending if pending != "" else part["state"]
		if STATE_RANK[want] > STATE_RANK[current]:
			part["pending"] = want
			_change.call_deferred(part)  # we may be inside the physics callback


func _change(part: Dictionary) -> void:
	var want: String = part.get("pending", "")
	part["pending"] = ""
	if want == "" or STATE_RANK[want] <= STATE_RANK[part["state"]]:
		return  # repaired in the meantime
	if part["state"] == "on":
		for node: Node3D in part["nodes"]:
			part["parents"].append(node.get_parent())
			part["xforms"].append(node.transform)
		part["body"] = make_debris(_car, part["nodes"], part["mass"], null, want == "off")
		if want == "hinged":
			_hinge(part)
	elif want == "off":  # hinged -> torn off
		(part["joint"] as Node).queue_free()
		part["joint"] = null
		_throw(_car, part["body"])
	part["state"] = want
	part_changed.emit(part["kind"], want, (part["bounds"] as AABB).get_center())


## Holds a loose part on its hinges: a HingeJoint3D (rotation about its Z axis) between car and part.
func _hinge(part: Dictionary) -> void:
	var b: AABB = part["bounds"]
	var c := b.get_center()
	var point: Vector3
	var axis: Vector3
	match part["kind"]:
		"hood":  # rear edge at the windscreen, the front edge lifts
			point = Vector3(c.x, b.end.y, b.end.z)
			axis = Vector3.RIGHT
		"engine_lid":  # top edge at the rear window, the lower edge lifts
			point = Vector3(c.x, b.end.y, b.position.z)
			axis = Vector3.LEFT
		_:  # door: front edge at the A pillar, the rear edge swings out
			var left := c.x < 0.0
			point = Vector3(b.position.x if left else b.end.x, c.y, b.position.z)
			axis = Vector3.DOWN if left else Vector3.UP
	var x := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.UP).normalized()
	var joint := HingeJoint3D.new()
	_car.get_parent().add_child(joint)
	joint.global_transform = _car.global_transform * Transform3D(Basis(x, axis.cross(x), axis), point)
	# The joint's angle runs opposite to `axis` (checked: gravity pulls the hood to positive joint
	# angles, into the body): closed is the upper stop, opening goes negative.
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -deg_to_rad(OPEN_DEG.get(part["kind"], 70.0)))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, 0.0)
	joint.node_a = joint.get_path_to(_car)
	joint.node_b = joint.get_path_to(part["body"])
	part["joint"] = joint
	part["hinge_axis"] = axis
	part["rest_basis"] = _car.global_basis.inverse() * (part["body"] as Node3D).global_basis


## Bounds of the given nodes' meshes in car space.
func _bounds(nodes: Array[Node3D]) -> AABB:
	var points := PackedVector3Array()
	var to_car := _car.global_transform.affine_inverse()
	for node in nodes:
		var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		for mi: MeshInstance3D in meshes:
			var box := (to_car * mi.global_transform) * mi.get_aabb()
			for i in 8:
				points.append(box.get_endpoint(i))
	return TrackProps.bounds_of(points)


func _apply_visuals() -> void:
	for mi in _meshes:
		for z in ZONE_COUNT:
			var i := mi.find_blend_shape_by_name("dz%d" % z)
			if i >= 0:
				mi.set_blend_shape_value(i, zone_damage[z])
