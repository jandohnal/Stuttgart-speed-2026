extends Node
## Renders the prototype and saves screenshots (needs a window, not --headless):
##   godot --path game res://tests/screenshot.tscn -- <output folder> [--track=<name>] [--slice=<n>]
## Drives for a few seconds with the chase camera, saves shot_0.png .. shot_2.png and quits.

const SHOT_TIMES := [1.0, 4.0, 8.0]

var main: Node3D
var out_dir := "user://"
var t := 0.0
var shot := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		out_dir = args[0]
	main = preload("res://scenes/main.tscn").instantiate() as Node3D
	add_child(main)
	(main.get_node("Camera") as FollowCamera).intro_duration = 0.0  # shots from behind the car


func _process(delta: float) -> void:
	t += delta
	if t > 1.5:
		Input.action_press("accelerate")
	if shot < SHOT_TIMES.size() and t >= SHOT_TIMES[shot]:
		var path := out_dir.path_join("shot_%d.png" % shot)
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
		shot += 1
		if shot == SHOT_TIMES.size():
			get_tree().quit()
