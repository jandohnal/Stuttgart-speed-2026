extends Node
## Test of where FallingLeaves takes leaves from (D-028): only leafy tree crowns over farmland,
## alps, autobahn (the wood at its start), foothills and forest (its wooded part); no lamps,
## wires, icicles, awnings or tunnel lights, nothing on the other tracks. Prints the crowns used:
## material, triangles, slices.
##   godot --headless --path game res://tests/leaves_test.tscn [-- --track=<name>]

const WITH_LEAVES := ["farmland", "alps", "autobahn", "foothills", "forest"]
const AUTOBAHN_WOOD := 110  ## slices: the wood at autobahn's start


func _ready() -> void:
	var track := "farmland"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			track = arg.trim_prefix("--track=")
	var main := preload("res://scenes/main.tscn").instantiate() as Node3D
	main.track_name = track
	add_child(main)
	var fl: Node = main.get_node_or_null("FallingLeaves")
	var crowns: Dictionary = fl.crowns if fl != null else {}
	var slices: int = main.road.size() if main.road != null else 0
	print("LEAVES %s: %d slices, crowns %d materials" % [track, slices, crowns.size()])
	var last := -1
	for name: String in crowns:
		var c: Dictionary = crowns[name]
		last = maxi(last, c["last"])
		print("  %-40s %5d triangles  slices %4d-%4d" % [name, c["triangles"], c["first"], c["last"]])
	var ok := not crowns.is_empty() if track in WITH_LEAVES else crowns.is_empty()
	if track == "autobahn":
		ok = ok and last < AUTOBAHN_WOOD
	print("LEAVES TEST %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
