extends TextureRect
## Selected car turning slowly in the menu porthole (one turn a minute): the car's original model
## with its style and paint (as main.gd builds it, without physics), lit in its own 3D world and
## rendered into a transparent SubViewport at the screen's real pixel size, so it stays sharp.

const Main := preload("res://scripts/main.gd")
const CarStyle := preload("res://scripts/car_style.gd")
const Materials := preload("res://scripts/materials.gd")
const TURN_SPEED := TAU / 60.0  ## rad/s, 360 degrees a minute
const START_YAW := deg_to_rad(35.0)
const PITCH := deg_to_rad(-11.0)  ## camera looking down
const FOV := 20.0  ## vertical, degrees
const MARGIN := 1.08

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D
var _shown := ""  ## "key|color" on screen


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	# The project's MetalFX upscaling drops alpha: render natively.
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_viewport.scaling_3d_scale = 1.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_viewport.add_child(_environment())
	for light: Array in [[Vector3(-38, 30, 0), 1.0], [Vector3(-20, -150, 0), 0.35]]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = light[0]
		sun.light_energy = light[1]
		_viewport.add_child(sun)
	_pivot = Node3D.new()
	_pivot.rotation.y = START_YAW
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_viewport.add_child(_camera)
	texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
	_fit_viewport()


func _process(delta: float) -> void:
	_pivot.rotation.y = wrapf(_pivot.rotation.y + TURN_SPEED * delta, 0.0, TAU)
	_fit_viewport()


## Shows car `key` (main.gd CARS) in `color` ("#rrggbb", "" = untinted); empty key clears the view.
func show_car(key: String, color: String, car_colors: Variant) -> void:
	if _shown == key + "|" + color:
		return
	_shown = key + "|" + color
	if _model != null:
		_model.queue_free()
		_model = null
	if key.is_empty() or not OriginalAssets.exists(Main.car_model_path(key)):
		return
	var model_path := Main.car_model_path(key)
	_model = OriginalAssets.load_gltf(model_path)
	if _model == null:
		return
	CarStyle.apply(_model, model_path, Main.car_style_of(key, car_colors))
	Materials.setup_car(_model, Color.from_string(color, Color(0, 0, 0, 0)) if not color.is_empty() else Color(0, 0, 0, 0))
	_pivot.add_child(_model)
	_frame(_bounds(_model))


## The car centred on the pivot, the camera far enough to keep it whole at every angle.
func _frame(box: AABB) -> void:
	_model.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var reach := Vector2(box.size.x, box.size.z).length() * 0.5  ## footprint radius, any angle
	var aspect := size.x / maxf(size.y, 1.0)
	var half_h := atan(tan(deg_to_rad(FOV * 0.5)) * aspect)
	var distance := reach * MARGIN / tan(half_h) + reach
	var target := Vector3(0, box.size.y * 0.42, 0)
	_camera.position = target + Vector3(0, -sin(PITCH), cos(PITCH)) * distance
	_camera.look_at(target)


static func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var part := _to_model(mesh, model) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


static func _to_model(node: Node3D, model: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != model and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Neutral studio light and reflections from a grey procedural sky; the background stays clear.
static func _environment() -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.62, 0.64, 0.66)
	sky_material.sky_horizon_color = Color(0.85, 0.84, 0.8)
	sky_material.ground_horizon_color = Color(0.45, 0.44, 0.42)
	sky_material.ground_bottom_color = Color(0.15, 0.15, 0.15)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	return world


## Viewport in real screen pixels (the menu canvas is scaled to the window).
func _fit_viewport() -> void:
	var px := Vector2i((size * get_global_transform_with_canvas().get_scale()).round())
	if px.x > 0 and px.y > 0 and _viewport.size != px:
		_viewport.size = px
