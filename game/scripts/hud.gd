extends CanvasLayer
## Minimal telemetry readout.

@export var car_path: NodePath

@onready var car := get_node_or_null(car_path) as Car
@onready var label: Label = $Label


func _process(_delta: float) -> void:
	if car == null or car.telemetry.is_empty():
		return
	var t := car.telemetry
	var gear_text := "R" if int(t["gear"]) == -1 else str(t["gear"])
	label.text = "%d km/h   gear %s   %d rpm\nlat %.2f g   long %.2f g   steer %.1f°\nsteering assist %s\n" % [
		roundi(t["speed_kmh"]), gear_text, t["rpm"], t["lat_g"], t["long_g"], t["steer_deg"],
		"ON" if t["assist"] else "OFF",
	] + "W/S throttle/brake  A/D steer  Space handbrake  R reset  F2 telemetry  F3 assist  F11 full screen"
