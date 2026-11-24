extends SceneTree
## Headless check for the Clarion loop (a RoadTrack built from map data): length, gates, hills,
## road surface, ground near the road, closed side streets, resets near the car, a timed lap and the car at the start.
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
		_check_side_streets()
		_check_buildings()
		_check_detour()
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
	_check(trees != null and trees.multimesh.instance_count > 500, "trees along the road")


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


## Side streets: drivable stubs that end at a solid barrier well clear of the loop.
func _check_side_streets() -> void:
	var t := _track
	var space := t.get_world_3d().direct_space_state
	var list: Array = t._data.get("side_streets", [])
	_check(list.size() >= 40, "side streets closed off (%d)" % list.size())
	var too_close := 0
	var road_misses := 0
	var not_blocked := 0
	var too_high := 0
	for stub: Dictionary in list:
		var b: Array = stub.barrier
		var foot := t.to_global(Vector3(b[0], b[1], b[2]))
		var toward_loop := Vector3(b[3], 0.0, b[4]).normalized()
		var nearest := INF
		for p in t._points:
			nearest = minf(nearest, Vector2(p.x - b[0], p.z - b[2]).length())
		if nearest < 12.0:
			too_close += 1
		# A car driving up the stub towards the barrier runs into it.
		var start := foot + toward_loop * 3.0 + Vector3.UP * 0.8
		var query := PhysicsRayQueryParameters3D.create(start, foot + Vector3.UP * 0.8)
		query.exclude = [_car.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty() or String(hit.collider.name) != "Barriers":
			not_blocked += 1
		var flat: Array = stub.edges
		for k in range(int(stub.shoulder_from) * 6, flat.size() - 6, 6):
			var middle := Vector3((flat[k] + flat[k + 3]) / 2.0, (flat[k + 1] + flat[k + 4]) / 2.0,
					(flat[k + 2] + flat[k + 5]) / 2.0)
			if middle.distance_to(Vector3(b[0], b[1], b[2])) < 3.0:
				continue
			if _ground_at(space, t.to_global(middle)) != "SideStreets":
				road_misses += 1
			if t.ground_height(middle.x, middle.z) > middle.y + 0.3:
				too_high += 1
	_check(too_close == 0, "every barrier at least 12 m from the loop (%d too close)" % too_close)
	_check(not_blocked == 0, "every side street blocked by a solid barrier (%d open)" % not_blocked)
	_check(road_misses == 0, "side street road surface up to the barrier (%d misses)" % road_misses)
	_check(too_high == 0, "ground never pokes up through a side street (%d places)" % too_high)

	# Where a street joins, the road's edge is open: road surface, not grass, just past the edge.
	var cuts: Dictionary = t._data.get("mouth_cuts", {})
	var grass_at_mouth := 0
	var mouth_points := 0
	for key in ["left", "right"]:
		var side := -1.0 if key == "left" else 1.0
		for i in cuts.get(key, []):
			var j := (int(i) + 1) % t._points.size()
			var middle := (t._points[int(i)] + t._points[j]) / 2.0
			var across := (t._right(int(i)) + t._right(j)).normalized()
			var spot := middle + across * side * (t._half + 0.3)
			mouth_points += 1
			if _ground_at(space, t.to_global(spot)) == "Shoulder":
				grass_at_mouth += 1
	_check(mouth_points > 100, "street mouths leave the road's edge open (%d segments)" % mouth_points)
	_check(grass_at_mouth == 0, "no strip of grass between the loop and a street (%d places)" % grass_at_mouth)

	# Name signs: one per named street, on both faces, standing off the loop's road.
	var signed := 0
	var named := 0
	var on_road := 0
	var i80 := 0
	for stub: Dictionary in list:
		var spot: Array = stub.get("sign_post", [])
		if not String(stub.get("name", "")).is_empty() or not String(stub.get("sign", "")).is_empty():
			named += 1
		if String(stub.get("sign", "")).is_empty() or spot.is_empty():
			continue
		signed += 1
		if stub.sign == "I-80":
			i80 += 1
		for p in t._points:
			if Vector2(p.x - spot[0], p.z - spot[2]).length() < t._half + 1.0:
				on_road += 1
				break
	var labels := 0
	for child in t.get_children():
		if child is Label3D and child.text != "ROAD CLOSED":
			labels += 1
	# Some map roads have no name, so they get no sign. The detour has its own signs too.
	var detour_signs: int = t._data.get("detour", {}).get("signs", []).size()
	_check(signed == named and signed > list.size() * 0.9,
			"street-name signs on the named side streets (%d of %d named, %d streets)" % [signed, named, list.size()])
	_check(labels == (signed + detour_signs) * 2, "each name sign readable from both sides (%d labels)" % labels)
	_check(on_road == 0, "no name sign on the loop's road (%d)" % on_road)
	_check(i80 >= 2, "I-80 carries on past both of its ramps (%d stubs)" % i80)


## Buildings: real outlines with sensible heights, solid to drive into, and the business signs.
func _check_buildings() -> void:
	var t := _track
	var space := t.get_world_3d().direct_space_state
	var list: Array = t._data.get("buildings", [])
	var mesh := t.find_child("BuildingMeshes", true, false) as MeshInstance3D
	_check(list.size() > 500, "buildings in town (%d)" % list.size())
	_check(mesh != null and mesh.mesh.get_faces().size() > list.size() * 12, "every building drawn")
	var odd := 0
	var sloped := 0
	var roof_misses := 0
	for k in list.size():
		var b: Dictionary = list[k]
		var top := float(b.get("ridge", b.eave))
		if float(b.eave) < 2.0 or float(b.eave) > 60.0 or top < float(b.eave):
			odd += 1
		if b.has("roof"):
			sloped += 1
		# Every tenth building: a ray from above lands on it, about as high as its top.
		if k % 10 != 0:
			continue
		var ring: Array = b.ring
		var middle := Vector2.ZERO
		for n in range(0, ring.size(), 2):
			middle += Vector2(ring[n], ring[n + 1])
		middle /= ring.size() / 2.0
		var from := t.to_global(Vector3(middle.x, float(b.y) + top + 20.0, middle.y))
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (top + 40.0))
		query.exclude = [_car.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty() or String(hit.collider.name) != "Buildings":
			roof_misses += 1
	_check(odd == 0, "building heights 2 to 60 m, ridge above the eaves (%d odd)" % odd)
	_check(sloped > list.size() / 4, "many sloped roofs (%d of %d)" % [sloped, list.size()])
	# A few outlines are L or U shaped, so the middle can be outside them.
	_check(roof_misses < list.size() / 50, "buildings are solid from above (%d misses)" % roof_misses)

	var signs: Array = t._data.get("businesses", [])
	var holder := t.get_node_or_null("BusinessSigns")
	var labels := holder.get_child_count() if holder != null else 0
	var poles := 0
	var on_road := 0
	for biz: Dictionary in signs:
		for key in ["wall", "pole"]:
			var spot: Array = biz.get(key, [])
			if spot.is_empty():
				continue
			if key == "pole":
				poles += 1
			for p in t._points:
				if Vector2(p.x - spot[0], p.z - spot[2]).length() < t._half + 1.0:
					on_road += 1
					break
	var listed: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/clarion/businesses.json"))
	_check(signs.size() == listed.size(),
			"a sign for each listed business (%d of %d)" % [signs.size(), listed.size()])
	_check(labels == signs.size() + poles * 2, "business names on walls and both sides of road signs (%d)" % labels)
	_check(on_road == 0, "no business sign on the road (%d)" % on_road)


func _check_detour() -> void:
	var t := _track
	var space := t.get_world_3d().direct_space_state
	var points: PackedVector3Array = t._detour_points
	_check(points.size() > 100, "detour road exists (%d points)" % points.size())
	_check(t.side_roads().size() == 1 and t.side_roads()[0].size() > points.size(),
			"course map gets the detour, ends included")
	if points.size() < 2:
		return
	var first := t.to_global(points[0])
	var last := t.to_global(points[points.size() - 1])
	var first_gap := t.point_at(_distance_of(first)).distance_to(first)
	var last_gap := t.point_at(_distance_of(last)).distance_to(last)
	_check(first_gap < 30.0 and last_gap < 30.0,
			"detour leaves and rejoins the loop (%.0f m, %.0f m)" % [first_gap, last_gap])
	var far := 0.0
	var misses := 0
	for i in range(0, points.size(), 5):
		var p := t.to_global(points[i])
		far = maxf(far, t.point_at(_distance_of(p)).distance_to(p))
		var under := _ground_at(space, p)
		if under != "Detour" and under != "Road":
			misses += 1
	_check(far > 300.0, "detour goes well away from the loop (%.0f m)" % far)
	_check(misses == 0, "detour road surface all the way, no barriers on it (%d misses)" % misses)
	var mid := t.to_global(points[points.size() / 2])
	var ahead := t.to_global(points[points.size() / 2 + 1]) - mid
	var side := ahead.cross(Vector3.UP).normalized()
	var place := t.reset_transform(mid + side * 6.0 + Vector3.UP * 3.0)
	var gap := Vector2(place.origin.x - mid.x, place.origin.z - mid.z).length()
	var facing := (-place.basis.z).dot(ahead.normalized())
	_check(gap < 5.0 and absf(facing) > 0.9,
			"reset on the detour puts the car on it, along the road (%.1f m off, facing %.2f)" % [gap, facing])
	var house: Node3D = null
	for child in t.get_children():
		if child is FeatureHouse:
			house = child
	_check(house != null and house.has_node("FeatureHouseBody"), "403 Ridgewood Rd is built and solid")
	if house == null:
		return
	var near := INF
	for p in points:
		near = minf(near, t.to_global(p).distance_to(house.global_position))
	_check(near < 40.0, "the house faces the detour (%.0f m from the road)" % near)
	var owners := house.get_node_or_null("Owners")
	_check(owners != null and owners.get_child_count() == 2, "two owners stand on the porch")
	var start: Node3D = t.get_node_or_null("DetourSpawn")
	_check(start != null, "the detour start marker exists")
	if start == null:
		return
	var at := start.global_position
	var to_junction := at.distance_to(first)
	var along := (-start.global_basis.z).dot(t.direction_at(_distance_of(at)))
	_check(_ground_at(space, at) == "Road" and to_junction < 120.0 and along > 0.9,
			"detour start sits on Route 66 just before the junction (%.0f m, facing %.2f)" % [to_junction, along])


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
