extends SceneTree
## Headless check for the learning levels: anti-spin catches a slide, ABS stops the wheels
## locking, Noob's speed limit and auto-brake, the guide on the road, the level saving
## and loading, the AI's skill following the level, the tuning panel's Level row, and the
## best lap keeping its level.
## Writes only to a temp folder, never to the real files in user://.
## Run: godot --headless --path . -s tests/levels_check.gd

const HZ := 120.0

var _failed := false
var _ticks := 0
var _stage := 0
var _flat: Node
var _car: Car
var _runs := [
	{"test": "flick", "anti": 0.0}, {"test": "flick", "anti": 1.0},
	{"test": "brake", "abs": false}, {"test": "brake", "abs": true},
]
var _run := -1
var _results := {}
var _max_slide := 0.0
var _locked_ticks := 0
var _brake_ticks := 0
var _abs_seen := false
var _main: Node


func _initialize() -> void:
	_flat = load("res://track/test_flat.tscn").instantiate()
	root.add_child(_flat)


func _physics_process(_delta: float) -> bool:
	_ticks += 1
	if _run < 0:
		_next_run()  # The car is set up on the first tick, once the tree is running.
		return false
	if _run < _runs.size():
		if _drive_run():
			return false
		_check_aids()
		_flat.free()
		_flat = null
		_run = _runs.size()
		_main = load("res://main.tscn").instantiate()
		root.add_child(_main)
		(_main.get_node("PlayerDriver") as Node).process_mode = Node.PROCESS_MODE_DISABLED
		_ticks = 0
		return false
	if _ticks < 3:
		return false  # Let the deferred setup finish.
	_check_paths()
	_check_levels()
	_check_guide()
	_check_speed_limit()
	_check_auto_brake()
	_check_panel()
	_check_best_lap()
	_main.free()
	_remove_dir(SavePaths.test_dir())
	print("LEVELS CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


## One tick of the current flat-track run. False once all runs are done.
func _drive_run() -> bool:
	var run: Dictionary = _runs[_run]
	var t := _ticks / HZ
	if run.test == "flick":
		# Coasting at 75 km/h: a quick flick right, then full left. Without help the back
		# swings round.
		_car.steer = 1.0 if t < 0.6 else -1.0
		_max_slide = maxf(_max_slide, absf(_car.slide_angle()))
		if t < 3.0:
			return true
	else:
		# Straight at 90 km/h, then full brake with brakes strong enough to lock the wheels.
		_car.brake = 1.0
		if _car.forward_speed() > 3.0:
			_brake_ticks += 1
			for i in 2:
				if -_car.wheels[i].slip_ratio > _car.setup.peak_slip_ratio * 3.0:
					_locked_ticks += 1
					break
			_abs_seen = _abs_seen or _car.abs_active
		if t < 4.0:
			return true
	_results[_key(run)] = {"slide": _max_slide, "locked": float(_locked_ticks) / maxi(_brake_ticks, 1),
			"abs_seen": _abs_seen, "kmh": _car.forward_speed() * 3.6}
	print("  %-14s max slide %5.1f deg, front locked %3.0f %% of braking, %5.1f km/h at the end" % [
			_key(run), _max_slide, _results[_key(run)].locked * 100.0, _car.forward_speed() * 3.6])
	if _run + 1 < _runs.size():
		_next_run()
		return true
	return false


func _next_run() -> void:
	if _car:
		_car.get_parent().remove_child(_car)
		_car.free()
	_run += 1
	_ticks = 0
	_max_slide = 0.0
	_locked_ticks = 0
	_brake_ticks = 0
	_abs_seen = false
	var run: Dictionary = _runs[_run]
	_car = load("res://car/car.tscn").instantiate()
	_car.setup = _car.setup.duplicate()  # Never change the shared roadster setup.
	var speed := 75.0 / 3.6
	if run.test == "flick":
		_car.anti_spin = run.anti
	else:
		_car.abs_brakes = run.abs
		_car.setup.brake_torque *= 2.0
		speed = 90.0 / 3.6
	_car.position = Vector3(0, 0.75, 0)
	_flat.add_child(_car)
	_car.drivetrain.gear = 0  # Neutral: no engine braking.
	_car.linear_velocity = Vector3(0, 0, -speed)
	for wheel in _car.wheels:
		wheel.spin = speed / _car.setup.wheel_radius


func _key(run: Dictionary) -> String:
	if run.test == "flick":
		return "flick anti %.1f" % run.anti
	return "brake ABS %s" % ("on" if run.abs else "off")


func _check_aids() -> void:
	var off: Dictionary = _results["flick anti 0.0"]
	var on: Dictionary = _results["flick anti 1.0"]
	_check(off.slide > 40.0, "without anti-spin the flick spins the car (%.0f deg)" % off.slide)
	_check(on.slide < 15.0, "full anti-spin holds the slide under 15 deg (%.1f)" % on.slide)
	_check(on.kmh > 30.0, "and the car keeps going (%.0f km/h)" % on.kmh)
	var locks: Dictionary = _results["brake ABS off"]
	var abs_on: Dictionary = _results["brake ABS on"]
	_check(locks.locked > 0.5, "without ABS strong brakes lock the fronts (%.0f %%)" % (locks.locked * 100.0))
	_check(abs_on.locked < 0.15, "ABS keeps them turning (%.0f %% locked)" % (abs_on.locked * 100.0))
	_check(abs_on.abs_seen and not locks.abs_seen, "ABS readout shows only when ABS works")


func _check_paths() -> void:
	var level := _level()
	var path := SavePaths.safe(level.settings_path)
	_check(path.begins_with(SavePaths.test_dir()), "level file is in the temp folder (%s)" % path)
	var tt := _main.get_node("TimeTrial") as TimeTrial
	_check(tt.records.path.begins_with(SavePaths.test_dir()), "best laps are in the temp folder")


func _check_levels() -> void:
	var level := _level()
	var car := _main.get_node("Car") as Car
	var ai_car := _main.get_node("AiCar") as Car
	var ai := _main.get_node("AiDriver") as AiDriver
	var tt := _main.get_node("TimeTrial") as TimeTrial
	_check(level.get_index() > _main.get_node("PlayerDriver").get_index()
			and level.get_index() < car.get_index(), "level runs after your driver and before your car")
	_check(level.level == LearningLevel.NOOB, "game starts at Noob")
	_check(car.anti_spin == 1.0 and car.abs_brakes and car.traction_allowed, "Noob: full anti-spin, ABS and TC")
	_check(ai.skill == 50.0, "Noob: AI at 50 %")
	_check(ai_car.anti_spin == 0.0 and not ai_car.abs_brakes, "AI car gets no aids")
	_check(tt.level_name == "Noob", "time trial knows the level")

	var heard: Array[int] = []
	level.changed.connect(func(l): heard.append(l))
	level.set_level(LearningLevel.EXPERT)
	_check(car.anti_spin == 0.0 and not car.abs_brakes and not car.traction_allowed,
			"Expert: no anti-spin, ABS or TC")
	_check(ai.skill == 90.0, "Expert: AI at 90 %")
	_check(heard == [LearningLevel.EXPERT], "level change is announced")
	_check(level.load_level() == LearningLevel.EXPERT, "level is saved")
	var fresh := LearningLevel.new()
	_check(fresh.load_level() == LearningLevel.EXPERT, "a new game loads the saved level")
	fresh.free()

	level.set_level(LearningLevel.NOVICE)
	_check(car.anti_spin == 0.6 and car.abs_brakes and car.traction_allowed and ai.skill == 65.0,
			"Novice: medium anti-spin, ABS, TC, AI at 65 %")
	level.set_level(LearningLevel.EXPERIENCED)
	_check(car.anti_spin == 0.3 and not car.abs_brakes and car.traction_allowed and ai.skill == 80.0,
			"Experienced: light anti-spin, TC, AI at 80 %")
	level.set_level(99)
	_check(level.level == LearningLevel.EXPERT, "levels past Expert stop at Expert")


func _check_guide() -> void:
	var level := _level()
	var guide := level._guide
	level.set_level(LearningLevel.NOOB)
	_check(level.line != null and level.line != (_main.get_node("AiDriver") as AiDriver).line,
			"guide has its own copy of the line")
	var fastest := 0.0
	for s in level.line.speeds:
		fastest = maxf(fastest, s)
	_check(fastest <= 80.0 / 3.6 + 0.01, "Noob line never asks for more than 80 km/h (%.0f)" % (fastest * 3.6))
	_check(guide.mode == TrackGuide.LINE and guide._line_node.visible, "Noob shows the coloured line")
	guide._draw_line()
	_check(guide._mesh.get_surface_count() == 1, "line is drawn")
	_check((guide._line_node.material_override as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED,
			"line shows from above whichever way it winds")
	_check(guide.colour_at(0, 0.0, 0.0) == TrackGuide.GREEN, "line is green when slow")
	_check(guide.colour_at(0, 0.0, level.line.speeds[0] + 5.0) == TrackGuide.RED, "red when too fast for it")
	_check(guide.board_points.is_empty(), "no brake boards at Noob")
	level.set_level(LearningLevel.EXPERIENCED)
	_check(guide.mode == TrackGuide.MARKERS and not guide._line_node.visible, "Experienced hides the line")
	_check(guide.board_points.size() >= 4 and guide.board_points.size() < 30,
			"Experienced has brake boards before the big corners (%d)" % guide.board_points.size())
	_check(guide.count_points.size() > 0 and guide.count_points.size() <= 2 * guide.board_points.size(),
			"100 and 50 boards come before them (%d)" % guide.count_points.size())
	var step := level.line.distance_at(1)
	var placed_right := true
	for k in guide.count_points.size():
		var metres := int(guide.count_labels[k])
		var ahead := guide.count_points[k] + roundi(metres / step)
		placed_right = placed_right and posmod(ahead, level.line.size()) in guide.board_points
	_check(placed_right, "each count board stands its distance before a BRAKE board")
	var heard: Array[bool] = []
	guide.toggled.connect(func(on): heard.append(on))
	var hud := _main.get_node("LapHud")
	guide.toggle()
	_check(not guide.visible and heard == [false] and hud._note.text == "Road guide off", "L turns the guide off")
	level.set_level(LearningLevel.NOOB)
	_check(not guide.visible, "guide stays off when the level changes")
	guide.toggle()
	_check(guide.visible and heard == [false, true] and hud._note.text == "Road guide on", "L turns it on again")
	var key := false
	for e in InputMap.action_get_events("toggle_guide"):
		key = key or (e is InputEventKey and e.physical_keycode == KEY_L)
	_check(key, "L is the guide key")
	var clash := ""
	for action in InputMap.get_actions():
		if action == "toggle_guide" or action.begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(action):
			if e is InputEventKey and e.physical_keycode == KEY_L:
				clash = action
	_check(clash == "", "no other action uses L %s" % clash)
	level.set_level(LearningLevel.EXPERT)
	_check(guide.board_points.is_empty() and not guide._line_node.visible, "Expert shows nothing")


func _check_speed_limit() -> void:
	var level := _level()
	var car := _main.get_node("Car") as Car
	level.set_level(LearningLevel.NOOB)
	car.throttle = 1.0
	car.brake = 0.0
	level._limit_speed(50.0 / 3.6, 80.0 / 3.6)
	_check(car.throttle == 1.0, "full throttle at 50 km/h")
	level._limit_speed(79.5 / 3.6, 80.0 / 3.6)
	_check(car.throttle < 0.2, "throttle eases off at 80 km/h (%.2f)" % car.throttle)
	car.throttle = 1.0
	level._limit_speed(90.0 / 3.6, 80.0 / 3.6)
	_check(car.throttle == 0.0 and car.brake > 0.0, "gentle brake above 80 km/h, down a hill")


func _check_auto_brake() -> void:
	var level := _level()
	var line := level.line
	level.set_level(LearningLevel.NOOB)
	# The slowest point on the lap, and a place 50 m before it.
	var slowest := 0
	for i in line.size():
		if line.speeds[i] < line.speeds[slowest]:
			slowest = i
	var before := posmod(slowest - roundi(50.0 / line.distance_at(1)), line.size())
	level.progress = before
	var car := _main.get_node("Car") as Car
	car.global_transform = Transform3D(Basis.looking_at(line.direction(before)), line.points[before] + Vector3.UP * 0.5)

	car.linear_velocity = line.direction(before) * (line.speeds[slowest] + 12.0)
	car.throttle = 1.0
	car.brake = 0.0
	level._physics_process(1.0 / HZ)
	_check(level.auto_brake > 0.0 and car.throttle == 0.0 and car.brake == level.auto_brake,
			"auto-brake slows you for a corner you're too fast for (brake %.2f)" % car.brake)
	car.brake = 0.9
	level._physics_process(1.0 / HZ)
	_check(car.brake == 0.9, "your own harder braking wins")

	car.linear_velocity = line.direction(before) * (line.speeds[slowest] * 0.8)
	car.throttle = 1.0
	car.brake = 0.0
	level._physics_process(1.0 / HZ)
	_check(level.auto_brake == 0.0 and car.throttle > 0.0, "no auto-brake when slow enough")

	level.set_level(LearningLevel.NOVICE)
	car.linear_velocity = line.direction(before) * (line.speeds[slowest] + 12.0)
	car.throttle = 1.0
	level._physics_process(1.0 / HZ)
	_check(level.auto_brake == 0.0 and car.throttle == 1.0, "no auto-brake above Noob")


func _check_panel() -> void:
	var level := _level()
	var ai := _main.get_node("AiDriver") as AiDriver
	var panel := _main.get_node("TuningPanel")
	_check(panel._level_slider != null, "tuning panel has the Level row")
	if panel._level_slider == null:
		return
	_check(panel._first_slider == panel._level_slider, "Level is the first row")
	panel._level_slider.value = LearningLevel.NOVICE
	_check(level.level == LearningLevel.NOVICE and panel._level_value.text == "Novice", "Level row sets the level")
	_check(panel._ai_slider.value == 65.0, "AI skill slider follows the level")
	_check(not panel.has_unsaved_changes(), "level is not a car setup change")


func _check_best_lap() -> void:
	var level := _level()
	var tt := _main.get_node("TimeTrial") as TimeTrial
	var records := LapRecords.new("user://levels_check_records.cfg")
	_check(records.path.begins_with(SavePaths.test_dir()), "test records are in the temp folder")
	records.save_best("ridge", 95.2, [30.0, 60.0], "Novice")
	_check(records.best("ridge").level == "Novice", "best lap keeps its level")
	level.set_level(LearningLevel.EXPERIENCED)
	_check(tt.level_name == "Experienced", "time trial follows the level")
	tt.best_level = "Noob"
	tt.timer.best_lap = 95.2
	var hud := _main.get_node("LapHud")
	hud._process(0.0)
	_check(hud._times.text.ends_with("(Noob)"), "lap display shows the best lap's level (%s)" % hud._times.text)


func _level() -> LearningLevel:
	return _main.get_node("LearningLevel") as LearningLevel


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
