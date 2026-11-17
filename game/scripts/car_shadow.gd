class_name CarShadow
extends MeshInstance3D
## Low quality: a soft dark blob on the ground under a car instead of shadows computed while
## running, as in the original (docs/formats/shadow.md: GameData/CarModel/Shadow.fsh under the car).
## The original's shape under the car is not decoded, so the blob is a rounded rectangle generated
## here, the size of the body's outline plus MARGIN. It lies on the plane through the wheels'
## contact points (it tilts with the road, not with the body's roll) and fades while the car is in
## the air, gone FADE_HEIGHT m above its height at rest.

const ALPHA := 0.75  ## darkest point
const MARGIN := 1.3  ## blob size / body outline
const EDGE := 0.4  ## share of each half that fades out
const LIFT := 0.03  ## m above the ground along its normal
const FADE_HEIGHT := 1.5
const TEXTURE_SIZE := Vector2i(32, 64)

static var _texture: Texture2D

var _car: Car
var _offset := Vector3.ZERO  ## centre of the body's outline from the wheels' centre, car space
var _rest := NAN  ## height of the body over the blob at rest
var _material: StandardMaterial3D
## m from the wheels' centre to the front of the body (CarBeam).
var front_reach := 2.0


func setup(car: Car, model: Node3D) -> void:
	_car = car
	name = "Shadow"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := _outline(model)
	var wheels := Vector3.ZERO
	for w in car.wheels:
		wheels += w.center
	wheels /= maxi(car.wheels.size(), 1)
	_offset = Vector3(box.get_center().x - wheels.x, 0.0, box.get_center().z - wheels.z)
	front_reach = wheels.z - box.position.z
	var plane := PlaneMesh.new()
	plane.size = Vector2(box.size.x, box.size.z) * MARGIN
	mesh = plane
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(0, 0, 0, ALPHA)
	_material.albedo_texture = _blob()
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material_override = _material
	car.add_child(self)


func _process(_delta: float) -> void:
	if _car == null or _car.wheels.is_empty():
		return
	var frame := ground_frame(_car)
	frame.origin += frame.basis * _offset
	var height := (_car.global_position - frame.origin).dot(frame.basis.y)
	if is_nan(_rest):
		_rest = height
	_material.albedo_color.a = ALPHA * clampf(1.0 - (height - _rest) / FADE_HEIGHT, 0.0, 1.0)
	frame.origin += frame.basis.y * LIFT
	global_transform = frame


## The ground under a car: the plane through its wheels' contact points (the end of a wheel's ray
## when it is in the air), origin in their middle, -Z towards the front, Y the ground's normal.
static func ground_frame(car: Car) -> Transform3D:
	var center := Vector3.ZERO
	var front := Vector3.ZERO
	var rear := Vector3.ZERO
	var normal := Vector3.ZERO
	for w in car.wheels:
		var p := w.point if w.contact else w.ray.to_global(w.ray.target_position)
		center += p
		if w.front:
			front += p
		else:
			rear += p
		normal += w.normal if w.contact else Vector3.UP
	center /= float(car.wheels.size())
	normal = normal.normalized()
	var forward := (front - rear).normalized()
	if forward.is_zero_approx():
		forward = -car.global_basis.z
	var right := forward.cross(normal).normalized()
	forward = normal.cross(right)
	return Transform3D(Basis(right, normal, -forward), center)


## Outline of the car's meshes in the car's space.
func _outline(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var to_car := _car.global_transform.affine_inverse() * mi.global_transform \
			if mi.is_inside_tree() else _relative(mi, model)
		var b := to_car * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box if not first else AABB(Vector3(-0.85, 0, -2.1), Vector3(1.7, 1.3, 4.2))


func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return root.transform * t


## Rounded rectangle, full in the middle and fading over EDGE of each half to the border.
static func _blob() -> Texture2D:
	if _texture != null:
		return _texture
	var img := Image.create(TEXTURE_SIZE.x, TEXTURE_SIZE.y, false, Image.FORMAT_LA8)
	for y in TEXTURE_SIZE.y:
		for x in TEXTURE_SIZE.x:
			var u := absf((x + 0.5) / TEXTURE_SIZE.x * 2.0 - 1.0)
			var v := absf((y + 0.5) / TEXTURE_SIZE.y * 2.0 - 1.0)
			var a := smoothstep(1.0, 1.0 - EDGE, u) * smoothstep(1.0, 1.0 - EDGE, v)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_texture = ImageTexture.create_from_image(img)
	return _texture
