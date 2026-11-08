extends AcceptDialog
## Wheel setup in the menu (D-038): pick the device, then a guided calibration measures the axes
## (WheelInput detectors) and the buttons. Ends on a review page with live bars and the steering
## range and curve sliders; only Save writes anything (GameSettings.wheel, user://settings.cfg).
## The joypad is polled, not read from events, and the focus is released while waiting for a wheel
## button, so that a button the system maps to ui_accept cannot press a dialog button.

const MenuTheme := preload("res://ui/theme/menu_theme.gd")

enum Page { DEVICE, CENTER, LEFT, RIGHT, THROTTLE, BRAKE, BUTTON, REVIEW }

const SIZE := Vector2i(760, 480)
const SKIP := "skip"
const REMOVE := "remove"
const ADJUST := "adjust"
const NO_DEVICE := "No wheel or joypad found. Connect it and wait a moment; if it does not appear, check that the system sees it (some wheels need the maker's driver or another mode)."
const PROMPTS := {
	Page.DEVICE: "Choose the wheel, then calibrate it.",
	Page.CENTER: "Centre the wheel and take your feet off the pedals, then press Next.",
	Page.LEFT: "Turn the wheel fully LEFT to its stop and hold it there.",
	Page.RIGHT: "Now turn the wheel fully RIGHT to its stop and hold it there.",
	Page.THROTTLE: "Press the THROTTLE pedal all the way down, then let it go.",
	Page.BRAKE: "Press the BRAKE pedal all the way down, then let it go.",
	Page.REVIEW: "Try the wheel and pedals. Steering range: how far to turn for full lock. Curve: gentler around the centre.",
}

var page := Page.DEVICE
var draft := WheelInput.new()  ## the mapping being measured; the saved one changes only on Save
var turn: WheelInput.TurnDetector
var pedal: WheelInput.PedalDetector

var _center := PackedFloat32Array()  ## all axes with the wheel centred and the pedals released
var _joypads: Array[int] = []
var _actions: Array = []  ## actions still waiting for a button
var _held := {}  ## buttons pressed before the step began; they count once released
var _prompt: Label
var _status: Label
var _device_option: OptionButton
var _review: GridContainer
var _steer_bar: ProgressBar
var _throttle_bar: ProgressBar
var _brake_bar: ProgressBar
var _range_slider: HSlider
var _curve_slider: HSlider
var _skip_button: Button
var _remove_button: Button
var _adjust_button: Button


func _ready() -> void:
	title = "WHEEL SETUP"
	size = SIZE
	dialog_hide_on_ok = false
	exclusive = true
	wrap_controls = false  # the wrapped prompts would stretch the window far past the screen
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(SIZE.x - 40, 0)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	_prompt = _label(&"CreditsText")
	box.add_child(_prompt)
	_device_option = OptionButton.new()
	_device_option.theme_type_variation = &"SetupDropdown"
	box.add_child(_device_option)
	_status = _label(&"CreditsNote")
	box.add_child(_status)
	_review = GridContainer.new()
	_review.columns = 2
	_review.add_theme_constant_override("h_separation", 16)
	_review.add_theme_constant_override("v_separation", 10)
	box.add_child(_review)
	_steer_bar = _add_bar("STEERING", -1.0)
	_throttle_bar = _add_bar("THROTTLE", 0.0)
	_brake_bar = _add_bar("BRAKE", 0.0)
	_range_slider = _add_slider("STEERING RANGE", WheelInput.MIN_STEER_RANGE, 1.0)
	_curve_slider = _add_slider("CURVE", 1.0, 2.5)
	_skip_button = add_button("skip", false, SKIP)
	_adjust_button = add_button("adjust", false, ADJUST)
	_remove_button = add_button("remove", false, REMOVE)
	add_cancel_button("close")
	confirmed.connect(_on_ok)
	custom_action.connect(_on_custom)
	Input.joy_connection_changed.connect(_on_joy_connection)


## Opens on the device page, showing the saved wheel if there is one.
func open() -> void:
	_show_page(Page.DEVICE)
	popup_centered(SIZE)


func _label(variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _add_row_label(text_value: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"SetupLabel"
	label.text = text_value
	_review.add_child(label)


func _add_bar(caption: String, low: float) -> ProgressBar:
	_add_row_label(caption)
	var bar := ProgressBar.new()
	bar.min_value = low
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 22)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := StyleBoxFlat.new()
	back.bg_color = MenuTheme.FIELD_BG
	back.set_border_width_all(2)
	back.border_color = MenuTheme.BORDER
	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuTheme.ACCENT
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	_review.add_child(bar)
	return bar


func _add_slider(caption: String, low: float, high: float) -> HSlider:
	_add_row_label(caption)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_slider.unbind(1))
	_review.add_child(slider)
	return slider


func _show_page(new_page: Page) -> void:
	page = new_page
	_prompt.text = PROMPTS.get(page, "")
	_status.text = ""
	_device_option.visible = page == Page.DEVICE
	_review.visible = page == Page.REVIEW
	_skip_button.visible = page == Page.BUTTON
	_remove_button.visible = page == Page.DEVICE and not GameSettings.wheel.is_empty()
	_adjust_button.visible = false
	var ok := get_ok_button()
	ok.visible = page in [Page.DEVICE, Page.CENTER, Page.REVIEW]
	ok.disabled = false
	match page:
		Page.DEVICE:
			ok.text = "calibrate"
			_fill_devices()
		Page.CENTER:
			ok.text = "next"
		Page.LEFT:
			turn = WheelInput.TurnDetector.new(_center)
		Page.RIGHT:
			turn = WheelInput.TurnDetector.new(_center, draft.steer_axis, draft.steer_left - draft.steer_center)
		Page.THROTTLE, Page.BRAKE:
			pedal = WheelInput.PedalDetector.new(_axes(), draft.steer_axis)
		Page.BUTTON:
			_next_button()
		Page.REVIEW:
			ok.text = "save"
			ok.disabled = not draft.is_valid()
			_range_slider.set_value_no_signal(draft.steer_range)
			_curve_slider.set_value_no_signal(draft.steer_curve)
			if not draft.is_valid():
				_status.text = "The calibration did not measure valid axes. Close and calibrate again."
	if ok.visible and not ok.disabled:
		ok.grab_focus()


func _fill_devices() -> void:
	_device_option.clear()
	_joypads.clear()
	var saved_guid := str(GameSettings.wheel.get("guid", ""))
	var saved_index := -1
	for joypad in Input.get_connected_joypads():
		if Input.get_joy_guid(joypad) == saved_guid:
			saved_index = _joypads.size()
		_joypads.append(joypad)
		_device_option.add_item(Input.get_joy_name(joypad))
	var found := not _joypads.is_empty()
	_device_option.visible = found
	if saved_index >= 0:
		_device_option.select(saved_index)
	_prompt.text = PROMPTS[Page.DEVICE] if found else NO_DEVICE
	get_ok_button().visible = found
	_adjust_button.visible = saved_index >= 0
	if not GameSettings.wheel.is_empty():
		_status.text = "Saved: %s" % GameSettings.wheel.get("name", "")
		if saved_index < 0:
			_status.text += " (not connected)"


func _axes() -> PackedFloat32Array:
	return WheelInput.read_axes(draft.device)


## Next button to assign, or on to the review when all were asked. Buttons held now do not count.
func _next_button() -> void:
	if _actions.is_empty():
		_show_page(Page.REVIEW)
		return
	_prompt.text = "Press the wheel button for %s (Space = skip)." % WheelInput.BUTTON_ACTIONS[_actions[0]]
	_held.clear()
	for button in WheelInput.BUTTONS:
		if Input.is_joy_button_pressed(draft.device, button as JoyButton):
			_held[button] = true


func _assign_button(button: int) -> void:
	draft.buttons[_actions.pop_front()] = button
	_next_button()


func _skip() -> void:
	_actions.pop_front()
	_next_button()


func _start_calibration() -> void:
	var joypad: int = _joypads[_device_option.selected]
	var guid := Input.get_joy_guid(joypad)
	draft = WheelInput.new()
	draft.guid = guid
	draft.device_name = Input.get_joy_name(joypad)
	draft.attach(joypad)
	if GameSettings.wheel.get("guid", "") == guid:  # keep the player's tuning
		draft.steer_range = GameSettings.wheel.get("steer_range", draft.steer_range)
		draft.steer_curve = GameSettings.wheel.get("steer_curve", draft.steer_curve)
	_show_page(Page.CENTER)


func _on_ok() -> void:
	match page:
		Page.DEVICE:
			if not _joypads.is_empty():
				_start_calibration()
		Page.CENTER:
			_center = _axes()
			_show_page(Page.LEFT)
		Page.REVIEW:
			GameSettings.wheel = draft.to_dict()
			GameSettings.save_wheel()
			hide()


func _on_custom(action: StringName) -> void:
	match action:
		SKIP:
			_skip()
		ADJUST:
			draft = WheelInput.from_dict(GameSettings.wheel)
			_show_page(Page.REVIEW)
		REMOVE:
			GameSettings.wheel = {}
			GameSettings.save_wheel()
			_show_page(Page.DEVICE)


func _on_slider() -> void:
	if page == Page.REVIEW:
		draft.steer_range = _range_slider.value
		draft.steer_curve = _curve_slider.value


func _on_joy_connection(joypad: int, connected: bool) -> void:
	if not visible:
		return
	if page == Page.DEVICE or not connected and joypad == draft.device:
		_show_page(Page.DEVICE)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if page == Page.BUTTON and visible and key != null and key.pressed and not key.echo \
			and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		set_input_as_handled()
		_skip()


func _process(delta: float) -> void:
	if not visible:
		return
	match page:
		Page.LEFT:
			if _feed_turn(delta):
				draft.steer_axis = turn.axis
				draft.steer_center = _center[turn.axis]
				draft.steer_left = turn.value
				_show_page(Page.RIGHT)
		Page.RIGHT:
			if _feed_turn(delta):
				draft.steer_right = turn.value
				_show_page(Page.THROTTLE)
		Page.THROTTLE:
			if _feed_pedal(delta):
				draft.throttle_axis = pedal.axis
				draft.throttle_rest = pedal.rest
				draft.throttle_full = pedal.full
				_show_page(Page.BRAKE)
		Page.BRAKE:
			if _feed_pedal(delta):
				draft.brake_axis = pedal.axis
				draft.brake_rest = pedal.rest
				draft.brake_full = pedal.full
				draft.buttons = {}
				_actions = WheelInput.BUTTON_ACTIONS.keys()
				_show_page(Page.BUTTON)
		Page.BUTTON:
			gui_release_focus()
			_poll_buttons()
		Page.REVIEW:
			if draft.is_active():
				_steer_bar.value = draft.steer()
				_throttle_bar.value = draft.throttle()
				_brake_bar.value = draft.brake()


func _feed_turn(delta: float) -> bool:
	var values := _axes()
	var done := turn.feed(values, delta)
	_show_axis(turn.axis, values)
	return done


func _feed_pedal(delta: float) -> bool:
	var values := _axes()
	var done := pedal.feed(values, delta)
	_show_axis(pedal.axis, values)
	return done


func _show_axis(axis: int, values: PackedFloat32Array) -> void:
	_status.text = "Axis %d: %+.2f" % [axis, values[axis]] if axis >= 0 else "Waiting for movement…"


func _poll_buttons() -> void:
	for button in WheelInput.BUTTONS:
		var pressed := Input.is_joy_button_pressed(draft.device, button as JoyButton)
		if _held.has(button):
			if not pressed:
				_held.erase(button)
		elif pressed:
			_assign_button(button)
			return
