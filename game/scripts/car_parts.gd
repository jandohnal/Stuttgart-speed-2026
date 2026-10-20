extends RefCounted
## Performance parts of the original (D-024): Stock = the .sim as it is (the factory parts are
## neutral), Sport = the best part of every group the car's shop list offers, plus the tyres
## (stock / slick / rain) chosen apart. Data: FEData/Data/parts.json from tools/parts.py; how a
## part changes the .sim values (Porsche.exe 0x49CB50): docs/formats/prt.md; the constants of those
## formulas come with the data ("formula", read from the exe by the tool, D-023). Works on a
## cars.json entry in .sim file units and returns a changed copy.

const FILE := "FEData/Data/parts.json"
const TUNES := ["stock", "sport"]
const TYRES := ["stock", "slick", "rain"]
const ENGINE := 1
const BRAKES := 2
const GEARBOX := 3
const SPRINGS := 4
const SHOCKS := 5
const AERO := 6
const SWAY := 8
const TYRE := 9
const LBFT_TO_NM := 1.3558


## The car's entry in parts.json (keys of cars.json), or {} when it has none.
static func car_entry(parts: Variant, physics_key: String) -> Dictionary:
	if not parts is Dictionary:
		return {}
	return parts["cars"].get(physics_key, {})


## True when the original lets parts change this car (959, 928, GT2 and GT3 ignore them).
static func upgradable(entry: Dictionary) -> bool:
	return bool(entry.get("applies", false)) and not entry.get("sport", []).is_empty()


## Tyre choices the car offers: "stock" always, "slick" / "rain" when its shop list has them.
static func tyre_choices(entry: Dictionary) -> Array[String]:
	var out: Array[String] = ["stock"]
	if bool(entry.get("applies", false)):
		for kind: String in ["slick", "rain"]:
			if entry.get("tyres", {}).has(kind):
				out.append(kind)
	return out


## Copy of `params` (a cars.json entry) with the tune ("stock" / "sport") and tyres applied.
## Adds "tyre_grip_factor": grip of the fitted tyre type on dry asphalt relative to the factory one.
static func apply(params: Dictionary, parts: Variant, physics_key: String, tune: String, tyres: String) -> Dictionary:
	var out := params.duplicate(true)
	var entry := car_entry(parts, physics_key)
	if entry.is_empty() or not bool(entry["applies"]):
		return out
	var ids: Array = entry["sport"].duplicate() if tune == "sport" else []
	if tyres != "stock" and entry["tyres"].has(tyres):
		ids.append(entry["tyres"][tyres])  # last: the tyre formula uses the grip the others left
	for id: Variant in ids:
		var part: Variant = parts["parts"].get(str(int(id)))
		if part is Dictionary:
			apply_part(out, part, parts["formula"])
	var grip: Array = parts["tyre_grip"]
	var stock_type := int(entry.get("stock_tyre_type", 0))
	var tyre_type := int(out.get("tyre_type", stock_type))
	out["tyre_type"] = tyre_type
	out["tyre_grip_factor"] = float(grip[tyre_type]) / float(grip[stock_type])
	return out


## Changes `p` (cars.json entry, .sim file units) the way the original fits one part; `k`: the
## formula constants of parts.json.
static func apply_part(p: Dictionary, part: Dictionary, k: Dictionary) -> void:
	var u: Dictionary = p["unknown"]
	var c0 := float(part["effect"][0])
	var c4 := float(part["effect"][1])
	p["mass_kg"] = float(p["mass_kg"]) + float(part["mass_kg"])
	p["top_speed_mph"] = float(p["top_speed_mph"]) / (1.0 + float(part["vmax_pct"]) * 0.01)
	match int(part["category"]):
		ENGINE:
			if part.has("torque_curve"):
				_fit_engine(p, part, float(k["engine_added_share"]))
		BRAKES:
			_scale(u, "0x104", (c0 + k["brake_add"]) * k["brake_scale"])
		GEARBOX:
			if part.has("gearbox"):
				var box: Dictionary = part["gearbox"]
				p["gears"] = box["ratios"].duplicate()
				p["final_drive"] = box["final"]
				p["reverse_ratio"] = box["reverse"]
				u["0x054"] = int(part["shift_delay"])
			else:
				u["0x054"] = int(u.get("0x054", 8)) + int(part["shift_delay"])
		SPRINGS, SHOCKS, SWAY:
			var stiffer: float = (c0 + k["spring_add"]) * k["spring_scale"]  # suspension stiffness 0x11C
			var roll: float = (c0 + k["brake_add"]) * k["brake_scale"]  # roll 0x12C shrinks by this
			var damper_grip: float = (c0 + k["damper_grip_add"]) * k["damper_grip_scale"]
			if int(part["category"]) == SPRINGS:
				_scale(u, "0x11C", stiffer)
				_scale(u, "0x130", stiffer)
				_scale(u, "0x0F4", (c0 + k["spring_grip_add"]) * k["spring_grip_scale"])
				_scale(u, "0x12C", 1.0 / roll)
				u["0x120"] = c4
			elif int(part["category"]) == SHOCKS:
				_scale(u, "0x114", 1.0 / stiffer)
				_scale(u, "0x118", 1.0 / stiffer)
				_scale(u, "0x0F4", damper_grip)
			else:
				_scale(u, "0x11C", stiffer)
				_scale(u, "0x0F4", damper_grip)
				_scale(u, "0x12C", 1.0 / roll)
		AERO:
			_scale(u, "0x10C", 1.0 + c0 * k["aero_scale"])
			_scale(u, "0x110", 1.0 + c4 * k["aero_scale"])
		TYRE:
			# Front and rear tyre effects relative to the grip they meet; the mean sets 0x0F4,
			# the front's share shifts the front grip bias 0x0F0.
			var grip := float(u.get("0x0F4", 1.15))
			var weighted: float = grip * k["tyre_weight"]
			var front := (weighted + c0) / (weighted + 1.0)
			var both := (weighted + c4) / (weighted + 1.0) + front
			u["0x0F4"] = (both + 1.0) * grip * k["tyre_third"]
			_scale(u, "0x0F0", (2.0 * front / both + 1.0) * k["tyre_half"])
			p["tyre_type"] = int(part.get("tyre_type", 0))


## A whole engine replaces the torque curve; turbo, exhaust, intake ... add a share of their curve.
static func _fit_engine(p: Dictionary, part: Dictionary, added_share: float) -> void:
	var curve: Array = p["torque_curve_lbft_per_500rpm"].duplicate()
	var add: Array = part["torque_curve"]
	if bool(part.get("replaces_curve", false)):
		curve = add.duplicate()
	else:
		while curve.size() < add.size():
			curve.append(0.0)
		for i in add.size():
			curve[i] = float(curve[i]) + added_share * float(add[i])
	while not curve.is_empty() and float(curve[-1]) <= 0.0:
		curve.pop_back()
	p["torque_curve_lbft_per_500rpm"] = curve
	var peak := 0.0
	for t: Variant in curve:
		peak = maxf(peak, float(t))
	p["torque_peak_nm"] = snappedf(peak * LBFT_TO_NM, 0.1)
	if int(part.get("induction", 0)) == 1:
		p["turbo"] = true


static func _scale(u: Dictionary, key: String, factor: float) -> void:
	if u.has(key):
		u[key] = float(u[key]) * factor
