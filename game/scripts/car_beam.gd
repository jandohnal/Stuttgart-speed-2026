class_name CarBeam
extends MeshInstance3D
## Low quality at night: the headlights' light on the track the way the original draws it
## (Porsche.exe FUN_00452910, the LayerVertexLight layers of a night track's render methods, IDEA-015).
## The original takes every track vertex into the player's car's frame and looks the light up in the
## texture nght (GameData/Render/night.psh, 128 x 128 grey): row = metres ahead x AHEAD_SCALE
## (0..127, about 99 m), column = metres to the side x SIDE_SCALE + 64 (+-63, about +-17 m);
## light = (texel - |height above or below the car| x 32) / 256, in colour 0xFF808080.
## The track is unshaded in low quality (Materials.setup_track), so the headlights' SpotLight3D lights
## only the other cars. The light here is a grid of ROWS x COLUMNS points laid on the ground ahead
## (a ray down at each point, so it bends over crests and dips; walls, drops and cells spanning
## a guard rail get no light), drawn
## additively by shaders/car_beam.gdshader. Without nght (old decomposed/) a drawn oval stands in.

const POOL := "GameData/Render/night/index.json"  ## fsh2png of night.psh, entry nght
const SHADER := preload("res://shaders/car_beam.gdshader")
const AHEAD_SCALE := 1.28  ## texels per metre ahead (0x61BD54)
const SIDE_SCALE := 3.62  ## texels per metre to the side (0x61BD58)
const TEXELS := 128.0
const COLOR := Color(0.5, 0.5, 0.5)  ## 0xFF808080; added to the track (hypothesis: the original may modulate)
const LIFT := 0.12  ## m above the ground, over the car's shadow and the road's small bumps
const ROWS := 16
const COLUMNS := 7
const MIN_GROUND_UP := 0.7  ## a hit whose normal leans more (wall, kerb face) is no ground: no light there
const MAX_STEP := 1.0  ## m of height between a cell's corners above which the cell is left out (guard rail tops)
const RAY_UP := 4.0  ## m above the plane under the car where a point's ray starts
const RAY_DOWN := 8.0  ## m below it where the ray ends
const MISSED := 100.0  ## m of height given to a point without ground: no light there

static var _texture: Texture2D

var _car: Car
var _strip := ImmediateMesh.new()
var _material: ShaderMaterial
var _length := (TEXELS - 1.0) / AHEAD_SCALE  ## m ahead covered by the texture
var _half_width := (TEXELS / 2.0 - 1.0) / SIDE_SCALE  ## m to each side


## front: kept for the callers (CarShadow.front_reach); the original's light starts at the car's origin.
func setup(car: Car, _front := 0.0) -> void:
	_car = car
	name = "Beam"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _strip
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("pool", pool_texture())
	_material.set_shader_parameter("color", Vector3(COLOR.r, COLOR.g, COLOR.b))
	material_override = _material
	car.add_child(self)


func _process(_delta: float) -> void:
	if _car == null or _car.wheels.is_empty() or not visible:
		return
	global_transform = Transform3D.IDENTITY
	var frame := CarShadow.ground_frame(_car)
	var origin := _car.global_position  # the original measures from the car's position
	var up := frame.basis.y
	var ahead := -frame.basis.z
	var right := frame.basis.x
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [_car.get_rid()]
	var grid: Array[PackedVector3Array] = []
	var heights: Array[PackedFloat32Array] = []
	for i in ROWS + 1:
		var row := PackedVector3Array()
		var row_heights := PackedFloat32Array()
		var along := _length * float(i) / ROWS
		for j in COLUMNS:
			var across := lerpf(-_half_width, _half_width, float(j) / (COLUMNS - 1))
			var p := frame.origin + ahead * along + right * across
			query.from = p + up * RAY_UP
			query.to = p - up * RAY_DOWN
			var hit := space.intersect_ray(query)
			var height := MISSED
			# Ground only: not the roof of a car ahead, not a wall.
			if not hit.is_empty() and not hit["collider"] is Car and (hit["normal"] as Vector3).dot(up) >= MIN_GROUND_UP:
				p = hit["position"]
				height = absf((p - origin).dot(up))
			row.append(p + up * LIFT)
			row_heights.append(height)
		grid.append(row)
		heights.append(row_heights)
	_strip.clear_surfaces()
	_strip.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for i in ROWS:
		for j in COLUMNS - 1:
			var lo := INF
			var hi := -INF
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)]:
				var h := (grid[i + corner.x][j + corner.y] - origin).dot(up)
				lo = minf(lo, h)
				hi = maxf(hi, h)
			if hi - lo > MAX_STEP:
				continue
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0)]:
				var r := i + corner.x
				var c := j + corner.y
				# Texel centres: row 0..127 ahead, column 64 +-63 across. The original's x is mirrored
				# (tools/crp.py), so the car's left (c = 0) is column 127.
				var column := TEXELS / 2.0 + (TEXELS / 2.0 - 1.0) * (1.0 - 2.0 * c / (COLUMNS - 1))
				var row_texel := (TEXELS - 1.0) * r / ROWS
				_strip.surface_set_uv(Vector2(column + 0.5, row_texel + 0.5) / TEXELS)
				_strip.surface_set_uv2(Vector2(heights[r][c], 0.0))
				_strip.surface_add_vertex(grid[r][c])
	_strip.surface_end()


## The original's nght texture, else a drawn oval of the same size.
static func pool_texture() -> Texture2D:
	if _texture != null:
		return _texture
	var index: Variant = OriginalAssets.load_json(POOL) if OriginalAssets.exists(POOL) else null
	if index is Dictionary:
		for e: Dictionary in index.get("entries", []):
			if e.get("name") == "nght" and e.has("file"):
				var image := Image.load_from_file(OriginalAssets.path(POOL.get_base_dir().path_join(e["file"])))
				if image != null and not image.is_empty():
					_texture = ImageTexture.create_from_image(image)
					return _texture
	push_warning("%s missing - run tools/fsh2png.py (the headlight light is drawn instead)" % POOL)
	var img := Image.create(int(TEXELS), int(TEXELS), false, Image.FORMAT_L8)
	for y in int(TEXELS):
		for x in int(TEXELS):
			var d := Vector2((x + 0.5) / TEXELS * 2.0 - 1.0, (y + 0.5) / TEXELS * 2.0 - 1.0).length()
			img.set_pixel(x, y, Color.WHITE * (1.0 - smoothstep(0.5, 1.0, d)))
	_texture = ImageTexture.create_from_image(img)
	return _texture
