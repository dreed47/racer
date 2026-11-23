extends SceneTree
## Headless check for the course map: the Ridge outline fits the box, north is up, you and the
## AI car show in the right place, and N or D-pad left turns it on and off.
## Touches no files.
## Run: godot --headless --path . -s tests/map_check.gd

var _failed := false
var _ticks := 0
var _main: Node


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	(_main.get_node("PlayerDriver") as Node).process_mode = Node.PROCESS_MODE_DISABLED


func _physics_process(_delta: float) -> bool:
	_ticks += 1
	if _ticks < 3:
		return false
	_check_outline()
	_check_markers()
	_check_toggle()
	_main.free()
	print("MAP CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _map() -> CourseMap:
	return _main.get_node("CourseMap") as CourseMap


func _check_outline() -> void:
	var map := _map()
	var track := _main.get_node("Track") as Track
	_check(map.outline.size() > 300, "outline follows the track (%d points)" % map.outline.size())
	var low := Vector2(INF, INF)
	var high := -low
	for p in map.outline:
		low = low.min(p)
		high = high.max(p)
	var box := Rect2(Vector2.ZERO, Vector2(CourseMap.SIZE, CourseMap.SIZE))
	_check(box.has_point(low) and box.has_point(high), "whole track fits in the map box")
	_check(maxf(high.x - low.x, high.y - low.y) > CourseMap.SIZE * 0.8, "track fills the box")
	var a := map.to_map(Vector3(0, 0, 0))
	_check(map.to_map(Vector3(0, 0, -100)).y < a.y, "north is up")
	_check(map.to_map(Vector3(100, 0, 0)).x > a.x, "east is right")
	_check(map.to_map(Vector3(0, 50, 0)) == a, "height doesn't move the map")
	_check(map.outline[0].distance_to(map.to_map(track.point_at(0.0))) < 0.01, "outline starts at the track start")


func _check_markers() -> void:
	var map := _map()
	var car := _main.get_node("Car") as Car
	var you := map.to_map(car.global_position)
	var nearest := INF
	for p in map.outline:
		nearest = minf(nearest, p.distance_to(you))
	_check(nearest < 6.0, "your arrow sits on the track (%.1f px off)" % nearest)
	var ai := _main.get_node("AiDriver") as AiDriver
	_check(map.ai == ai and map.car == car, "map shows your car and the AI's")
	var on_grid := map.to_map(ai.car.global_position)
	_check(Rect2(Vector2.ZERO, Vector2(CourseMap.SIZE, CourseMap.SIZE)).has_point(on_grid),
			"AI car is on the map")


func _check_toggle() -> void:
	var map := _map()
	var hud := _main.get_node("LapHud")
	_check(map.shown and map._canvas.visible, "map is on at the start")
	var heard: Array[bool] = []
	map.toggled.connect(func(on): heard.append(on))
	map.toggle()
	_check(not map.shown and not map._canvas.visible and heard == [false], "turns off")
	_check(hud._note.text == "Map off", "note says Map off (%s)" % hud._note.text)
	map.toggle()
	_check(map.shown and map._canvas.visible and heard == [false, true], "turns on again")
	_check(hud._note.text == "Map on", "note says Map on")

	var key := false
	var pad := false
	for e in InputMap.action_get_events("toggle_map"):
		key = key or (e is InputEventKey and e.physical_keycode == KEY_N)
		pad = pad or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_DPAD_LEFT)
	_check(key and pad, "N and D-pad left turn the map on and off")
	var clash := ""
	for action in InputMap.get_actions():
		if action == "toggle_map" or action.begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(action):
			if (e is InputEventKey and e.physical_keycode == KEY_N) \
					or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_DPAD_LEFT):
				clash = action
	_check(clash == "", "no other action uses N or D-pad left %s" % clash)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
