class_name FollowCamera
extends Camera3D
## Chase camera behind the car (car front is -Z). While the game is paused it orbits the car:
## drag with the left mouse button to rotate, mouse wheel to zoom. The camera stays out of
## track geometry and keeps a little height above the ground. At the start it circles from in
## front of the car round to the chase position (intro).

@export var target_path: NodePath
@export var distance := 6.0
@export var height := 2.4
@export var look_height := 1.0
@export var smoothing := 6.0
@export var orbit_sensitivity := 0.005  ## radians per pixel of mouse drag
@export var orbit_min_distance := 2.5
@export var orbit_max_distance := 30.0
@export var roll_degrees := 0.0  ## sideways tilt around the view axis, + = clockwise
@export var collision_radius := 0.3  ## m; the camera stops this far in front of walls and terrain
@export var min_ground_clearance := 0.4  ## m above the ground below the camera
@export var snap_distance := 10.0  ## m; a bigger jump of the car in one tick (reset) snaps the camera
@export var intro_duration := 3.0  ## s; circling from the front to behind the car at the start, 0 = off
@export var intro_start_distance := 5.0  ## m in front of the car where the intro starts
@export var intro_clockwise := true  ## seen from above; false circles the other way

const GROUND_PROBE_DOWN := 5.0  ## m below the camera where it ends

var target: Node3D
var _orbiting := false
var _yaw := 0.0
var _pitch := 0.0
var _orbit_distance := 0.0
var _snapped := false
var _intro_started := false
var _intro_time := -1.0  ## s since the intro started, < 0 when it is not running
var _last_target_pos := Vector3.ZERO
var _probe := SphereShape3D.new()


func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D
	process_mode = Node.PROCESS_MODE_ALWAYS  # orbits while the tree is paused
	_probe.radius = collision_radius


## Circles from in front of the car to the chase position again (race restart).
func play_intro() -> void:
	_snapped = false
	_intro_started = true
	_intro_time = 0.0 if intro_duration > 0.0 else -1.0


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
	global_position = _avoid_geometry(_orbit_center(), _orbit_center() + dir * _orbit_distance)
	_aim(_orbit_center())


func _physics_process(delta: float) -> void:
	if target == null or _orbiting or get_tree().paused:
		return
	var xf := target.global_transform
	var back := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
	if back == Vector3.ZERO:
		back = Vector3.BACK
	var wanted := xf.origin + back * distance + Vector3.UP * height
	if xf.origin.distance_to(_last_target_pos) > snap_distance:
		_snapped = false  # first frame or the car was reset: no glide across the map
	_last_target_pos = xf.origin
	if not _intro_started:
		_intro_started = true
		if intro_duration > 0.0:
			_intro_time = 0.0
	var t := clampf(smoothing * delta, 0.0, 1.0) if _snapped else 1.0
	_snapped = true
	if _intro_time >= 0.0:
		wanted = _intro_position(xf.origin, back)
		t = 1.0  # the intro path is smooth already; it ends exactly at the chase position
		_intro_time += delta
		if _intro_time >= intro_duration:
			_intro_time = -1.0
	var pivot := xf.origin + Vector3.UP * look_height
	# After the lerp, so smoothing cannot pull the camera back into a wall.
	global_position = _avoid_geometry(pivot, global_position.lerp(wanted, t))
	_aim(pivot)


## Intro camera: starts intro_start_distance in front of the car and circles round it
## (eased) to the chase position behind it, following the car if it already moves.
func _intro_position(origin: Vector3, back: Vector3) -> Vector3:
	var a := smoothstep(0.0, 1.0, clampf(_intro_time / intro_duration, 0.0, 1.0))
	var turn := PI * (1.0 - a) * (1.0 if intro_clockwise else -1.0)
	var dir := back.rotated(Vector3.UP, turn)
	var dist := lerpf(intro_start_distance, distance, a)
	return origin + dir * dist + Vector3.UP * height


func _aim(point: Vector3) -> void:
	if global_position.is_equal_approx(point):
		return
	look_at(point)
	if roll_degrees != 0.0:
		rotate_object_local(Vector3.FORWARD, deg_to_rad(roll_degrees))


## Moves the camera from `wanted` towards `pivot` until a sphere fits there, then lifts it
## above the ground below it. The car itself is ignored.
func _avoid_geometry(pivot: Vector3, wanted: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var body := target as CollisionObject3D
	if body != null:
		exclude.append(body.get_rid())
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis.IDENTITY, pivot)
	q.motion = wanted - pivot
	q.exclude = exclude
	var safe := space.cast_motion(q)[0]  # free fraction of the path
	var pos := pivot + (wanted - pivot) * safe
	# The ray starts no higher than the pivot, so a bridge or tunnel roof above is not "ground".
	var from := Vector3(pos.x, maxf(pos.y, pivot.y), pos.z)
	var ray := PhysicsRayQueryParameters3D.create(
			from, pos + Vector3.DOWN * GROUND_PROBE_DOWN, 0xFFFFFFFF, exclude)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and pos.y < hit.position.y + min_ground_clearance:
		pos.y = hit.position.y + min_ground_clearance
	return pos
