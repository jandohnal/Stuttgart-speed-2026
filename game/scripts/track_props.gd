extends RefCounted
## Physics for the objects placed along an original track (group "props" in the track glTF,
## described by <track>_objects.json from tools/track2gltf.py). The collision type and mass
## come from the original animdefs.txt:
##   smackable  -> RigidBody3D with the original mass, frozen until a moving body comes within
##                 WAKE_MARGIN (signs are too top-heavy to stand on their own)
##   box, cylinder, static -> StaticBody3D
##   none       -> visual only (finish line, arrows, animated sweepers)
## Every body collides as the convex hull of its mesh, flat ones as a box at least 10 cm thick.

const DEFAULT_MASS := 50.0  ## kg, smackables without a mass in animdefs.txt
const MIN_THICKNESS := 0.1  ## m, flatter objects collide as a box this thick
const WAKE_MARGIN := 1.0  ## m around a smackable where a moving body releases it (> one tick at 200 km/h)


## Turns the props of a loaded track into physics bodies; returns {collide type: count}.
static func build(track: Node3D, objects: Array) -> Dictionary:
	var group := track.find_child("props", true, false) as Node3D
	var counts := {}
	if group == null:
		return counts
	var by_index := {}
	for info: Dictionary in objects:
		by_index[str(info["node"]).substr(0, 3).to_int()] = info
	for child in group.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not str(mi.name).substr(0, 3).is_valid_int():
			continue
		var info: Dictionary = by_index.get(str(mi.name).substr(0, 3).to_int(), {})
		var collide: String = info.get("collide", "static")
		counts[collide] = int(counts.get(collide, 0)) + 1
		if collide == "none" or bool(info.get("drivethrough", false)):
			continue
		_make_body(group, mi, collide, float(info.get("mass", 0.0)))
	return counts


static func _make_body(group: Node3D, mi: MeshInstance3D, collide: String, mass: float) -> void:
	# Bodies must not be scaled: the scale stays on the mesh and is baked into the hull.
	var xf := mi.transform
	var scale := xf.basis.get_scale()
	var body: PhysicsBody3D
	if collide == "smackable":
		var rigid := RigidBody3D.new()
		rigid.mass = mass if mass > 0.0 else DEFAULT_MASS
		rigid.continuous_cd = true
		rigid.freeze = true
		body = rigid
	else:
		body = StaticBody3D.new()
	body.name = mi.name
	body.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var points := PackedVector3Array()
	for surface in mi.mesh.get_surface_count():
		for p: Vector3 in mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			points.append(p * scale)
	var col := CollisionShape3D.new()
	var bounds := AABB(points[0], Vector3.ZERO) if not points.is_empty() else AABB()
	for p in points:
		bounds = bounds.expand(p)
	if bounds.size[bounds.get_shortest_axis_index()] < MIN_THICKNESS:
		# Flat objects (sign plates) give a degenerate hull: use a box with some thickness.
		var box := BoxShape3D.new()
		box.size = bounds.size.max(Vector3.ONE * MIN_THICKNESS)
		col.shape = box
		col.position = bounds.get_center()
	else:
		var hull := ConvexPolygonShape3D.new()
		hull.points = points
		col.shape = hull
	body.add_child(col)
	if body is RigidBody3D:
		_add_wake_area(body as RigidBody3D, bounds)
	group.remove_child(mi)
	mi.transform = Transform3D(Basis.from_scale(scale), Vector3.ZERO)
	mi.name = "mesh"
	body.add_child(mi)
	group.add_child(body)


## Releases a frozen smackable as soon as a moving body (the car, a flying sign) gets close, so
## the impact itself is already between two dynamic bodies.
static func _add_wake_area(rigid: RigidBody3D, bounds: AABB) -> void:
	var area := Area3D.new()
	area.monitorable = false
	var box := BoxShape3D.new()
	box.size = bounds.size.max(Vector3.ONE * MIN_THICKNESS) + Vector3.ONE * 2.0 * WAKE_MARGIN
	var col := CollisionShape3D.new()
	col.shape = box
	col.position = bounds.get_center()
	area.add_child(col)
	rigid.add_child(area)
	area.body_entered.connect(func(other: Node3D) -> void:
		if other is RigidBody3D and not (other as RigidBody3D).freeze:
			rigid.set_deferred("freeze", false)
			area.set_deferred("monitoring", false))
