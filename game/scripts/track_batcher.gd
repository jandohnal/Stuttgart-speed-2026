extends RefCounted
## Web only: merges the track's static pieces into a few big meshes, one per material and map
## cell. WebGL's cost per draw call limits the frame rate (a dense forest is 5000 calls of mostly
## tiny pieces), while the triangle count is low. The originals stay, hidden: their collision and
## the ground lookup of CarEffects still use them.

const GROUPS := ["road", "terrain", "drivethrough", "vegetation", "objects", "shadows"]
const CELL := 500.0  ## m; larger cells mean fewer draw calls but coarser culling
const ARRAYS := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]


## Call when the track is fully set up (materials, water, lights). Returns the number of pieces merged.
static func merge(track: Node3D) -> int:
	var started := Time.get_ticks_msec()
	var buckets := {}
	var merged := 0
	var kept := 0
	for group: String in GROUPS:
		var node := track.find_child(group, true, false)
		if node == null:
			continue
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if not mi.is_visible_in_tree() or _is_moving(mi, track):
				continue
			if not _can_merge(mi):
				kept += 1
				continue
			_collect(mi, track, buckets)
			mi.visible = false
			merged += 1
	for key: String in buckets:
		track.add_child(_build(buckets[key]))
	print("TrackBatcher: %d pieces -> %d meshes, %d kept apart, %d ms" % [merged, buckets.size(), kept, Time.get_ticks_msec() - started])
	return merged


## A piece on a physics body (a prop that can be knocked over) has to stay on its own.
static func _is_moving(mi: Node3D, track: Node3D) -> bool:
	var node := mi.get_parent()
	while node != null and node != track:
		if node is PhysicsBody3D:
			return true
		node = node.get_parent()
	return false


## Only indexed triangles in opaque or alpha-tested materials: blended ones are sorted per mesh.
static func _can_merge(mi: MeshInstance3D) -> bool:
	if not mi.mesh is ArrayMesh or mi.mesh.get_surface_count() == 0:
		return false
	for s in mi.mesh.get_surface_count():
		var material := mi.get_active_material(s)
		if material == null or mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		if mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] == null:
			return false
		if material is BaseMaterial3D and (material as BaseMaterial3D).transparency in [
				BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:
			return false
	return true


static func _collect(mi: MeshInstance3D, track: Node3D, buckets: Dictionary) -> void:
	var to_track := track.global_transform.affine_inverse() * mi.global_transform
	var center := to_track * mi.get_aabb().get_center()
	var cell := Vector2i(floori(center.x / CELL), floori(center.z / CELL))
	for s in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var material := mi.get_active_material(s)
		var present := ARRAYS.filter(func(a: int) -> bool: return arrays[a] != null)
		var key := "%s|%d|%d|%d|%s" % [cell, material.get_instance_id(), mi.cast_shadow, mi.layers, present]
		if not buckets.has(key):
			buckets[key] = {"material": material, "cast_shadow": mi.cast_shadow, "layers": mi.layers,
				"present": present, "arrays": _empty_arrays(present), "index": PackedInt32Array()}
		_append(buckets[key], arrays, to_track)


static func _empty_arrays(present: Array) -> Dictionary:
	var out := {}
	for a: int in present:
		match a:
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
				out[a] = PackedVector3Array()
			Mesh.ARRAY_TANGENT:
				out[a] = PackedFloat32Array()
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
				out[a] = PackedVector2Array()
			Mesh.ARRAY_COLOR:
				out[a] = PackedColorArray()
	return out


static func _append(bucket: Dictionary, arrays: Array, to_track: Transform3D) -> void:
	var out: Dictionary = bucket["arrays"]
	var offset: int = out[Mesh.ARRAY_VERTEX].size()
	var normals := Transform3D(to_track.basis.inverse().transposed(), Vector3.ZERO)
	for a: int in bucket["present"]:
		var values: Variant = arrays[a]
		if a == Mesh.ARRAY_VERTEX:
			values = to_track * (values as PackedVector3Array)
		elif a == Mesh.ARRAY_NORMAL:
			values = normals * (values as PackedVector3Array)
		elif a == Mesh.ARRAY_TANGENT and not to_track.basis.is_equal_approx(Basis.IDENTITY):
			values = _rotated_tangents(values, to_track.basis)
		out[a].append_array(values)
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in index.size():
		index[i] += offset
	bucket["index"].append_array(index)


static func _rotated_tangents(tangents: PackedFloat32Array, basis: Basis) -> PackedFloat32Array:
	var out := tangents.duplicate()
	for i in range(0, out.size(), 4):
		var t := (basis * Vector3(out[i], out[i + 1], out[i + 2])).normalized()
		out[i] = t.x
		out[i + 1] = t.y
		out[i + 2] = t.z
	return out


static func _build(bucket: Dictionary) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	for a: int in bucket["present"]:
		arrays[a] = bucket["arrays"][a]
	arrays[Mesh.ARRAY_INDEX] = bucket["index"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, bucket["material"])
	var mi := MeshInstance3D.new()
	mi.name = "Batch"
	mi.mesh = mesh
	mi.cast_shadow = bucket["cast_shadow"]
	mi.layers = bucket["layers"]
	return mi
