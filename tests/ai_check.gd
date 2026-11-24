extends SceneTree
## Headless check for the AI driver: the racing line stays on the road, the speeds make sense,
## the AI drives a clean lap of Ridge (no grass or gravel, never put back on the line),
## and the on/off key, grid start and tuning panel slider work in the game scene.
## Touches no files.
## Run: godot --headless --path . --fixed-fps 120 -s tests/ai_check.gd

const HZ := 120
## Longest the lap test may run, in simulated seconds.
const TIME_LIMIT := 240.0

var _failed := false
var _ticks := 0
var _track: Track
var _car: Car
var _ai: AiDriver
var _main: Node

var _lap_start := -1
var _laps_done := 0
var _lap_time := 0.0
var _last_progress := 0
var _off_ticks := 0
var _top_speed := 0.0


func _initialize() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	_track = load("res://track/ridge/ridge.tscn").instantiate()
	scene.add_child(_track)
	_ai = AiDriver.new()
	_car = load("res://car/car.tscn").instantiate()
	_ai.car = _car
	_ai.track = _track
	scene.add_child(_ai)  # Before the car, so it drives each tick before the car moves.
	scene.add_child(_car)


func _physics_process(_delta: float) -> bool:
	_ticks += 1
	if _ticks == 2:
		_check_line()
		_ai.skill = 90.0
		_ai.set_active(true)
		return false
	if _main == null and _laps_done < 2:
		_watch_lap()
		if _ticks < TIME_LIMIT * HZ:
			return false
		_check(false, "AI finishes a lap within %d s" % TIME_LIMIT)
		_laps_done = 99
	if _main == null:
		_report_lap()
		_check_skill()
		_ai.get_parent().free()
		_main = load("res://main.tscn").instantiate()
		root.add_child(_main)
		return false
	_check_game()
	_main.free()
	print("AI CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _check_line() -> void:
	var line := _ai.line
	var n := line.size()
	_check(n > 500, "line has a point every few metres (%d points)" % n)
	var limit := _track.gate_half_width() - 1.6 + 0.01
	var widest := 0.0
	for o in line.offsets:
		widest = maxf(widest, absf(o))
	_check(widest <= limit, "line stays on the road (widest %.2f m from the middle, limit %.2f)" % [widest, limit])
	_check(widest > 2.0, "line uses the road width to cut corners (%.2f m)" % widest)
	var slowest := INF
	var fastest := 0.0
	for s in line.speeds:
		slowest = minf(slowest, s)
		fastest = maxf(fastest, s)
	print("  line speeds %.0f to %.0f km/h" % [slowest * 3.6, fastest * 3.6])
	_check(slowest > 8.0 and slowest < 25.0, "slowest point is the hairpin pace (%.0f km/h)" % (slowest * 3.6))
	_check(fastest > 35.0, "fast on the straights (%.0f km/h)" % (fastest * 3.6))
	# Never asks to slow faster than the brakes can. Uphill, gravity helps; downhill, less is left.
	var worst := 0.0
	for i in n:
		var a := line.speeds[i]
		var b := line.speeds[(i + 1) % n]
		var step := line.points[i].distance_to(line.points[(i + 1) % n])
		var grade := (line.points[(i + 1) % n].y - line.points[i].y) / step
		var can := maxf(0.3 * line.brake_accel, line.brake_accel + RacingLine.GRAVITY * grade)
		worst = maxf(worst, (a * a - b * b) / (2.0 * step) / can)
	_check(worst <= 1.01, "braking asked for fits the brakes (%.0f %% of what they can do)" % (worst * 100.0))


## Times laps by the line point the car is at. The car starts behind the line.
func _watch_lap() -> void:
	var n := _ai.line.size()
	var p := _ai.progress
	var crossed := _last_progress > n * 3 / 4 and p < n / 4
	_last_progress = p
	_top_speed = maxf(_top_speed, _car.linear_velocity.length())
	if crossed:
		if _lap_start >= 0:
			_lap_time = float(_ticks - _lap_start) / HZ
		_lap_start = _ticks
		_laps_done += 1
	if _lap_start < 0:
		return
	for wheel in _car.wheels:
		if wheel.on_ground and wheel.surface_grip < 0.85:
			_off_ticks += 1
			break


func _report_lap() -> void:
	print("  lap %.2f s, top speed %.0f km/h, %d ticks with a wheel off the road and kerbs, %d recoveries"
			% [_lap_time, _top_speed * 3.6, _off_ticks, _ai.recoveries])
	_check(_laps_done >= 2 and _lap_time > 60.0 and _lap_time < 150.0, "AI drives a full lap (%.2f s)" % _lap_time)
	_check(_ai.recoveries == 0, "never put back on the line")
	_check(_off_ticks == 0, "never on grass or gravel")


func _check_skill() -> void:
	var fast := _ai.line.speeds.duplicate()
	_ai.skill = 60.0
	var slower := true
	for i in fast.size():
		slower = slower and _ai.line.speeds[i] <= fast[i] + 0.001
	_check(slower and _ai.line.speeds[0] <= fast[0], "lower skill plans slower everywhere")
	_ai.skill = 5.0
	_check(_ai.skill == 30.0, "skill never goes below 30 %")


func _check_game() -> void:
	var ai := _main.get_node_or_null("AiDriver") as AiDriver
	var ai_car := _main.get_node_or_null("AiCar") as Car
	var player := _main.get_node("Car") as Car
	_check(ai != null and ai_car != null, "AI driver and car in the game scene")
	if ai == null or ai_car == null:
		return
	_check(ai.get_index() < ai_car.get_index(), "AI driver runs before its car")
	_check(not ai.active and not ai_car.visible and ai_car.process_mode == Node.PROCESS_MODE_DISABLED,
			"AI is off at the start: car hidden and out of the physics")
	ai.toggle()
	_check(ai.active and ai_car.visible and ai_car.process_mode == Node.PROCESS_MODE_INHERIT, "turns on")
	ai.place_on_grid()  # As happens once the player's reset takes effect.
	var spawn := (_main.get_node("Track/Spawn") as Node3D).global_transform
	var side := (ai_car._place_target.origin - spawn.origin).dot(spawn.basis.x)
	_check(absf(side - AiDriver.GRID_GAP) < 0.01, "starts %.1f m to the right of you" % side)
	_check(ai._waiting, "waits on the grid for you to move off")
	ai.toggle()
	_check(not ai.active and not ai_car.visible, "turns off")
	var tt := _main.get_node("TimeTrial") as TimeTrial
	_check(tt.car == player, "only your car is timed")

	var panel := _main.get_node("TuningPanel")
	_check(panel._ai_slider != null, "tuning panel has the AI skill slider")
	if panel._ai_slider != null:
		panel._ai_slider.value = 70.0
		_check(ai.skill == 70.0, "slider sets the skill")
		_check(not panel.has_unsaved_changes(), "skill is not a car setup change")

	var key := false
	var pad := false
	for e in InputMap.action_get_events("toggle_ai"):
		key = key or (e is InputEventKey and e.physical_keycode == KEY_I)
		pad = pad or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_DPAD_RIGHT)
	_check(key and pad, "I and D-pad right turn the AI on and off")


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
