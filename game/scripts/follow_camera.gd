extends Camera3D
## Chase camera behind the car (car front is -Z).

@export var target_path: NodePath
@export var distance := 5.5
@export var height := 1.7
@export var look_height := 0.8
@export var smoothing := 6.0

var target: Node3D


func _ready() -> void:
	target = get_node_or_null(target_path) as Node3D


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var xf := target.global_transform
	var back := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
	if back == Vector3.ZERO:
		back = Vector3.BACK
	var wanted := xf.origin + back * distance + Vector3.UP * height
	global_position = global_position.lerp(wanted, clampf(smoothing * delta, 0.0, 1.0))
	look_at(xf.origin + Vector3.UP * look_height)
