class_name OriginalAssets
extends RefCounted
## Loads assets converted from the original game (tools/*.py) at run time from decomposed/.
## They are never imported into res://, so nothing from the original game ends up in the
## project or in git (D-008). Location: project setting stuttgart/data_root.

const DEFAULT_ROOT := "../decomposed"


static func data_root() -> String:
	var root: String = ProjectSettings.get_setting("stuttgart/data_root", DEFAULT_ROOT)
	if root.is_relative_path():
		root = ProjectSettings.globalize_path("res://").path_join(root).simplify_path()
	return root


static func path(relative: String) -> String:
	return data_root().path_join(relative)


static func load_gltf(relative: String) -> Node3D:
	var file := path(relative)
	if not FileAccess.file_exists(file):
		push_error("Missing %s - run the converters in tools/ first (see game/README.md)" % file)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(file, state)
	if err != OK:
		push_error("Cannot load %s (error %d)" % [file, err])
		return null
	return doc.generate_scene(state) as Node3D


static func load_json(relative: String) -> Variant:
	var file := path(relative)
	if not FileAccess.file_exists(file):
		push_error("Missing %s - run the converters in tools/ first (see game/README.md)" % file)
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(file))
