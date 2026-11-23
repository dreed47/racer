extends SceneTree
## Headless check for car sound: engine pitch follows rpm, throttle makes it louder,
## tires squeal only when sliding on hard ground, wind grows with speed, mute works.
## Writes no files.
## Run: godot --headless --path . -s tests/sound_check.gd

const RATE := 22050.0

var _failed := false
var _main: Node


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_check_engine()
	_check_tires()
	_check_wind()
	_check_car_sound()
	_main.free()
	print("SOUND CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _check_engine() -> void:
	var low := _engine_note(2000.0)
	var high := _engine_note(6000.0)
	_check(absf(low / EngineSynth.firing_hz(2000.0) - 1.0) < 0.1,
		"engine note at 2000 rpm is %.0f Hz (expect %.0f)" % [low, EngineSynth.firing_hz(2000.0)])
	_check(absf(high / EngineSynth.firing_hz(6000.0) - 1.0) < 0.1,
		"engine note at 6000 rpm is %.0f Hz (expect %.0f)" % [high, EngineSynth.firing_hz(6000.0)])
	var closed := _rms(_settled(EngineSynth.new(RATE, 1), 3000.0, 0.0))
	var open := _rms(_settled(EngineSynth.new(RATE, 1), 3000.0, 1.0))
	_check(closed > 0.02, "engine audible with throttle shut (level %.3f)" % closed)
	_check(open > closed * 1.5, "full throttle louder (level %.3f against %.3f)" % [open, closed])
	_check(_peak(_settled(EngineSynth.new(RATE, 1), 7200.0, 1.0)) <= 1.0, "engine never clips")


## Main note of the engine at this rpm, found by autocorrelation.
func _engine_note(rpm: float) -> float:
	var s := _settled(EngineSynth.new(RATE, 1), rpm, 0.5)
	var n := 2048
	var best := 0.0
	var scores := PackedFloat32Array()
	var first := int(RATE / 400.0)
	var last := int(RATE / 25.0)
	for lag in range(first, last):
		var sum := 0.0
		for i in n:
			sum += s[i].x * s[i + lag].x
		scores.append(sum)
		best = maxf(best, sum)
	# The shortest lag that repeats almost as well as the best one is the note.
	for k in scores.size():
		if scores[k] >= best * 0.85 and (k == 0 or scores[k] >= scores[k - 1]) \
				and (k + 1 == scores.size() or scores[k] >= scores[k + 1]):
			return RATE / (first + k)
	return 0.0


## Lets rpm and throttle settle for half a second, then returns the next 0.2 s.
func _settled(engine: EngineSynth, rpm: float, throttle: float) -> PackedVector2Array:
	engine.fill(int(RATE * 0.5), rpm, throttle)
	return engine.fill(int(RATE * 0.2), rpm, throttle)


func _check_tires() -> void:
	_check(TireSynth.squeal_for(0.5, 1.0, 20.0, true) == 0.0, "no squeal while gripping")
	_check(TireSynth.squeal_for(1.0, 1.0, 20.0, true) > 0.0, "quiet squeal near the limit")
	_check(TireSynth.squeal_for(1.6, 1.0, 20.0, true) == 1.0, "full squeal when sliding")
	_check(TireSynth.squeal_for(1.6, 0.9, 20.0, true) > 0.0, "kerbs squeal")
	_check(TireSynth.squeal_for(1.6, 0.6, 20.0, true) == 0.0, "no squeal on grass")
	_check(TireSynth.squeal_for(1.6, 1.0, 20.0, false) == 0.0, "no squeal in the air")
	_check(TireSynth.squeal_for(1.6, 1.0, 1.0, true) == 0.0, "no squeal when nearly stopped")
	var skid := TireSynth.load_samples()
	_check(skid.size() > int(RATE), "recorded skid loads (%d samples)" % skid.size())
	var tire := TireSynth.new(RATE, 2, skid)
	var silent := _rms(tire.fill(int(RATE * 0.3), 0.0))
	tire.fill(int(RATE * 0.3), 1.0)
	var loud := _rms(tire.fill(int(RATE * 0.2), 1.0))
	_check(silent == 0.0 and loud > 0.05, "squeal sound only when asked (level %.3f)" % loud)
	_check(_peak(tire.fill(int(RATE * 0.2), 1.0)) <= 1.0, "squeal never clips")
	tire.fill(int(RATE * 0.3), 0.3)
	var light := _rms(tire.fill(int(RATE * 0.5), 0.3))
	_check(light < loud * 0.4, "light slide is much quieter than a full slide")
	var engine := _rms(_settled(EngineSynth.new(RATE, 1), 4000.0, 0.3))
	_check(loud < engine, "full squeal stays below the engine at part throttle")


func _check_wind() -> void:
	var levels: Array[float] = []
	for speed in [0.0, 20.0, 40.0, 60.0]:
		var wind := WindSynth.new(RATE, 3)
		wind.fill(int(RATE * 1.0), speed)
		levels.append(_rms(wind.fill(int(RATE * 0.3), speed)))
	_check(levels[0] == 0.0, "no wind when stopped")
	_check(levels[1] < levels[2] and levels[2] < levels[3],
		"wind grows with speed (%.3f, %.3f, %.3f)" % [levels[1], levels[2], levels[3]])
	_check(levels[3] < 1.0, "wind never clips")


func _check_car_sound() -> void:
	var has_m := false
	var has_pad := false
	for event in InputMap.action_get_events("mute_sound"):
		has_m = has_m or (event is InputEventKey and event.physical_keycode == KEY_M)
		has_pad = has_pad or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_DPAD_DOWN)
	_check(has_m and has_pad, "M and D-pad down mute")
	var sound := _main.get_node("CarSound") as CarSound
	_check(sound != null and sound.car == _main.get_node("Car"), "main scene has car sound on the car")
	_check(sound.find_children("*", "AudioStreamPlayer", false, false).size() == 3,
		"three sounds: engine, tires, wind")
	sound.toggle_mute()
	var off := AudioServer.is_bus_mute(0)
	sound.toggle_mute()
	_check(off and not AudioServer.is_bus_mute(0), "mute turns sound off and on")


func _rms(samples: PackedVector2Array) -> float:
	var sum := 0.0
	for s in samples:
		sum += s.x * s.x
	return sqrt(sum / maxf(samples.size(), 1))


func _peak(samples: PackedVector2Array) -> float:
	var most := 0.0
	for s in samples:
		most = maxf(most, absf(s.x))
	return most


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
