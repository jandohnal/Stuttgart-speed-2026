class_name FollowCamera
extends Camera3D
## Chase camera behind the car (car front is -Z). While the game is paused it orbits the car:
## drag with the left mouse button to rotate, mouse wheel to zoom.

@export var target_path: NodePath
@export var distance := 6.0
@export var height := 2.4
@export var look_height := 1.0
@export var smoothing := 6.0
@export var orbit_sensitivity := 0.005  ## radians per pixel of mouse drag
@export var orbit_min_distance := 2.5
@export var orbit_max_distance := 30.0

var target: Node3D
var _orbiting := false
var _yaw := 0.0
var _pitch := 0.0
var _orbit_distance := 0.0


func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D
	process_mode = Node.PROCESS_MODE_ALWAYS  # orbits while the tree is paused


## Free orbit around the car (pause), starting from where the chase camera is now.
func set_orbit(on: bool) -> void:
	_orbiting = on and target != null
	if not _orbiting:
		return
	var offset := global_position - _orbit_center()
	_orbit_distance = clampf(offset.length(), orbit_min_distance, orbit_max_distance)
	_yaw = atan2(offset.x, offset.z)
	_pitch = asin(clampf(offset.y / maxf(offset.length(), 0.001), -1.0, 1.0))


func _orbit_center() -> Vector3:
	return target.global_position + Vector3.UP * look_height


func _unhandled_input(event: InputEvent) -> void:
	if not _orbiting:
		return
	var motion := event as InputEventMouseMotion
	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= motion.relative.x * orbit_sensitivity
		_pitch = clampf(_pitch + motion.relative.y * orbit_sensitivity, -0.2, 1.45)
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(_orbit_distance * 0.9, orbit_min_distance)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(_orbit_distance / 0.9, orbit_max_distance)


func _process(_delta: float) -> void:
	if not _orbiting:
		return
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	global_position = _orbit_center() + dir * _orbit_distance
	look_at(_orbit_center())


func _physics_process(delta: float) -> void:
	if target == null or _orbiting or get_tree().paused:
		return
	var xf := target.global_transform
	var back := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
	if back == Vector3.ZERO:
		back = Vector3.BACK
	var wanted := xf.origin + back * distance + Vector3.UP * height
	global_position = global_position.lerp(wanted, clampf(smoothing * delta, 0.0, 1.0))
	look_at(xf.origin + Vector3.UP * look_height)
