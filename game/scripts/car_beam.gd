class_name CarBeam
extends MeshInstance3D
## Low quality at night: the headlights' pool of light on the road as a bright patch laid on the
## ground in front of the car, the way games of the original's time drew it. The track is unshaded
## in low quality (Materials.setup_track), so the headlights' SpotLight3D lights only the other
## cars. The patch is a strip of ROWS rows following the ground ahead (a ray down at each row, so
## it bends over crests and dips instead of cutting into them) and widens and fades with the
## distance, added to the road's colour.

const COLOR := Color(1.0, 0.93, 0.82)  ## CarLights.HEAD_COLOR
const ENERGY := 0.3  ## added at the brightest point
const LENGTH := 30.0  ## m from the front of the car
const NEAR_WIDTH := 3.0  ## m at the front of the car
const FAR_WIDTH := 16.0  ## m at LENGTH
const START := 0.3  ## m in front of the body
const LIFT := 0.12  ## m above the ground, over the car's shadow and the road's small bumps
const ROWS := 10
const RAY_UP := 4.0  ## m above the plane under the car where a row's ray starts
const RAY_DOWN := 8.0  ## m below it where the ray ends
const TEXTURE_SIZE := Vector2i(64, 128)

static var _texture: Texture2D

var _car: Car
var _front := 2.0  ## m from the wheels' centre to the front of the body
var _strip := ImmediateMesh.new()
var _material: StandardMaterial3D


func setup(car: Car, front: float) -> void:
	_car = car
	_front = front
	name = "Beam"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _strip
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, ENERGY)
	material.albedo_texture = _pool()
	material.disable_fog = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
	_material = material
	car.add_child(self)


func _process(_delta: float) -> void:
	if _car == null or _car.wheels.is_empty():
		return
	global_transform = Transform3D.IDENTITY
	var frame := CarShadow.ground_frame(_car)
	var up := frame.basis.y
	var ahead := -frame.basis.z
	var side := frame.basis.x * (FAR_WIDTH / 2.0)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [_car.get_rid()]
	_strip.clear_surfaces()
	_strip.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for i in ROWS + 1:
		var t := float(i) / ROWS
		var p := frame.origin + ahead * (_front + START + LENGTH * t)
		query.from = p + up * RAY_UP
		query.to = p - up * RAY_DOWN
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and not hit["collider"] is Car:  # not on the roof of a car ahead
			p = hit["position"]
		p += up * LIFT
		_strip.surface_set_uv(Vector2(0.0, 1.0 - t))
		_strip.surface_add_vertex(p - side)
		_strip.surface_set_uv(Vector2(1.0, 1.0 - t))
		_strip.surface_add_vertex(p + side)
	_strip.surface_end()


## Trapezoid, NEAR_WIDTH at the car (bottom of the texture, +Z of the plane) to FAR_WIDTH at the
## far end; bright near the car, fading with the distance and to the sides.
static func _pool() -> Texture2D:
	if _texture != null:
		return _texture
	var img := Image.create(TEXTURE_SIZE.x, TEXTURE_SIZE.y, false, Image.FORMAT_LA8)
	for y in TEXTURE_SIZE.y:
		var d := 1.0 - (y + 0.5) / TEXTURE_SIZE.y  # 0 at the car, 1 at the far end
		var half := lerpf(NEAR_WIDTH, FAR_WIDTH, d) / FAR_WIDTH  # share of the full width
		var along := smoothstep(0.0, 0.1, d) * pow(1.0 - d, 1.5)
		for x in TEXTURE_SIZE.x:
			var u := absf((x + 0.5) / TEXTURE_SIZE.x * 2.0 - 1.0) / half
			var a := along * (1.0 - smoothstep(0.15, 1.0, u))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_texture = ImageTexture.create_from_image(img)
	return _texture
