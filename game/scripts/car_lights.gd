extends Node3D
## Car lamps (IDEA-009 section 3, D-019): at night headlights (SpotLight3D with shadows, one per
## side) and glowing lamp glass; tail lights glow at night and brighter under the brake, day or
## night, with a small red OmniLight3D per side.
## The lamps are the model's "Light*" parts (exterior page, tools/crp2gltf.py): the car front is
## -Z, so parts ahead of the centre are head lamps, behind it tail lamps. Their glass gets its
## own material copy with the texture as emission, tinted warm white at the front, red at the back.
## Parts near the centre line (the 935's light bars) light up but get no light of their own.

const HEAD_COLOR := Color(1.0, 0.93, 0.82)
## Reach on the road about 2x the first version (energy 8, range 90 m, decay 1.2, pitch -3, whose
## beam centre hit the road 11 m ahead), computed with Godot's light attenuation.
const HEAD_ENERGY := 17.0
const HEAD_RANGE := 200.0
const HEAD_DECAY := 1.0  ## distance falloff exponent (spot_attenuation)
const HEAD_ANGLE := 26.0  ## degrees, half angle of the cone
const HEAD_PITCH := -2.0  ## degrees, aimed slightly down
const HEAD_AHEAD := 0.15  ## m in front of the lamp, so its own glass does not shadow it
## Shadows: the near-horizontal beam grazes the low-poly terrain, which with the default biases
## shadowed itself in hard dark bands. Larger biases remove them; light_size turns on soft (PCSS)
## edges. Neither costs measurable FPS (M1 Pro, farmland at night).
const HEAD_SHADOW_BIAS := 0.15
const HEAD_SHADOW_NORMAL_BIAS := 3.0
const HEAD_LIGHT_SIZE := 0.2  ## m, lamp size for the soft shadow edge
const TAIL_COLOR := Color(1.0, 0.08, 0.04)
const TAIL_ENERGY := 0.06
const BRAKE_ENERGY := 0.35
const TAIL_RANGE := 2.0
const HEAD_EMISSION := 2.0
const TAIL_EMISSION := 1.5
const BRAKE_EMISSION := 5.0
const BRAKE_ON := 0.05  ## brake pedal above this lights the brake lights
const SIDE_MIN_X := 0.2  ## m from the centre line for a lamp to count as left or right
## The lights skip the car's own visual layer (Materials.CAR_LAYER): no red glow in the cabin,
## no headlight hot spots on the bonnet.
const CULL_MASK := ~Materials.CAR_LAYER & 0xFFFFF
const Materials := preload("res://scripts/materials.gd")

var night := false
var headlights: Array[SpotLight3D] = []
var tail_lights: Array[OmniLight3D] = []
var _car: Node3D
var _head_materials: Array[StandardMaterial3D] = []
var _tail_materials: Array[StandardMaterial3D] = []
var _braking := false


## Builds the lights from the model's lamp parts (model already added to the car).
func setup(car: Node3D, model: Node3D, is_night: bool) -> void:
	_car = car
	night = is_night
	name = "Lights"
	var lamps := {"head": {-1: [], 1: []}, "tail": {-1: [], 1: []}}
	var to_car := car.global_transform.affine_inverse()
	for mi: MeshInstance3D in model.find_children("Light*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var box := (to_car * mi.global_transform) * mi.get_aabb()
		var centre := box.get_center()
		var kind := "head" if centre.z < 0.0 else "tail"
		if kind == "head":
			_make_emissive(mi, HEAD_COLOR, _head_materials)
		else:
			_make_emissive(mi, TAIL_COLOR, _tail_materials)
		if absf(centre.x) >= SIDE_MIN_X:
			# Head lamps: the front face of the box; tail lamps: its centre.
			var at := Vector3(centre.x, centre.y, box.position.z) if kind == "head" else centre
			lamps[kind][1 if centre.x > 0.0 else -1].append(at)
	for side: int in [-1, 1]:
		var head: Array = lamps["head"][side]
		if not head.is_empty():
			headlights.append(_headlight(_average(head)))
		var tail: Array = lamps["tail"][side]
		if not tail.is_empty():
			tail_lights.append(_tail_light(_average(tail)))
	_update(true)


func _headlight(at: Vector3) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.position = at + Vector3(0.0, 0.0, -HEAD_AHEAD)
	light.rotation_degrees = Vector3(HEAD_PITCH, 0.0, 0.0)  # default spot points along -Z, as the car
	light.light_color = HEAD_COLOR
	light.light_energy = HEAD_ENERGY
	light.spot_range = HEAD_RANGE
	light.spot_angle = HEAD_ANGLE
	light.spot_angle_attenuation = 0.6
	light.spot_attenuation = HEAD_DECAY
	light.shadow_enabled = true
	light.shadow_bias = HEAD_SHADOW_BIAS
	light.shadow_normal_bias = HEAD_SHADOW_NORMAL_BIAS
	light.light_size = HEAD_LIGHT_SIZE
	light.light_cull_mask = CULL_MASK
	add_child(light)
	return light


func _tail_light(at: Vector3) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = at + Vector3(0.0, 0.0, 0.15)
	light.light_color = TAIL_COLOR
	light.omni_range = TAIL_RANGE
	light.shadow_enabled = false
	light.light_cull_mask = CULL_MASK
	add_child(light)
	return light


## Gives every surface of the lamp part its own emissive copy of the material, the texture
## tinted with `tint` (the chrome rings of the tail lamps glow red, not white).
func _make_emissive(mi: MeshInstance3D, tint: Color, out: Array[StandardMaterial3D]) -> void:
	for surface in mi.mesh.get_surface_count():
		var base := mi.get_active_material(surface) as StandardMaterial3D
		if base == null:
			continue
		var m := base.duplicate() as StandardMaterial3D
		m.emission_enabled = true
		m.emission = tint
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = 0.0
		mi.set_surface_override_material(surface, m)
		out.append(m)


func _average(points: Array) -> Vector3:
	var sum := Vector3.ZERO
	for p: Vector3 in points:
		sum += p
	return sum / points.size()


func set_night(value: bool) -> void:
	night = value
	_update(true)


func _process(_delta: float) -> void:
	_update(false)


func _update(force: bool) -> void:
	var braking: bool = _car != null and float(_car.get("brake")) > BRAKE_ON
	if braking == _braking and not force:
		return
	_braking = braking
	for light in headlights:
		light.visible = night
	for m in _head_materials:
		m.emission_energy_multiplier = HEAD_EMISSION if night else 0.0
	var tail_energy := BRAKE_ENERGY if braking else (TAIL_ENERGY if night else 0.0)
	for light in tail_lights:
		light.light_energy = tail_energy
		light.visible = tail_energy > 0.0
	for m in _tail_materials:
		m.emission_energy_multiplier = BRAKE_EMISSION if braking else (TAIL_EMISSION if night else 0.0)
