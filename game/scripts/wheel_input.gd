class_name WheelInput
extends RefCounted
## A racing wheel or any other joypad with analog axes, calibrated in the menu (WheelSetup, D-038).
## Wheels share no common axis layout, so the mapping is measured instead of listed per model:
## axis numbers and their calibrated values, stored per device GUID in GameSettings.wheel.
## Car reads steer() / throttle() / brake(); the buttons go to the InputMap (install_buttons).
## A pedal may rest at -1 or +1, and throttle and brake may share one axis: only rest and full
## values matter. Reconnecting finds the device again by GUID.

const AXES := int(JOY_AXIS_MAX)
const BUTTONS := int(JOY_BUTTON_MAX)
## Action -> label in the setup: game actions a wheel button can trigger.
const BUTTON_ACTIONS := {
	"handbrake": "HANDBRAKE",
	"reset_car": "RESET CAR",
	"restart_race": "RESTART RACE",
	"pause": "PAUSE",
	"menu": "BACK TO MENU",
}
const DEFAULT_STEER_RANGE := 0.35  ## guess for a 900 degree wheel: full lock at about 160 degrees
const DEFAULT_STEER_CURVE := 1.2
const MIN_STEER_RANGE := 0.1
const STEER_DEADZONE := 0.01  ## share of the axis either side of centre
const PEDAL_DEADZONE := 0.03  ## share of the travel ignored at rest, pedals rarely return exactly
const PEDAL_TOP := 0.02  ## share ignored at the end of the travel, so full is reachable
const MOVE_EPSILON := 0.01
const MIN_TRAVEL := 0.3  ## least axis change that counts as a calibration movement

var guid := ""
var device_name := ""
var device := -1  ## current joypad id, -1 = not connected
var steer_axis := -1
var steer_center := 0.0
var steer_left := 0.0
var steer_right := 0.0
var throttle_axis := -1
var throttle_rest := 0.0
var throttle_full := 0.0
var brake_axis := -1
var brake_rest := 0.0
var brake_full := 0.0
var steer_range := DEFAULT_STEER_RANGE  ## share of the axis travel to one side that gives full lock
var steer_curve := DEFAULT_STEER_CURVE  ## 1 = linear, more = gentler around the centre
var buttons := {}  ## action -> button index

var _initial := {}  ## axis -> first value read
var _moved := {}  ## axis -> true once it changed


## Calibrated axis value -> pedal 0..1. Works for any rest and full, also for half of a shared axis.
static func pedal_value(raw: float, rest: float, full: float) -> float:
	var span := full - rest
	if absf(span) < 0.001:
		return 0.0
	var travel := clampf((raw - rest) / span, 0.0, 1.0)
	return clampf((travel - PEDAL_DEADZONE) / (1.0 - PEDAL_DEADZONE - PEDAL_TOP), 0.0, 1.0)


## Calibrated axis value -> steering -1..1, positive to the left as in Car._read_input.
static func steer_value(raw: float, center: float, left: float, right: float, range_share: float, curve: float) -> float:
	var away := raw - center
	var span := left - center
	var side := 1.0
	if away * span < 0.0:
		span = right - center
		side = -1.0
	if absf(span) < 0.001:
		return 0.0
	var reach := maxf(range_share, MIN_STEER_RANGE)
	var turned := clampf((clampf(away / span, 0.0, 1.0) - STEER_DEADZONE) / (reach - STEER_DEADZONE), 0.0, 1.0)
	return side * pow(turned, maxf(curve, 0.1))


## Puts the wheel's buttons into the InputMap, replacing those of an earlier calibration.
## device -1 = any joypad, as joypad numbers change between runs.
static func install_buttons(mapping: Dictionary) -> void:
	for action: String in BUTTON_ACTIONS:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				InputMap.action_erase_event(action, event)
		if mapping.has(action):
			var event := InputEventJoypadButton.new()
			event.device = -1
			event.button_index = int(mapping[action]) as JoyButton
			InputMap.action_add_event(action, event)


## All axes of a joypad, for the calibration detectors.
static func read_axes(joypad: int) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(AXES)
	for axis in AXES:
		values[axis] = Input.get_joy_axis(joypad, axis as JoyAxis)
	return values


## Mapping from GameSettings.wheel; looks for its device and follows connects and disconnects.
static func from_dict(data: Dictionary) -> WheelInput:
	var wheel := WheelInput.new()
	wheel.guid = str(data.get("guid", ""))
	wheel.device_name = str(data.get("name", ""))
	wheel.steer_axis = int(data.get("steer_axis", -1))
	wheel.steer_center = float(data.get("steer_center", 0.0))
	wheel.steer_left = float(data.get("steer_left", 0.0))
	wheel.steer_right = float(data.get("steer_right", 0.0))
	wheel.throttle_axis = int(data.get("throttle_axis", -1))
	wheel.throttle_rest = float(data.get("throttle_rest", 0.0))
	wheel.throttle_full = float(data.get("throttle_full", 0.0))
	wheel.brake_axis = int(data.get("brake_axis", -1))
	wheel.brake_rest = float(data.get("brake_rest", 0.0))
	wheel.brake_full = float(data.get("brake_full", 0.0))
	wheel.steer_range = float(data.get("steer_range", DEFAULT_STEER_RANGE))
	wheel.steer_curve = float(data.get("steer_curve", DEFAULT_STEER_CURVE))
	wheel.buttons = data.get("buttons", {})
	for joypad in Input.get_connected_joypads():
		if Input.get_joy_guid(joypad) == wheel.guid:
			wheel.attach(joypad)
			break
	Input.joy_connection_changed.connect(wheel._on_joy_connection)
	return wheel


func to_dict() -> Dictionary:
	return {
		"guid": guid, "name": device_name,
		"steer_axis": steer_axis, "steer_center": steer_center, "steer_left": steer_left, "steer_right": steer_right,
		"throttle_axis": throttle_axis, "throttle_rest": throttle_rest, "throttle_full": throttle_full,
		"brake_axis": brake_axis, "brake_rest": brake_rest, "brake_full": brake_full,
		"steer_range": steer_range, "steer_curve": steer_curve, "buttons": buttons,
	}


## The calibration is complete: all axes known, the steering stops on opposite sides of the centre.
func is_valid() -> bool:
	return not guid.is_empty() and steer_axis >= 0 and throttle_axis >= 0 and brake_axis >= 0 \
		and absf(steer_left - steer_center) >= MIN_TRAVEL and absf(steer_right - steer_center) >= MIN_TRAVEL \
		and (steer_left - steer_center) * (steer_right - steer_center) < 0.0 \
		and absf(throttle_full - throttle_rest) >= MIN_TRAVEL and absf(brake_full - brake_rest) >= MIN_TRAVEL


func is_active() -> bool:
	return device >= 0 and is_valid()


## Starts reading a joypad. Axes count as untouched until they change.
func attach(joypad: int) -> void:
	device = joypad
	_initial.clear()
	_moved.clear()


func steer() -> float:
	if not _touched(steer_axis):
		return 0.0
	return steer_value(Input.get_joy_axis(device, steer_axis as JoyAxis), steer_center, steer_left, steer_right,
		steer_range, steer_curve)


func throttle() -> float:
	return _pedal(throttle_axis, throttle_rest, throttle_full)


func brake() -> float:
	return _pedal(brake_axis, brake_rest, brake_full)


func _pedal(axis: int, rest: float, full: float) -> float:
	if not _touched(axis):
		return 0.0
	return pedal_value(Input.get_joy_axis(device, axis as JoyAxis), rest, full)


## Some systems report 0 for an axis until it first moves, which is half throttle for a pedal
## resting at -1: an axis that never changed since attach() counts as released.
func _touched(axis: int) -> bool:
	if _moved.has(axis):
		return true
	var raw := Input.get_joy_axis(device, axis as JoyAxis)
	if not _initial.has(axis):
		_initial[axis] = raw
	if absf(raw - float(_initial[axis])) <= MOVE_EPSILON:
		return false
	_moved[axis] = true
	return true


func _on_joy_connection(joypad: int, connected: bool) -> void:
	if connected and device < 0 and Input.get_joy_guid(joypad) == guid:
		attach(joypad)
	elif not connected and joypad == device:
		device = -1


## Finds the axis being turned to a stop and held there: the largest change since the baseline
## that then stays still. The wheel's left and right stops; only_axis and away_from limit the
## search for the second stop to the same axis and the other side.
class TurnDetector:
	const HOLD_TIME := 0.7  ## s without movement
	const STILL := 0.005

	var axis := -1
	var value := 0.0
	var _baseline: PackedFloat32Array
	var _only_axis: int
	var _away_from: float
	var _last := PackedFloat32Array()
	var _still := 0.0

	func _init(baseline: PackedFloat32Array, only_axis := -1, away_from := 0.0) -> void:
		_baseline = baseline
		_only_axis = only_axis
		_away_from = away_from

	## True once a stop has been found (axis, value).
	func feed(values: PackedFloat32Array, delta: float) -> bool:
		var best := -1
		var best_change := WheelInput.MIN_TRAVEL
		for i in values.size():
			var change := values[i] - _baseline[i]
			if _only_axis >= 0 and i != _only_axis or change * _away_from > 0.0:
				continue
			if absf(change) >= best_change:
				best = i
				best_change = absf(change)
		var moving := best != axis or _last.is_empty() or best >= 0 and absf(values[best] - _last[best]) > STILL
		_last = values
		axis = best
		_still = 0.0 if moving or best < 0 else _still + delta
		if best >= 0:
			value = values[best]
		return best >= 0 and _still >= HOLD_TIME


## Finds a pedal pressed and released again: the axis with the largest excursion from the baseline
## that came back. The rest value is taken after the release, not from the baseline, because an
## untouched axis may report 0 before its first movement.
class PedalDetector:
	const SETTLE_TIME := 0.4  ## s without movement after the release
	const STILL := 0.005
	const RETURNED := 0.5  ## share of the excursion it must come back

	var axis := -1
	var rest := 0.0
	var full := 0.0
	var _baseline: PackedFloat32Array
	var _exclude: int
	var _peak := PackedFloat32Array()
	var _last := PackedFloat32Array()
	var _still := 0.0

	func _init(baseline: PackedFloat32Array, exclude_axis := -1) -> void:
		_baseline = baseline
		_exclude = exclude_axis
		_peak = baseline.duplicate()

	## True once a press and release have been seen (axis, rest, full).
	func feed(values: PackedFloat32Array, delta: float) -> bool:
		var best := -1
		var best_travel := WheelInput.MIN_TRAVEL
		for i in values.size():
			if i == _exclude:
				continue
			if absf(values[i] - _baseline[i]) > absf(_peak[i] - _baseline[i]):
				_peak[i] = values[i]
			var travel := absf(_peak[i] - _baseline[i])
			if travel >= best_travel:
				best = i
				best_travel = travel
		var moving := _last.is_empty() or best != axis or best >= 0 and absf(values[best] - _last[best]) > STILL
		_last = values
		axis = best
		_still = 0.0 if moving or best < 0 else _still + delta
		if best < 0 or absf(values[best] - _peak[best]) < best_travel * RETURNED or _still < SETTLE_TIME:
			return false
		rest = values[best]
		full = _peak[best]
		return true
