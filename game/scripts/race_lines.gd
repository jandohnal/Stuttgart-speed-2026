extends RefCounted
## Start and finish lines on the road. The finish line is the original's: tiles (FNSH, a 6 x 6 m
## chequer) that _fstart.scn places across the road, exported by track2gltf in the group
## "gates". They become decals, so they follow the road surface instead of fighting with it.
## The original has no start line object; ours is a white stripe across the road at the start
## trigger. Decals skip the car's layer, so a car standing on a line is not painted.

const Materials := preload("res://scripts/materials.gd")

const PROJECTION_DEPTH := 1.0  ## m above and below the line that the decal paints
const START_LINE_DEPTH := 0.5  ## m along the road
const START_LINE_COLOR := Color(0.95, 0.95, 0.92)


## Turns the meshes of the track's "gates" group into decals; returns how many.
static func gate_decals(track: Node3D) -> int:
	var group := track.find_child("gates", true, false) as Node3D
	if group == null:
		return 0
	var count := 0
	for mesh_node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		var material := mi.get_active_material(0) as BaseMaterial3D
		if material == null or material.albedo_texture == null:
			continue
		var box := mi.get_aabb()
		var decal := _decal(material.albedo_texture, Vector3(box.size.x, PROJECTION_DEPTH * 2.0, box.size.z))
		decal.transform = mi.transform * Transform3D(Basis.IDENTITY, box.get_center())
		mi.get_parent().add_child(decal)
		mi.visible = false
		count += 1
	return count


## White stripe across the road at the start trigger; `slice` is the road slice nearest to it
## (its right vector and half widths give the road across).
static func start_line(start: Dictionary, slice: Dictionary) -> Decal:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(START_LINE_COLOR)
	var widths: Array = slice["widths"]
	var half := maxf(float(widths[0]), float(widths[1]))
	var decal := _decal(ImageTexture.create_from_image(image), Vector3(half * 2.0, PROJECTION_DEPTH * 2.0, START_LINE_DEPTH))
	var right := _vec(slice["right"]).normalized()
	var up := _vec(slice["up"]).normalized()
	var basis := Basis(right, up, right.cross(up)).orthonormalized()
	decal.transform = Transform3D(basis, _vec(start["position"]))
	return decal


static func _decal(texture: Texture2D, size: Vector3) -> Decal:
	var decal := Decal.new()
	decal.texture_albedo = texture
	decal.size = size
	decal.cull_mask = ~Materials.CAR_LAYER & 0xFFFFF
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	return decal


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
