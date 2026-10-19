extends Node
## Headless test of the paint colour (Materials.setup_car with a colour):
##   godot --headless --path game res://tests/paint_test.tscn
## Loads the 356 A and the 935, paints them, and checks that paint texels (atlas alpha 204 and the
## stripe zones 153, 166, 179, 230, sills 77) take the colour on average, stripes included, while the other texels and the chrome, lamp and decal materials keep the
## original texture (decals are painted on their body texels like the paint).

const Main := preload("res://scripts/main.gd")
const Materials := preload("res://scripts/materials.gd")
const CARS := ["356Acoupe16", "935race"]
const PAINT := Color("#ff0000")

var failures := 0


func _ready() -> void:
	print("PAINT TEST")
	for key: String in CARS:
		var path := Main.car_model_path(key)
		if not OriginalAssets.exists(path):
			print("  %s: no data, skipped" % key)
			continue
		_check(key, path)
	print("  %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _check(key: String, path: String) -> void:
	var style := Main.car_style_of(key, OriginalAssets.load_json(Main.CAR_COLORS) if OriginalAssets.exists(Main.CAR_COLORS) else null)
	var plain := _materials(_load(path, style), Color(0, 0, 0, 0))
	var painted := _materials(_load(path, style), PAINT)
	_expect(plain.has("paint") and painted.has("paint"), "%s has paint" % key)
	if not plain.has("paint"):
		return
	var before := _rgba((plain["paint"] as StandardMaterial3D).albedo_texture)
	var after := _rgba((painted["paint"] as StandardMaterial3D).albedo_texture)
	var sum := Color(0, 0, 0)
	var n := 0
	var stripe_sum := Color(0, 0, 0)
	var stripes := 0
	var others_same := true
	for y in before.get_height():
		for x in before.get_width():
			var b := before.get_pixel(x, y)
			var a := after.get_pixel(x, y)
			var zone := Materials.paint_zone(b.a8)
			if zone >= 0:
				sum += a
				n += 1
				if Materials.PAINT_ALPHAS[zone] != 204:
					stripe_sum += a
					stripes += 1
			elif not a.is_equal_approx(b):
				others_same = false
	var avg := sum / maxf(n, 1)
	print("  %s: %d paint texels, average %s" % [key, n, avg])
	_expect(n > 0, "%s paint texels" % key)
	_expect(avg.r > 0.6 and avg.g < 0.2 and avg.b < 0.2, "%s paint is red" % key)
	var stripe_avg := stripe_sum / maxf(stripes, 1)
	print("  %s: %d stripe-zone texels, average %s" % [key, stripes, stripe_avg])
	_expect(stripes > 0 and stripe_avg.r > 0.6 and stripe_avg.g < 0.2 and stripe_avg.b < 0.2, "%s stripes are red" % key)
	_expect(others_same, "%s trim texels unchanged" % key)
	for kind: String in ["chrome", "lamp"]:
		if plain.has(kind):
			_expect((painted[kind] as StandardMaterial3D).albedo_texture.get_image().get_data() \
				== (plain[kind] as StandardMaterial3D).albedo_texture.get_image().get_data(), "%s %s untouched" % [key, kind])


## The car's model with its variant's parts and textures, as main.gd loads it.
func _load(path: String, style: int) -> Node3D:
	var model := OriginalAssets.load_gltf(path)
	CarStyle.apply(model, path, style)
	return model


## Exterior-page materials by kind after setup_car.
func _materials(model: Node3D, paint: Color) -> Dictionary:
	Materials.setup_car(model, paint)
	var found := {}
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as StandardMaterial3D
			if m == null or m.resource_name.get_slice(" ", 1) != "exterior":
				continue
			var kind := Materials._car_kind(m.resource_name, String(child.name))
			if not found.has(kind):
				found[kind] = m
	model.free()
	return found


func _rgba(tex: Texture2D) -> Image:
	var img := tex.get_image().duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL ", what)
