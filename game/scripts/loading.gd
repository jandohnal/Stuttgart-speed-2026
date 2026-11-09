extends Control
## Web only: downloads the packs of the next scene with a progress bar. It is the first scene of
## the web build (the menu needs the core pack, which also holds the menu's fonts and icons, so
## this screen uses the default theme), then runs before every race.

const MENU_SCENE := "res://scenes/menu.tscn"
const BACKGROUND := Color("#161512")

var _bar: ProgressBar
var _status: Label


func _ready() -> void:
	_build_ui()
	var scene := DataPacks.next_scene if not DataPacks.next_scene.is_empty() else MENU_SCENE
	var packs := DataPacks.next_packs if not DataPacks.next_scene.is_empty() else ["core"]
	DataPacks.next_scene = ""
	if not await DataPacks.ensure(packs):
		set_process(false)
		_status.text = DataPacks.error
		return
	set_process(false)
	_bar.value = 1.0
	_status.text = "Preparing…"
	# Let the text show: the next scene blocks while it builds, and its first frame takes seconds.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(scene)


func _process(_delta: float) -> void:
	_bar.value = DataPacks.progress()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 420
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var title := Label.new()
	title.text = "STUTTGART SPEED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 8
	column.add_child(_bar)
	_status = Label.new()
	_status.text = "Downloading game data…"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
