extends SceneTree
## Headless check for the circuit, lap timer and best-lap file.
## Writes only to a file in the system temp folder, never to the real records in user://.
## Run: godot --headless --path . -s tests/lap_check.gd

const HZ := 120.0

var _failed := false
var _circuit: Circuit
var _car: Car
var _ticks := 0


func _initialize() -> void:
	_circuit = load("res://track/loop_1.tscn").instantiate()
	root.add_child(_circuit)
	_car = load("res://car/car.tscn").instantiate()
	root.add_child(_car)


# Nodes are ready and the physics world exists only once the tree runs.
func _physics_process(_delta: float) -> bool:
	_ticks += 1
	if _ticks == 1:
		_car.place_at(_circuit.get_node("Spawn").global_transform)
		_check_circuit()
		_check_timer()
		_check_records()
	if _ticks < int(HZ * 1.5):
		return false
	_check_car_on_road()
	print("LAP CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _check_circuit() -> void:
	var c := _circuit
	_check(c.closure_gap() < 0.05, "loop closes (gap %.3f m)" % c.closure_gap())
	_check(c.heading_gap() < 0.001, "loop ends facing the way it starts")
	_check(c.lap_length() > 1400.0 and c.lap_length() < 1700.0, "lap is about 1.5 km (%.0f m)" % c.lap_length())
	_check(c.gate_count() == 7, "start line plus 6 checkpoints")
	_check(c.point_at(0.0).distance_to(c.point_at(c.lap_length())) < 0.01, "distance wraps round the lap")
	var space := c.get_world_3d().direct_space_state
	var on_road := _ground_at(space, c.gate(0).origin)
	_check(on_road.get("grip", -1.0) == 1.0, "start line is on road with grip 1")
	var beside: Vector3 = c.gate(0).origin + c.gate(0).basis.x * 20.0
	_check(is_equal_approx(_ground_at(space, beside).get("grip", -1.0), 0.6), "grass beside the road has grip 0.6")
	for i in c.gate_count():
		if _ground_at(space, c.gate(i).origin).get("grip", -1.0) != 1.0:
			_check(false, "gate %d is on the road" % i)


func _check_timer() -> void:
	var c := _circuit
	var gates: Array[Transform3D] = []
	for i in c.gate_count():
		gates.append(c.gate(i))
	var timer := LapTimer.new(gates, c.gate_half_width())
	var events: Array[String] = []
	timer.lap_started.connect(func(): events.append("start"))
	timer.split.connect(func(_i, _t, _d): events.append("split"))
	timer.lap_voided.connect(func(): events.append("void"))
	var finished: Array[Dictionary] = []
	timer.lap_finished.connect(func(t, d, best): finished.append({"time": t, "delta": d, "best": best}))

	var start := c.start_distance
	var lap := c.lap_length()
	# Run up to the line, then two laps at 40 m/s and one at 50 m/s.
	var s := _drive(timer, start - 30.0, start + 2.0 * lap + 1.0, 40.0)
	_check(events.count("split") == 12 and events.count("start") == 3, "every checkpoint seen (%s)" % [events])
	_check(finished.size() == 2, "two laps finished")
	if finished.size() == 2:
		_check(absf(finished[0].time - lap / 40.0) < 0.002, "lap time matches distance over speed (%.3f s, expect %.3f)"
				% [finished[0].time, lap / 40.0])
		_check(finished[0].best and is_nan(finished[0].delta), "first lap is the best, no gap shown")
		_check(not finished[1].best and absf(finished[1].delta) < 0.002, "same pace: not a new best, gap near 0")
	s = _drive(timer, s, start + 3.0 * lap + 1.0, 50.0)
	_check(finished.size() == 3 and finished[2].best and finished[2].delta < -5.0, "faster lap is a new best")
	_check(finished.size() == 3 and timer.best_lap == finished[2].time, "best lap stored")
	_check(timer.best_splits.size() == 6, "best lap has 6 splits")

	# Back up over the line and cross again: checkpoints were skipped, so the lap is voided.
	events.clear()
	s = _drive(timer, s, s - 11.0, -20.0)
	_check(events.is_empty(), "driving backwards over the line does nothing")
	_drive(timer, s, s + 15.0, 30.0)
	_check(events == ["void", "start"], "shortcut lap is voided and a new lap starts (%s)" % [events])

	timer.cancel()
	_check(not timer.running and timer.lap_time == 0.0, "cancel stops the lap")
	var g := gates[0]
	timer.step(g.origin + g.basis.z * 5.0, g.origin - g.basis.z * 30.0, 1.0 / HZ)
	_check(not timer.running, "a teleport across the line doesn't start a lap")
	timer.step(g.origin + g.basis.z * 1.0 + g.basis.x * 20.0, g.origin - g.basis.z * 1.0 + g.basis.x * 20.0, 1.0 / HZ)
	_check(not timer.running, "crossing far off the road doesn't count")
	_check(LapTimer.format(83.4567) == "1:23.457", "time format (%s)" % LapTimer.format(83.4567))


func _check_records() -> void:
	var path := OS.get_temp_dir().path_join("racer_lap_check_%d.cfg" % OS.get_process_id())
	_check(path.begins_with(OS.get_temp_dir()) and not path.begins_with("user://"),
			"records file is in the temp folder: %s" % path)
	var records := LapRecords.new(path)
	_check(records.path == path, "records use the temp path")
	_check(records.best("loop_1").is_empty(), "no record before the first save")
	var splits: Array[float] = [10.0, 20.5]
	_check(records.save_best("loop_1", 61.25, splits) == OK, "save works")
	_check(records.save_best("other", 99.0, splits) == OK, "second track saves")
	var best := records.best("loop_1")
	_check(best.get("time", 0.0) == 61.25 and best.get("splits", []) == splits, "record reads back")
	_check(records.best("other").get("time", 0.0) == 99.0, "other track kept")
	DirAccess.remove_absolute(path)


func _check_car_on_road() -> void:
	var all_on_road := true
	for wheel in _car.wheels:
		all_on_road = all_on_road and wheel.on_ground and wheel.surface_grip == 1.0
	_check(all_on_road, "car settles on the road at the spawn point")


## Moves a point along the centreline at a steady speed, one physics tick at a time.
## Negative speed drives backwards. Returns where it stopped.
func _drive(timer: LapTimer, from: float, to: float, speed: float) -> float:
	var s := from
	var step := speed / HZ
	var here := _circuit.point_at(s)
	while (step > 0.0 and s < to) or (step < 0.0 and s > to):
		s += step
		var next := _circuit.point_at(s)
		timer.step(here, next, 1.0 / HZ)
		here = next
	return s


func _ground_at(space: PhysicsDirectSpaceState3D, where: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(where + Vector3.UP * 2.0, where - Vector3.UP * 2.0)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"grip": hit.collider.get_meta("grip", 1.0)}


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
