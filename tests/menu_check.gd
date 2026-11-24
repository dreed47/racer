extends SceneTree
## Headless check for the track menu: one button per track, the first has focus, every track
## scene loads, and picking a track starts the game on it. Writes no files.
## Run: godot --headless --path . -s tests/menu_check.gd

var _failed := false
var _menu: TrackMenu
var _frames := 0


func _initialize() -> void:
	_menu = load("res://menu/track_menu.tscn").instantiate()
	root.add_child(_menu)
	current_scene = _menu


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_check_buttons()
		var practice: Button = _menu.get_node("%Buttons").get_child(0)
		practice.pressed.emit()
		_check(practice.disabled and _menu.get_node("%Loading").visible, "picking a track shows Loading")
	if _frames < 30:
		return false
	_check_game_started()
	print("MENU CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _check_buttons() -> void:
	var buttons: Array[Node] = _menu.get_node("%Buttons").get_children()
	_check(buttons.size() == TrackMenu.TRACKS.size(), "one button per track (%d)" % buttons.size())
	_check(buttons[0].has_focus(), "first button has focus, so Enter or A works at once")
	_check(buttons[0].text.begins_with("Practice track"), "first button is the practice track")
	for entry in TrackMenu.TRACKS:
		var scene := load(entry.scene) as PackedScene
		var track: Node = scene.instantiate() if scene else null
		_check(track is Track, "%s scene is a track" % entry.name)
		if track:
			track.free()


func _check_game_started() -> void:
	var main := current_scene as Main
	_check(main != null, "game scene is running")
	_check(not is_instance_valid(_menu), "menu is gone")
	if main == null:
		return
	var track := main.get_node_or_null("Track") as Track
	_check(track != null and track.track_id == "ridge", "game is on the practice track")
	_check(main.get_child(0) == track, "track is the first child, so it is ready before the drivers")


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
