extends SceneTree
## Headless check for the Blender track (ridge): markers, centreline, surfaces and a timed lap.
## Writes no files.
## Run: godot --headless --path . -s tests/track_check.gd

const HZ := 120.0

var _failed := false
var _track: BlenderTrack
var _car: Car
var _ticks := 0


func _initialize() -> void:
	_track = load("res://track/ridge/ridge.tscn").instantiate()
	root.add_child(_track)
	_car = load("res://car/car.tscn").instantiate()
	root.add_child(_car)


# Nodes are ready and the physics world exists only once the tree runs.
func _physics_process(_delta: float) -> bool:
	_ticks += 1
	if _ticks == 1:
		_car.place_at(_track.get_node("Spawn").global_transform)
	if _ticks == 2:
		# Collision shapes are in the physics world from the second tick.
		_check_layout()
		_check_surfaces()
		_check_timer()
	if _ticks < int(HZ * 1.5):
		return false
	_check_car_on_road()
	print("TRACK CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _check_layout() -> void:
	var t := _track
	var lap := t.lap_length()
	_check(t.track_id == "ridge", "track id is ridge")
	_check(lap > 2000.0 and lap < 3000.0, "lap is 2 to 3 km (%.0f m)" % lap)
	_check(t.gate_count() == 7, "start line plus 6 checkpoints (%d gates)" % t.gate_count())
	_check(t.point_at(0.0).distance_to(t.gate(0).origin) < 2.5, "distance 0 is at the start line")
	_check(t.direction_at(0.0).dot(-t.gate(0).basis.z) > 0.95, "centreline runs the way the start line faces")
	_check(t.point_at(-1.0).distance_to(t.point_at(lap - 1.0)) < 0.01, "distance wraps round the lap")
	var climb := 0.0
	var low := INF
	var high := -INF
	var s := 0.0
	while s < lap:
		var dy := t.point_at(s + 2.0).y - t.point_at(s).y
		climb = maxf(climb, absf(dy) / 2.0)
		low = minf(low, t.point_at(s).y)
		high = maxf(high, t.point_at(s).y)
		s += 2.0
	_check(high - low > 10.0, "track has hills (%.1f m from lowest to highest)" % (high - low))
	_check(climb < 0.12, "no slope steeper than 12%% (steepest %.1f%%)" % (climb * 100.0))
	var last := -1.0
	var in_order := true
	for i in t.gate_count():
		var d := _distance_of(t.gate(i).origin)
		in_order = in_order and d > last
		last = d
	_check(in_order, "gates are in driving order")


func _check_surfaces() -> void:
	var t := _track
	var space := t.get_world_3d().direct_space_state
	for i in t.gate_count():
		if _ground_at(space, t.gate(i).origin).get("grip", -1.0) != 1.0:
			_check(false, "gate %d is on the road" % i)
	_check(_ground_at(space, t.get_node("Spawn").global_position).get("grip", -1.0) == 1.0, "spawn is on the road")
	# Look across the track every 10 m: road all the way across the middle, no holes anywhere near it.
	# Start 0.5 m in: a ray exactly on a seam between two road triangles can slip through to the grass.
	var seen := {}
	var holes := 0
	var road_gaps := 0
	var s := 0.5
	while s < t.lap_length():
		var middle := t.point_at(s)
		var side := t.direction_at(s).cross(Vector3.UP).normalized()
		for x in range(-40, 41, 2):
			var ground := _ground_at(space, middle + side * x)
			if ground.is_empty():
				holes += 1
				continue
			var grip: float = ground.grip
			seen[snappedf(grip, 0.01)] = true
			if absi(x) <= 4 and grip != 1.0:
				road_gaps += 1
		s += 10.0
	_check(holes == 0, "ground everywhere within 40 m of the road (%d holes)" % holes)
	_check(road_gaps == 0, "road surface across the middle 8 m (%d misses)" % road_gaps)
	_check(seen.has(0.9), "kerbs found (grip 0.9)")
	_check(seen.has(0.6), "grass found (grip 0.6)")
	_check(seen.has(0.45), "gravel found (grip 0.45)")
	_check(t.model.find_child("wall", true, false) != null, "walls exist")
	var gravel := BlenderTrack.SURFACES.gravel
	var grass := BlenderTrack.SURFACES.grass
	_check(gravel.rolling_resistance > grass.rolling_resistance and gravel.grip < grass.grip,
			"gravel slows the car more than grass")


func _check_timer() -> void:
	var t := _track
	var gates: Array[Transform3D] = []
	for i in t.gate_count():
		gates.append(t.gate(i))
	var timer := LapTimer.new(gates, t.gate_half_width())
	var events: Array[String] = []
	timer.lap_started.connect(func(): events.append("start"))
	timer.split.connect(func(_i, _t, _d): events.append("split"))
	var finished: Array[float] = []
	timer.lap_finished.connect(func(time, _d, _best): finished.append(time))
	var lap := t.lap_length()
	var s := -30.0
	var here := t.point_at(s)
	while s < lap + 1.0:
		s += 40.0 / HZ
		var next := t.point_at(s)
		timer.step(here, next, 1.0 / HZ)
		here = next
	_check(events.count("start") == 2 and events.count("split") == 6, "every checkpoint seen (%s)" % [events])
	_check(finished.size() == 1 and absf(finished[0] - lap / 40.0) < 0.02,
			"lap time matches distance over speed (%s, expect %.3f)" % [finished, lap / 40.0])


func _check_car_on_road() -> void:
	var all_on_road := true
	for wheel in _car.wheels:
		all_on_road = all_on_road and wheel.on_ground and wheel.surface_grip == 1.0
	_check(all_on_road, "car settles on the road at the spawn point")
	_check(_car.linear_velocity.length() < 0.5, "car is still (%.2f m/s)" % _car.linear_velocity.length())


## Distance along the lap of the centreline point nearest a place.
func _distance_of(where: Vector3) -> float:
	var best := 0.0
	var best_gap := INF
	var s := 0.0
	while s < _track.lap_length():
		var gap := _track.point_at(s).distance_to(where)
		if gap < best_gap:
			best_gap = gap
			best = s
		s += 1.0
	return best


func _ground_at(space: PhysicsDirectSpaceState3D, where: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(where + Vector3.UP * 3.0, where - Vector3.UP * 3.0)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"grip": hit.collider.get_meta("grip", 1.0)}


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
