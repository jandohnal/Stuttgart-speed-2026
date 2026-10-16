extends Node3D
## Phase 2 prototype (D-009): the original 356 A on the original skidpad, both loaded at run
## time from decomposed/. F2 records telemetry to user://telemetry_*.csv for comparing with
## the original game.

const TRACK := "GameData/Track/skidpad/skidpad.gltf"
const ROAD := "GameData/Track/skidpad/skidpad_road.json"
const CAR_MODEL := "GameData/CarModel/356a/356a.gltf"
const CAR_PHYSICS := "GameData/Simulation/cars.json"
const CAR_KEY := "356Acoupe16"
const SOLID_GROUPS := ["road", "terrain", "objects"]
const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"reset_car": [KEY_R],
	"telemetry": [KEY_F2],
}
const LOG_FIELDS := ["time", "speed_kmh", "rpm", "gear", "throttle", "brake", "steer_deg", "lat_g", "long_g"]

@onready var car: Car = $Car

var road_slices: Array = []
var _log: FileAccess
var _log_time := 0.0


func _ready() -> void:
	_setup_input()
	var track := OriginalAssets.load_gltf(TRACK)
	if track != null:
		add_child(track)
		_add_track_collision(track)
		var simd := track.find_child("simd", true, false) as Node3D
		if simd != null:
			simd.visible = false  # road data overlay from track2gltf, only for checking
	var road: Variant = OriginalAssets.load_json(ROAD)
	if road is Dictionary:
		road_slices = road["slices"]
	var cars: Variant = OriginalAssets.load_json(CAR_PHYSICS)
	if cars is Dictionary and cars.has(CAR_KEY):
		car.setup(OriginalAssets.load_gltf(CAR_MODEL), cars[CAR_KEY])
	else:
		push_error("Car %s not found in %s" % [CAR_KEY, CAR_PHYSICS])
	_reset_car(0)


func _setup_input() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			InputMap.action_add_event(action, event)


func _add_track_collision(track: Node3D) -> void:
	for group: String in SOLID_GROUPS:
		var node := track.find_child(group, true, false)
		if node == null:
			continue
		for child in node.find_children("*", "MeshInstance3D", true, false):
			(child as MeshInstance3D).create_trimesh_collision()


func _reset_car(slice_index: int) -> void:
	if road_slices.is_empty():
		car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
		return
	var s: Dictionary = road_slices[slice_index]
	var pos := _vec(s["position"])
	var up := _vec(s["up"])
	var rot := Basis.looking_at(_vec(s["forward"]), up)  # car front is -Z, as in the original
	car.reset_to(Transform3D(rot, pos + up * 0.4))


func _nearest_slice() -> int:
	var best := 0
	var best_dist := INF
	for i in road_slices.size():
		var d := _vec(road_slices[i]["position"]).distance_squared_to(car.global_position)
		if d < best_dist:
			best_dist = d
			best = i
	return best


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_car"):
		_reset_car(_nearest_slice())
	elif event.is_action_pressed("telemetry"):
		_toggle_log()


func _toggle_log() -> void:
	if _log != null:
		_log.close()
		_log = null
		print("Telemetry stopped")
		return
	var file := "user://telemetry_%s.csv" % Time.get_datetime_string_from_system().replace(":", "-")
	_log = FileAccess.open(file, FileAccess.WRITE)
	if _log == null:
		push_error("Cannot write %s" % file)
		return
	_log.store_line(",".join(LOG_FIELDS))
	_log_time = 0.0
	print("Telemetry -> ", ProjectSettings.globalize_path(file))


func _physics_process(delta: float) -> void:
	if _log == null or car.telemetry.is_empty():
		return
	_log_time += delta
	var row := PackedStringArray()
	for field: String in LOG_FIELDS:
		row.append(str(snappedf(_log_time, 0.001)) if field == "time" else str(car.telemetry.get(field, "")))
	_log.store_line(",".join(row))
