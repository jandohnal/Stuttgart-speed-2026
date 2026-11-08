extends Node
## Headless test of the wheel input (D-038), needs no real wheel:
##   godot --headless --path game res://tests/wheel_input_test.tscn
## Checks the axis conversions (pedal resting at -1 / +1 / sharing an axis, dead zones, steering range
## and curve), the calibration detectors on recorded movements, then the Car: wheel values reach it
## without the key ramps (joypad events through Input.parse_input_event), a pedal that never reported
## counts as released, a held key takes over, and a disconnect falls back to the keyboard.

const CAR_SCENE := "res://scenes/main.tscn"
const FAKE_JOYPAD := 3
const DT := 1.0 / 60.0

var failures := 0


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _near(a: float, b: float, what: String) -> void:
	_check(absf(a - b) < 0.01, "%s: %.3f (expected %.3f)" % [what, a, b])


func _ready() -> void:
	_test_conversions()
	_test_detectors()
	await _test_car()
	print("WHEEL INPUT TEST: %s" % ("FAILED %d" % failures if failures > 0 else "OK"))
	get_tree().quit(1 if failures > 0 else 0)


func _test_conversions() -> void:
	print("Conversions")
	_near(WheelInput.pedal_value(-1.0, -1.0, 1.0), 0.0, "pedal resting at -1, released")
	_near(WheelInput.pedal_value(1.0, -1.0, 1.0), 1.0, "pedal resting at -1, full")
	_near(WheelInput.pedal_value(1.0, 1.0, -1.0), 0.0, "pedal resting at +1, released")
	_near(WheelInput.pedal_value(-1.0, 1.0, -1.0), 1.0, "pedal resting at +1, full")
	_near(WheelInput.pedal_value(-0.5, 0.0, 1.0), 0.0, "shared axis: throttle while braking")
	_near(WheelInput.pedal_value(-1.0, 0.0, -1.0), 1.0, "shared axis: full brake")
	_near(WheelInput.pedal_value(-0.98, -1.0, 1.0), 0.0, "pedal within the rest dead zone")
	_near(WheelInput.steer_value(0.0, 0.0, -1.0, 1.0, 1.0, 1.0), 0.0, "steering centred")
	_near(WheelInput.steer_value(-1.0, 0.0, -1.0, 1.0, 1.0, 1.0), 1.0, "full left is positive")
	_near(WheelInput.steer_value(1.0, 0.0, -1.0, 1.0, 1.0, 1.0), -1.0, "full right is negative")
	_near(WheelInput.steer_value(0.5, 0.0, 1.0, -1.0, 1.0, 1.0), 0.495, "reversed axis, half left")
	_near(WheelInput.steer_value(-0.35, 0.0, -1.0, 1.0, 0.35, 1.0), 1.0, "full lock at the steering range")
	_check(WheelInput.steer_value(-0.5, 0.0, -1.0, 1.0, 1.0, 2.0) < 0.3, "curve is gentler near the centre")
	var wheel := _mapping()
	_check(wheel.is_valid(), "complete mapping is valid")
	wheel.steer_right = -0.8
	_check(not wheel.is_valid(), "stops on the same side are invalid")


func _test_detectors() -> void:
	print("Detectors")
	var center := _axes({})
	var turn := WheelInput.TurnDetector.new(center)
	_check(not _feed_turn(turn, _axes({2: 0.1}), 2.0), "small movement is no stop")
	_check(not _feed_turn(turn, _axes({2: -0.5}), 0.2), "passing through is no stop")
	_check(_feed_turn(turn, _axes({2: -0.97}), 1.0) and turn.axis == 2 and is_equal_approx(turn.value, -0.97), "left stop on axis 2")
	var other := WheelInput.TurnDetector.new(center, 2, -0.97)
	_check(not _feed_turn(other, _axes({2: -0.97, 5: 1.0}), 1.0), "the same side and other axes do not count")
	_check(_feed_turn(other, _axes({2: 0.95}), 1.0) and is_equal_approx(other.value, 0.95), "right stop on the same axis")

	# Reports 0 until first moved, really rests at -1: the rest comes from after the release.
	var pedal := WheelInput.PedalDetector.new(center, 2)
	_check(not _feed_pedal(pedal, _axes({2: 1.0}), 1.0), "the steering axis is ignored")
	_check(not _feed_pedal(pedal, _axes({1: 1.0}), 2.0), "pedal held down is not finished")
	_check(_feed_pedal(pedal, _axes({1: -1.0}), 1.0), "pedal pressed and released")
	_check(pedal.axis == 1 and is_equal_approx(pedal.rest, -1.0) and is_equal_approx(pedal.full, 1.0), "axis 1 rests at -1, full at +1")
	var shared := WheelInput.PedalDetector.new(_axes({}), 2)
	_feed_pedal(shared, _axes({1: -1.0}), 0.5)
	_check(_feed_pedal(shared, _axes({1: 0.0}), 1.0) and is_equal_approx(shared.rest, 0.0) and is_equal_approx(shared.full, -1.0), "half of a shared axis")


func _test_car() -> void:
	print("Car")
	var main := preload(CAR_SCENE).instantiate() as Node3D
	main.track_name = "skidpad"
	add_child(main)
	var car := main.get_node("Car") as Car
	await get_tree().physics_frame
	_check(car.wheel == null, "tests get no wheel from the settings")
	car.digital_input = true
	var wheel := _mapping()
	wheel.attach(FAKE_JOYPAD)
	car.wheel = wheel

	await _step()
	_near(car.throttle, 0.0, "pedal that never reported is released")
	_near(car.steer, 0.0, "steering that never reported is centred")
	_axis(1, 1.0)
	_axis(0, -1.0)
	await _step()
	_near(car.throttle, 1.0, "full throttle at once, no key ramp")
	_check(car.steer > 0.0, "turning left steers left (%.3f)" % car.steer)
	_axis(1, -1.0)
	_axis(0, 0.0)
	await _step(30)
	_near(car.throttle, 0.0, "throttle released")
	_near(car.steer, 0.0, "steering back at the centre")

	_axis(1, 1.0)
	await _step()
	Input.action_press("steer_right")  # not the brake: at a standstill that would engage reverse
	await _step(30)
	_near(car.throttle, 0.0, "a held key takes over from the wheel: its throttle is ignored")
	_check(car.steer < 0.0, "the key steers (%.3f)" % car.steer)
	Input.action_release("steer_right")

	wheel._on_joy_connection(FAKE_JOYPAD, false)
	_check(not wheel.is_active(), "disconnected wheel is not active")
	await _step()
	_near(car.throttle, 0.0, "disconnect falls back to the keyboard")

	var saved := WheelInput.from_dict(wheel.to_dict())
	_check(saved.is_valid() and saved.steer_axis == wheel.steer_axis and is_equal_approx(saved.brake_full, wheel.brake_full), "mapping survives saving")
	_check(not saved.is_active(), "saved mapping of an absent device stays inactive")

	WheelInput.install_buttons({"handbrake": 4})
	var found := InputMap.action_get_events("handbrake").filter(func(e: InputEvent) -> bool: return e is InputEventJoypadButton)
	_check(found.size() == 1 and found[0].button_index == 4 and found[0].device == -1, "button goes to the action for any joypad")
	WheelInput.install_buttons({})
	found = InputMap.action_get_events("handbrake").filter(func(e: InputEvent) -> bool: return e is InputEventJoypadButton)
	_check(found.is_empty(), "removing the mapping removes the button")
	_check(InputMap.action_get_events("handbrake").size() == 1, "the key stays")


func _step(frames := 2) -> void:
	for i in frames:
		await get_tree().physics_frame


func _axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = FAKE_JOYPAD
	event.axis = axis as JoyAxis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mapping() -> WheelInput:
	var wheel := WheelInput.new()
	wheel.guid = "test"
	wheel.steer_axis = 0
	wheel.steer_left = -1.0
	wheel.steer_right = 1.0
	wheel.throttle_axis = 1
	wheel.throttle_rest = -1.0
	wheel.throttle_full = 1.0
	wheel.brake_axis = 3
	wheel.brake_rest = 1.0
	wheel.brake_full = -1.0
	return wheel


func _axes(values: Dictionary) -> PackedFloat32Array:
	var axes := PackedFloat32Array()
	axes.resize(WheelInput.AXES)
	for axis: int in values:
		axes[axis] = values[axis]
	return axes


## Feeds the same values for the given time.
func _feed_turn(detector: WheelInput.TurnDetector, values: PackedFloat32Array, seconds: float) -> bool:
	for i in int(seconds / DT):
		if detector.feed(values, DT):
			return true
	return false


func _feed_pedal(detector: WheelInput.PedalDetector, values: PackedFloat32Array, seconds: float) -> bool:
	for i in int(seconds / DT):
		if detector.feed(values, DT):
			return true
	return false
