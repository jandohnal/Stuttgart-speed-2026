extends Node
## Autoload DataPacks: on the web, the converted data arrives as zip packs next to the page
## (tools/pack_web.py). A pack is downloaded when first needed and mounted into res://decomposed,
## so the loading code stays the same as on the desktop, where every call here does nothing.

const LOADING_SCENE := "res://scenes/loading.tscn"
const DATA_URL := "data/"
## Packs live in the browser's memory file system, which is not persistent; revisits are served
## by the browser's HTTP cache.
const PACK_DIR := "/tmp"
## Mounted track packs stay in wasm memory; the least recently used are dropped above this.
const TRACK_BUDGET := 512 * 1024 * 1024
## Bytes taken from the response per frame; the default 64 KiB needs half a minute for a big track.
const DOWNLOAD_CHUNK := 4 * 1024 * 1024

## Where the loading scene goes next and what it downloads first (go()).
var next_scene := ""
var next_packs: Array = []
## Why the last ensure() failed.
var error := ""

var _packs := {}  ## pack name -> {"size": bytes}, from the manifest
var _mounted: Array[String] = []  ## least recently used first
var _busy := false
var _http: HTTPRequest
var _total := 0
var _done := 0


## Mounts the packs, downloading the missing ones. False on failure (see `error`).
func ensure(names: Array) -> bool:
	if not OS.has_feature("web"):
		return true
	while _busy:
		await get_tree().process_frame
	_busy = true
	var ok: bool = await _ensure(names)
	_busy = false
	return ok


## Changes to `scene` after its packs are there, through the loading screen on the web.
func go(scene: String, packs: Array) -> void:
	if not OS.has_feature("web"):
		get_tree().change_scene_to_file(scene)
		return
	next_scene = scene
	next_packs = packs
	get_tree().change_scene_to_file(LOADING_SCENE)


## Share of the running ensure() already downloaded, 0..1.
func progress() -> float:
	if _total <= 0:
		return 0.0
	var current := _http.get_downloaded_bytes() if is_instance_valid(_http) else 0
	return clampf(float(_done + current) / _total, 0.0, 1.0)


## Name of the pack holding a car or track file (path relative to the data root), else "".
static func pack_for(relative: String) -> String:
	var parts := relative.split("/")
	if parts.size() >= 3 and parts[0] == "GameData":
		if parts[1] == "CarModel":
			return "car-" + parts[2]
		if parts[1] == "Track":
			return "track-" + parts[2]
	return ""


## True when the manifest offers the pack holding this car or track file.
func offers(relative: String) -> bool:
	return _packs.has(pack_for(relative))


func _ensure(names: Array) -> bool:
	error = ""
	if _packs.is_empty() and not await _load_manifest():
		return false
	var missing: Array[String] = []
	_total = 0
	_done = 0
	for pack: String in names:
		if not _packs.has(pack):
			error = "Pack %s is not in the manifest - run tools/pack_web.py" % pack
			return false
		if pack in _mounted:
			_mounted.erase(pack)
			_mounted.append(pack)
		elif pack not in missing:
			missing.append(pack)
			_total += _size(pack)
	for pack in missing:
		_make_room(pack, names)
		var body := await _fetch(DATA_URL + pack + ".zip")
		if body.is_empty():
			error = "Cannot download pack %s" % pack
			return false
		var file := _file(pack)
		var out := FileAccess.open(file, FileAccess.WRITE)
		if out == null:
			error = "Cannot store pack %s (error %d)" % [pack, FileAccess.get_open_error()]
			return false
		out.store_buffer(body)
		out.close()
		if not ProjectSettings.load_resource_pack(file, true):
			error = "Cannot mount pack %s" % pack
			return false
		_mounted.append(pack)
		_done += _size(pack)
	return true


func _load_manifest() -> bool:
	var body := await _fetch(DATA_URL + "manifest.json")
	var manifest: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	if not manifest is Dictionary or not manifest.has("packs"):
		error = "Game data not found on the server - run tools/pack_web.py (see docs/web.md)"
		return false
	_packs = manifest["packs"]
	return true


## Empty on failure. HTTPRequest needs an absolute URL; download_file does not work on the web.
func _fetch(relative: String) -> PackedByteArray:
	var base: String = JavaScriptBridge.eval("window.location.href.replace(/[^/]*$/, '')")
	_http = HTTPRequest.new()
	_http.download_chunk_size = DOWNLOAD_CHUNK
	add_child(_http)
	if _http.request(base + relative) != OK:
		_http.queue_free()
		return PackedByteArray()
	var response: Array = await _http.request_completed
	_http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		return PackedByteArray()
	return response[3]


## Drops the least recently used track packs (not those in `keep`) to fit a new track pack.
func _make_room(pack: String, keep: Array) -> void:
	if not pack.begins_with("track-"):
		return
	var used := _size(pack)
	for mounted in _mounted:
		if mounted.begins_with("track-"):
			used += _size(mounted)
	for mounted in _mounted.duplicate():
		if used <= TRACK_BUDGET:
			return
		if mounted.begins_with("track-") and mounted not in keep:
			DirAccess.remove_absolute(_file(mounted))
			_mounted.erase(mounted)
			used -= _size(mounted)


func _size(pack: String) -> int:
	return int(_packs[pack]["size"])


func _file(pack: String) -> String:
	return PACK_DIR.path_join(pack + ".zip")
