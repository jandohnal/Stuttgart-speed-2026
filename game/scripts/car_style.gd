class_name CarStyle
extends RefCounted
## Variant of an original car model (D-022): the original builds every variant of a model (coupé,
## cabrio, targa, turbo ...) from one .crp by its style in the model's .tpg, which picks the part
## type per geometry slot and the texture alternatives. tools/crp2gltf.py writes the parts of all
## styles into the glTF and <model>_styles.json: per style the nodes of the other styles and the
## atlases that differ from the glTF's own (those of the file's default style).
## apply() runs right after loading, before Materials.setup_car and Car.setup, so wheels, lights,
## collision and the damage groups only see the parts of the chosen style.


## Style data of the model (path relative to the data root, like OriginalAssets.load_gltf), or {}.
static func load_styles(model_path: String) -> Dictionary:
	var rel := model_path.get_basename() + "_styles.json"
	if not OriginalAssets.exists(rel):
		return {}
	var data: Variant = OriginalAssets.load_json(rel)
	return data if data is Dictionary else {}


## Style entry for the style number (0 or unknown: the file's default), or {}.
static func find_style(styles: Dictionary, style: int) -> Dictionary:
	var list: Array = styles.get("styles", [])
	for wanted: int in [style, int(styles.get("default", 0))]:
		for entry: Dictionary in list:
			if int(entry["style"]) == wanted:
				return entry
	return list[0] if not list.is_empty() else {}


## Removes the nodes the style does not show and swaps its atlases in. Convertibles have the top
## down unless top_up. Returns the style used (0 when the model has none).
static func apply(model: Node3D, model_path: String, style := 0, top_up := false) -> int:
	if model == null:
		return 0
	var entry := find_style(load_styles(model_path), style)
	if entry.is_empty():
		return 0
	var hide: Array = entry.get("hide", [])
	if top_up and entry.has("top_up"):
		var swap: Dictionary = entry["top_up"]
		hide = hide.filter(func(n: String) -> bool: return not n in swap["show"]) + swap["hide"]
	for node_name: String in hide:
		var node := model.find_child(node_name, true, false)
		if node != null:
			# Freed now, not queued: Car.setup and the lights look the parts up right after this.
			node.get_parent().remove_child(node)
			node.free()
	var textures: Dictionary = entry.get("textures", {})
	if not textures.is_empty():
		_swap_textures(model, textures, model_path.get_base_dir())
	return int(entry["style"])


static func _swap_textures(model: Node3D, textures: Dictionary, folder: String) -> void:
	var swapped := {}  # glTF material -> copy with the style's atlas (materials are shared between parts)
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var base := mesh.surface_get_material(surface) as StandardMaterial3D
			if base == null or not textures.has(base.resource_name):
				continue
			if not swapped.has(base):
				var m := base.duplicate() as StandardMaterial3D
				var image := Image.load_from_file(OriginalAssets.path(folder.path_join(str(textures[base.resource_name]))))
				if image != null and not image.is_empty():
					image.generate_mipmaps()
					m.albedo_texture = ImageTexture.create_from_image(image)
				swapped[base] = m
			mesh.surface_set_material(surface, swapped[base])
