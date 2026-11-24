extends SceneTree
## Headless check for the Clarion loop (a RoadTrack built from map data): length, gates, hills,
## road surface, ground near the road, resets near the car, a timed lap and the car at the start.
## Writes no files.
## Run: godot --headless --path . -s tests/clarion_check.gd

const HZ := 120.0

var _failed := false
var _track: RoadTrack
var _car: Car
var _ticks := 0


func _initialize() -> void:
	_track = load("res://track/clarion/clarion.tscn").instantiate()
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
		_check_reset()
		_check_timer()
	if _ticks < int(HZ * 1.5):
		return false
	_check_car_on_road()
	print("CLARION CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _check_layout() -> void:
	var t := _track
	var lap := t.lap_length()
	_check(t.track_id == "clarion", "track id is clarion")
	_check(lap > 15000.0 and lap < 19000.0, "lap is 15 to 19 km (%.0f m)" % lap)
	_check(t.gate_count() == 4, "start line plus 3 checkpoints (%d gates)" % t.gate_count())
	_check(t.point_at(t.start_line_distance()).distance_to(t.gate(0).origin) < 0.01,
			"start gate is at the start line distance")
	_check(t.direction_at(t.start_line_distance()).dot(-t.gate(0).basis.z) > 0.95,
			"centreline runs the way the start line faces")
	_check(t.point_at(-1.0).distance_to(t.point_at(lap - 1.0)) < 0.01, "distance wraps round the lap")
	_check(t.point_at(lap - 0.5).distance_to(t.point_at(0.5)) < 2.0, "road joins up at the end of the lap")
	var climb := 0.0
	var low := INF
	var high := -INF
	var s := 0.0
	while s < lap:
		var y := t.point_at(s).y
		climb = maxf(climb, absf(t.point_at(s + 10.0).y - y) / 10.0)
		low = minf(low, y)
		high = maxf(high, y)
		s += 10.0
	_check(high - low > 30.0, "road has real hills (%.0f m from lowest to highest)" % (high - low))
	_check(climb < 0.12, "no slope steeper than 12%% (steepest %.1f%%)" % (climb * 100.0))
	var last := -1.0
	var in_order := true
	for i in t.gate_count():
		var d := _distance_of(t.gate(i).origin)
		in_order = in_order and d > last
		last = d
	_check(in_order, "gates are in driving order")
	var trees := t.find_child("TreeCrowns", true, false) as MultiMeshInstance3D
	var buildings := t.find_child("BuildingMeshes", true, false) as MultiMeshInstance3D
	_check(trees != null and trees.multimesh.instance_count > 500, "trees along the road")
	_check(buildings != null and buildings.multimesh.instance_count > 50, "buildings in town")


func _check_surfaces() -> void:
	var t := _track
	var space := t.get_world_3d().direct_space_state
	for i in t.gate_count():
		if _ground_at(space, t.gate(i).origin) != "Road":
			_check(false, "gate %d is on the road" % i)
	_check(_ground_at(space, t.get_node("Spawn").global_position) == "Road", "spawn is on the road")
	# Every 10 m: road across the middle 8 m, and ground of some kind out to 30 m each side.
	# The long reach finds the valley floor under the high bridges.
	var holes := 0
	var road_gaps := 0
	var too_high := 0
	var s := 0.5
	while s < t.lap_length():
		var middle := t.point_at(s)
		var side := t.direction_at(s).cross(Vector3.UP).normalized()
		for x in range(-30, 31, 2):
			var hit := _ground_at(space, middle + side * x, 200.0)
			if hit == "":
				holes += 1
			elif absi(x) <= 4 and hit != "Road":
				road_gaps += 1
		# The ground under the road is never above it, or the car would hit a hidden hill.
		var local := t.to_local(middle)
		if t.ground_height(local.x, local.z) > local.y + 0.3:
			too_high += 1
		s += 10.0
	_check(holes == 0, "ground everywhere within 30 m of the road (%d holes)" % holes)
	_check(road_gaps == 0, "road surface across the middle 8 m (%d misses)" % road_gaps)
	_check(too_high == 0, "ground never pokes up through the road (%d places)" % too_high)


func _check_reset() -> void:
	var t := _track
	for s in [2000.0, 8000.0, 14000.0]:
		var road := t.point_at(s)
		var side := t.direction_at(s).cross(Vector3.UP).normalized()
		var place := t.reset_transform(road + side * 15.0 + Vector3.UP * 5.0)
		var gap := Vector2(place.origin.x - road.x, place.origin.z - road.z).length()
		var facing := (-place.basis.z).dot(t.direction_at(s))
		_check(gap < 5.0 and facing > 0.9 and place.origin.y > road.y,
				"reset at %.0f m puts the car on the road, facing the right way (%.1f m off, facing %.2f)"
				% [s, gap, facing])


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
	var speed := 40.0
	var s := t.start_line_distance() - 30.0
	var here := t.point_at(s)
	while s < t.start_line_distance() + lap + 1.0:
		s += speed / HZ
		var next := t.point_at(s)
		timer.step(here, next, 1.0 / HZ)
		here = next
	_check(events.count("start") == 2 and events.count("split") == 3, "every checkpoint seen (%s)" % [events])
	_check(finished.size() == 1 and absf(finished[0] - lap / speed) < 0.05,
			"lap time matches distance over speed (%s, expect %.3f)" % [finished, lap / speed])


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
		s += 2.0
	return best


## Name of the body under a place, or "" if there is nothing there.
func _ground_at(space: PhysicsDirectSpaceState3D, where: Vector3, reach := 3.0) -> String:
	var query := PhysicsRayQueryParameters3D.create(where + Vector3.UP * reach, where - Vector3.UP * reach)
	query.exclude = [_car.get_rid()]  # The car sits on the spawn point.
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return ""
	return String(hit.collider.name)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
