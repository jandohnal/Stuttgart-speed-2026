extends RefCounted
## Car damage from the original's damage zones (<car>_damage.json from tools/crp2gltf.py).
## The body's contact impulses are summed over the first `window` ticks of an impact; the next
## impact counts once the body has come off the obstacle (no resting or scraping contact adds up);
## an impact above `threshold` dents the zones near its contact point. Each zone's damage (0..1)
## drives the blend shape "dz<zone>" on every part of the model (the original's offsets for a
## fully damaged car). Car reads the zone values for the mechanical consequences.
## Detachable parts (hood, doors, lights ... from the json) come off as loose bodies once their
## zone is fully damaged; repair() puts everything back.

const TrackProps := preload("res://scripts/track_props.gd")
const ZONE_COUNT := 10
const CORNER_ZONES := [0, 2, 4, 6]  ## front left, front right, rear right, rear left

var threshold := 1500.0  ## N*s summed over one impact; below it nothing dents (light signs, scrapes)
var scale := 15000.0  ## N*s above the threshold for a fully damaged zone
var spread := 1.5  ## m, zones closer than this to the contact point are dented too (the nearest fully)
var underside_factor := 0.2  ## contacts from below (landing, bottoming out) dent less
var log_impacts := false  ## print every resolved impact (tests, tuning)
var tick_min := 30.0  ## N*s in one tick that still counts as contact
var window := 12  ## physics ticks (0.1 s at 120 Hz) summed per impact

var zone_damage := PackedFloat32Array()
var centroids: Array[Vector3] = []  ## per zone id, car space (Vector3.INF where unknown)
var names: Array[String] = []
var impacts := 0
var last_impact := 0.0  ## N*s of the last impact that dented something

var parts: Array[Dictionary] = []  ## {group, zone, mass, nodes, parents, xforms, body}
var _car: RigidBody3D
var _meshes: Array[MeshInstance3D] = []
var _sum := 0.0
var _point := Vector3.ZERO
var _normal := Vector3.ZERO
var _ticks := 0
var _blocked := false  ## impact resolved, still in contact


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
				parts.append({"group": entry["group"], "zone": int(entry["zone"]), "mass": float(entry["mass_kg"]),
					"nodes": nodes, "parents": [], "xforms": [], "body": null})
		for child in model.find_children("*", "MeshInstance3D", true, false):
			if (child as MeshInstance3D).mesh != null and (child as MeshInstance3D).mesh.get_blend_shape_count() > 0:
				_meshes.append(child as MeshInstance3D)


## Feeds one physics tick of body contacts: [{point, normal, impulse}] in car space.
func add_tick(contacts: Array) -> void:
	var tick := 0.0
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	for c: Dictionary in contacts:
		var impulse: float = c["impulse"]
		tick += impulse
		point += c["point"] * impulse
		normal += c["normal"] * impulse
	if tick < tick_min:
		if _sum > 0.0:
			_resolve()
		_blocked = false
		return
	if _blocked:
		return
	_sum += tick
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
		var body: RigidBody3D = part["body"]
		if body == null:
			continue
		for i in part["nodes"].size():
			var node: Node3D = part["nodes"][i]
			node.reparent(part["parents"][i], false)
			node.transform = part["xforms"][i]
		body.queue_free()
		part["body"] = null
		part["parents"] = []
		part["xforms"] = []
	_apply_visuals()


func detached_count() -> int:
	return parts.filter(func(p: Dictionary) -> bool: return p["body"] != null).size()


## Turns the given nodes of the car into one loose rigid body thrown off with the car's motion.
## shape: collision for the body (body space); null = hull of the nodes' meshes.
static func make_debris(car: RigidBody3D, nodes: Array, mass: float, shape: CollisionShape3D = null) -> RigidBody3D:
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
	var out := Vector3(r.x, 0.0, r.z).normalized()
	body.linear_velocity = car.linear_velocity + car.angular_velocity.cross(r) + out * 1.5 + Vector3.UP
	body.angular_velocity = car.angular_velocity
	return body


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
	var amount := (_sum - threshold) / scale
	if normal.y > 0.7:
		amount = (_sum * underside_factor - threshold) / scale
	if log_impacts:
		print("  impact: %.0f N*s over %d ticks at %s, normal %s -> %.2f" % [
			_sum, _ticks, point.snapped(Vector3.ONE * 0.01), normal.snapped(Vector3.ONE * 0.01), maxf(amount, 0.0)])
	if amount > 0.0:
		_dent(point, amount)
		impacts += 1
		last_impact = _sum
	_sum = 0.0
	_point = Vector3.ZERO
	_normal = Vector3.ZERO
	_ticks = 0


func _dent(point: Vector3, amount: float) -> void:
	var weights := PackedFloat32Array()
	weights.resize(ZONE_COUNT)
	var max_w := 0.0
	var nearest := -1
	var nearest_d := INF
	for z in ZONE_COUNT:
		if centroids[z] == Vector3.INF:
			continue
		var d := centroids[z].distance_to(point)
		weights[z] = maxf(0.0, 1.0 - d / spread)
		max_w = maxf(max_w, weights[z])
		if d < nearest_d:
			nearest_d = d
			nearest = z
	if max_w <= 0.0:
		weights[nearest] = 1.0
		max_w = 1.0
	for z in ZONE_COUNT:
		zone_damage[z] = minf(1.0, zone_damage[z] + amount * weights[z] / max_w)
	_apply_visuals()
	_check_parts()


## Sets a zone's damage directly (tests, debugging).
func set_damage(z: int, value: float) -> void:
	zone_damage[z] = clampf(value, 0.0, 1.0)
	_apply_visuals()
	_check_parts()


func _check_parts() -> void:
	for part in parts:
		if part["body"] == null and not part.get("pending", false) and zone_damage[part["zone"]] >= 1.0:
			part["pending"] = true
			_detach.call_deferred(part)  # we are inside the physics callback


func _detach(part: Dictionary) -> void:
	part["pending"] = false
	if part["body"] != null or zone_damage[part["zone"]] < 1.0:
		return  # repaired in the meantime
	for node: Node3D in part["nodes"]:
		part["parents"].append(node.get_parent())
		part["xforms"].append(node.transform)
	part["body"] = make_debris(_car, part["nodes"], part["mass"])


func _apply_visuals() -> void:
	for mi in _meshes:
		for z in ZONE_COUNT:
			var i := mi.find_blend_shape_by_name("dz%d" % z)
			if i >= 0:
				mi.set_blend_shape_value(i, zone_damage[z])
