extends Node3D
## Car sounds for the phase 2 prototype, from the original's banks converted by tools/snd2wav.py
## and tools/engine_sound.py (loaded at run time from decomposed/, D-008, D-011):
## - engine: looped recordings at fixed engine speeds, pitched to the current rpm and crossfaded
##   (equal power, on a log rpm scale) between the two nearest; "load" loops on throttle, "coast"
##   loops (with idle) off throttle, blended by the throttle;
## - tyres squeal with slip beyond the grip peak, wind grows with speed, the body scrapes;
## - impacts (CarDamage.impacted) and parts coming off or loose (CarDamage.part_changed).
## The collision bank sounds are picked by their signal (docs/formats/bnk.md), confirmed by ear.

const SFX := {  ## SND_coll.bnk indices
	"squeal": 46, "wind": 42, "scrape": 99,
	"hit_light": [52, 56], "hit_heavy": [49, 51, 55], "glass": [119, 120], "part_off": [61], "part_loose": [52],
}
const GLASS_KINDS := ["headlight", "front_light", "tail_light"]

var master_db := 0.0
var engine_db := -2.0
var sfx_db := -4.0

var _car: Car
var _layers := []  ## [{group, loops: [{player, rpm}]}]
var _load := 0.0  ## smoothed throttle share
var _squeal: AudioStreamPlayer3D
var _wind: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _sfx_dir := ""
var _streams := {}  ## path -> AudioStreamWAV


func setup(car: Car, engine: Dictionary, engine_dir: String, sfx_dir: String) -> void:
	_car = car
	_sfx_dir = sfx_dir
	_ensure_buses()
	var behind := 1.0 if str(car.params.get("engine_position", "rear")) != "front" else -1.0
	position = Vector3(0.0, 0.5, 1.2 * behind)
	for group: String in engine.get("groups", {}):
		for layer: Array in engine["groups"][group]:
			var loops := []
			for loop: Dictionary in layer:
				var stream := _load_stream(engine_dir.path_join(loop["file"]), int(loop["loop_start"]), int(loop["loop_end"]))
				if stream == null:
					continue
				loops.append({"player": _player(stream, "Engine"), "rpm": float(loop["rpm"])})
			if not loops.is_empty():
				_layers.append({"group": group, "loops": loops})
	_squeal = _sfx_loop(SFX["squeal"])
	_wind = _sfx_loop(SFX["wind"])
	_scrape = _sfx_loop(SFX["scrape"])
	if car.damage != null:
		car.damage.impacted.connect(_on_impact)
		car.damage.part_changed.connect(_on_part)


## Engine sound levels per group for tests: {group: [[rpm, linear volume, pitch_scale] per loop]}.
func engine_levels() -> Dictionary:
	var out := {}
	for layer: Dictionary in _layers:
		var rows: Array = out.get(layer["group"], [])
		for loop: Dictionary in layer["loops"]:
			var p: AudioStreamPlayer3D = loop["player"]
			rows.append([loop["rpm"], db_to_linear(p.volume_db), p.pitch_scale])
		out[layer["group"]] = rows
	return out


func squeal_level() -> float:
	return db_to_linear(_squeal.volume_db) if _squeal != null else 0.0


func _process(delta: float) -> void:
	if _car == null:
		return
	var rpm := maxf(_car.rpm, 300.0)
	var target := clampf(_car.throttle, 0.0, 1.0) if _car.gear != 0 else 0.0
	_load = move_toward(_load, target, delta * 6.0)
	var groups := {"load": sqrt(_load), "coast": sqrt(1.0 - _load)}
	var counts := {}
	for layer: Dictionary in _layers:
		counts[layer["group"]] = int(counts.get(layer["group"], 0)) + 1
	for layer: Dictionary in _layers:
		var loops: Array = layer["loops"]
		var gain: float = groups.get(layer["group"], 0.0) / sqrt(float(counts[layer["group"]]))
		var weights := _crossfade(loops, rpm)
		for i in loops.size():
			var p: AudioStreamPlayer3D = loops[i]["player"]
			p.volume_db = linear_to_db(maxf(weights[i] * gain, 0.0001)) + engine_db + master_db
			p.pitch_scale = clampf(rpm / float(loops[i]["rpm"]), 0.3, 3.0)
	var speed := absf(_car.forward_speed)
	_update_squeal(speed)
	_set_loop(_wind, smoothstep(5.0, 45.0, speed) * 0.8, 0.8 + clampf(speed / 50.0, 0.0, 1.0) * 0.5)
	var scrape := clampf(_car.damage.scrape / 400.0, 0.0, 1.0) * clampf(speed / 5.0, 0.0, 1.0) if _car.damage != null else 0.0
	_set_loop(_scrape, scrape, 0.8 + clampf(speed / 30.0, 0.0, 1.0) * 0.4)


## Equal power crossfade between the two loops around rpm (log scale); the outer loops hold.
func _crossfade(loops: Array, rpm: float) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(loops.size())
	if loops.size() == 1 or rpm <= float(loops[0]["rpm"]):
		w[0] = 1.0
		return w
	for i in loops.size() - 1:
		var a := float(loops[i]["rpm"])
		var b := float(loops[i + 1]["rpm"])
		if rpm <= b:
			var t := clampf(log(rpm / a) / log(b / a), 0.0, 1.0) if b > a else 1.0
			w[i] = cos(t * PI / 2.0)
			w[i + 1] = sin(t * PI / 2.0)
			return w
	w[loops.size() - 1] = 1.0
	return w


func _update_squeal(speed: float) -> void:
	var slip := 0.0
	for w in _car.wheels:
		if not w.contact:
			continue
		var s := maxf(absf(w.slip_angle) / _car.peak_slip_angle, absf(w.slip_ratio) / _car.peak_slip_ratio)
		slip = maxf(slip, s)
	var level := smoothstep(0.8, 1.6, slip) * clampf(speed / 8.0, 0.0, 1.0)
	_set_loop(_squeal, level, 0.9 + clampf(slip - 1.0, 0.0, 1.0) * 0.25)


func _set_loop(p: AudioStreamPlayer3D, level: float, pitch: float) -> void:
	if p == null:
		return
	p.volume_db = linear_to_db(maxf(level, 0.0001)) + sfx_db + master_db
	p.pitch_scale = pitch


func _on_impact(kmh: float, point: Vector3, impulse: float) -> void:
	if impulse < 300.0:
		return
	var heavy := impulse > 6000.0
	_one_shot(SFX["hit_heavy"] if heavy else SFX["hit_light"], point, clampf(impulse / 12000.0, 0.15, 1.0))


func _on_part(kind: String, state: String, point: Vector3) -> void:
	if state == "off":
		_one_shot(SFX["glass"] if kind in GLASS_KINDS else SFX["part_off"], point, 0.9)
	elif state == "hinged":
		_one_shot(SFX["part_loose"], point, 0.5)


func _one_shot(choices: Array, point: Vector3, level: float) -> void:
	var index: int = choices[randi() % choices.size()]
	var stream := _load_stream(_sfx_dir.path_join("%03d.wav" % index), -1, -1)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "Sfx"
	p.volume_db = linear_to_db(level) + sfx_db + master_db
	add_child(p)
	p.global_position = _car.to_global(point)
	p.finished.connect(p.queue_free)
	p.play()


func _sfx_loop(index: int) -> AudioStreamPlayer3D:
	var stream := _load_stream(_sfx_dir.path_join("%03d.wav" % index), 0, -2)
	if stream == null:
		return null
	var p := _player(stream, "Sfx")
	p.volume_db = -80.0
	return p


func _player(stream: AudioStreamWAV, bus: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


## WAV from decomposed/; loop_end -1 = no loop, -2 = loop the whole sound.
func _load_stream(path: String, loop_start: int, loop_end: int) -> AudioStreamWAV:
	var key := "%s|%d|%d" % [path, loop_start, loop_end]
	if _streams.has(key):
		return _streams[key]
	var file := OriginalAssets.path(path)
	if not FileAccess.file_exists(file):
		push_warning("Missing sound %s - run tools/snd2wav.py (see game/README.md)" % file)
		return null
	var stream := AudioStreamWAV.load_from_file(file)
	if stream == null:
		return null
	if loop_end != -1:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = maxi(loop_start, 0)
		var frames := int(stream.get_length() * stream.mix_rate)
		stream.loop_end = frames if loop_end == -2 else mini(loop_end, frames)
	_streams[key] = stream
	return stream


static func _ensure_buses() -> void:
	for bus in ["Engine", "Sfx"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
