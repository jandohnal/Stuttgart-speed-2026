class_name LightDecals
extends Node
## The original's light decals on the cars (D-044, docs/formats/map.md): <track>_decals.json from
## tools/light_decals.py lists road slice ranges with three textures from <track>.env. While a car
## is on such a slice, its materials get a next pass (shaders/light_decal.gdshader) with the
## texture of their tier, as Porsche.exe does per car each frame:
## - the section is the first whose [first, last] holds the car's slice; outside all sections the
##   car has no decal,
## - tier 1 / 2 / 3 = texture1 / 2 / 3: the original picks it by a material value (< 0.05, < 0.95,
##   otherwise). Mapped here by kind: interior and wheels 1, body 2, chrome and glass 3 (texture3 is
##   the stronger variant, twice the alpha),
## - "covered" textures under a roof, "open" ones under the sky: the original takes the nearest
##   surface more than 3.5 m above the car (FUN_00473330) and checks its roof flags; here a ray up
##   from 3.5 m above the car against the track collision (road, terrain, objects). Monte Carlo 3-5
##   and foothills have their tunnel lamps only in "covered",
## - UV offset: the car's offset from its slice along the slice's right vector / 60 and forward
##   vector / 6 (one scroll of the texture per slice).

const SHADER := preload("res://shaders/light_decal.gdshader")
const SLICE_METRES := 6.0  ## Porsche.exe scales the slice offset by 1/6
const LATERAL_FACTOR := 0.1  ## and the lateral one again by 0.1
## Car kinds (Materials.setup_car) per tier; decals keep only the body pass under them (their
## cut-out quads would show the light outside the print).
const TIERS := {
	"interior": 0, "extint": 0, "underbody": 0,
	"paint": 1, "inner": 1, "lamp": 1,
	"chrome": 2, "glass": 2, "intglass": 2,
}
const SEARCH_BACK := 3  ## slices around the last one searched each frame
const SEARCH_AHEAD := 8
const LOST_DISTANCE := 15.0  ## m from the best nearby slice: search the whole road again
const ROOF_ABOVE := 3.5  ## m above the car where a roof starts to count (as Porsche.exe)
const ROOF_REACH := 100.0  ## m above the car searched for a roof

var sections: Array = []  ## {first, last, open: [3 names], covered: [3 names], size, aspect}
var textures := {}  ## name -> Texture2D (fully clear ones are left out by the converter)
var tint := Color(1, 1, 1)
var road: Road
var _cars: Array[Dictionary] = []


## Decals for `track_name`, null when the track has none (or its file is missing).
static func load_track(track_name: String, track_road: Road) -> LightDecals:
	var folder := "GameData/Track/%s/" % track_name
	if track_road == null or track_road.size() == 0 or not OriginalAssets.exists(folder + track_name + "_decals.json"):
		return null
	var data: Variant = OriginalAssets.load_json(folder + track_name + "_decals.json")
	if not data is Dictionary or (data["textures"] as Dictionary).is_empty():
		return null
	var decals := LightDecals.new()
	decals.name = "LightDecals"
	decals.road = track_road
	decals.sections = data["sections"]
	var light: Array = data["header"]["lightdecal"]  # a, r, g, b
	decals.tint = Color(light[1], light[2], light[3])
	for key: String in data["textures"]:
		var img := Image.load_from_file(OriginalAssets.path(folder + str(data["textures"][key])))
		if img != null:
			img.convert(Image.FORMAT_RGBA8)
			img.generate_mipmaps()
			decals.textures[key] = ImageTexture.create_from_image(img)
	return decals


## Gives `car` (its model set up by Materials.setup_car) the decal passes.
func add_car(car: Node3D, model: Node3D) -> void:
	var tiers: Array = [[], [], []]
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mesh_instance as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var m := mesh.surface_get_material(surface) as BaseMaterial3D
			if m == null or not TIERS.has(str(m.get_meta("car_kind", ""))):
				continue
			var tier: Array = tiers[TIERS[str(m.get_meta("car_kind"))]]
			if not tier.has(m):
				tier.append(m)
	var passes: Array[ShaderMaterial] = []
	for k in 3:
		var p := ShaderMaterial.new()
		p.shader = SHADER
		p.set_shader_parameter("tint", tint)
		passes.append(p)
	_cars.append({"car": car, "tiers": tiers, "passes": passes, "slice": -1, "shown": ["", "", ""]})


func _process(_delta: float) -> void:
	for entry in _cars:
		var car := entry["car"] as Node3D
		if not is_instance_valid(car):
			continue
		var pos := car.global_position
		var slice := _track(entry, pos)
		var section := section_at(slice)
		var names: Array = ["", "", ""]
		if not section.is_empty():
			names = section["covered"] if section["open"] != section["covered"] and _under_roof(car) else section["open"]
		var passes: Array[ShaderMaterial] = entry["passes"]
		if not section.is_empty():
			var d := pos - road.positions[slice]
			var offset := Vector2(d.dot(road.rights[slice]) / SLICE_METRES * LATERAL_FACTOR,
				d.dot(road.forwards[slice]) / SLICE_METRES) + Vector2(0.5, 0.5)
			var size := float(section["size"])
			var scale := Vector2(1.0 / size, float(section["aspect"]) / size)
			var to_car := car.global_transform.affine_inverse()
			for p in passes:
				p.set_shader_parameter("world_to_car", Projection(to_car))
				p.set_shader_parameter("scale", scale)
				p.set_shader_parameter("offset", offset)
		for k in 3:
			var name := str(names[k]) if textures.has(str(names[k])) else ""
			if name == entry["shown"][k]:
				continue
			entry["shown"][k] = name
			if not name.is_empty():
				passes[k].set_shader_parameter("decal", textures[name])
			for m: BaseMaterial3D in entry["tiers"][k]:
				m.next_pass = passes[k] if not name.is_empty() else null


## First section whose slice range holds `slice`, {} when none (as Porsche.exe, FUN_00441140).
func section_at(slice: int) -> Dictionary:
	if slice < 0:
		return {}
	for s: Dictionary in sections:
		if slice >= int(s["first"]) and slice <= int(s["last"]):
			return s
	return {}


## True when track collision lies above the car (tunnel ceiling, bridge, roof).
func _under_roof(car: Node3D) -> bool:
	var from := car.global_position + Vector3.UP * ROOF_ABOVE
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * ROOF_REACH)
	query.hit_back_faces = true
	if car is CollisionObject3D:
		query.exclude = [(car as CollisionObject3D).get_rid()]
	return not car.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Road slice of the car: around the last one, the whole road when the car is far from it (start,
## reset, a jump to another segment).
func _track(entry: Dictionary, pos: Vector3) -> int:
	var last := int(entry["slice"])
	var best := -1
	var best_dist := INF
	if last >= 0:
		for i in range(maxi(last - SEARCH_BACK, 0), mini(last + SEARCH_AHEAD + 1, road.size())):
			var d := road.positions[i].distance_squared_to(pos)
			if d < best_dist:
				best_dist = d
				best = i
	if best < 0 or best_dist > LOST_DISTANCE * LOST_DISTANCE:
		best = road.nearest(pos)
	entry["slice"] = best
	return best
