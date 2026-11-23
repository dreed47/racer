extends SceneTree
## Headless check for the ghost car: recording and playback, saving and loading, keeping only
## the fastest lap, the see-through car following the lap, and the on/off key.
## Writes only to a temp folder (see SavePaths), never to the real saved files in user://.
## Run: godot --headless --path . -s tests/ghost_check.gd

var _failed := false
var _main: Node
var _real_before := {}


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	var tt := _main.get_node("TimeTrial") as TimeTrial
	_real_before = _real_state(tt)
	_check_paths(tt)
	_check_recording()
	_check_files()
	_check_time_trial(tt)
	_check_ghost_car(tt)
	_check_input()
	_check(_real_state(tt) == _real_before, "real saved files untouched")
	_main.free()
	_remove_dir(SavePaths.test_dir())
	print("GHOST CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _check_paths(tt: TimeTrial) -> void:
	var temp := SavePaths.test_dir()
	_check(SavePaths.running_test(), "test run is detected")
	_check(temp.begins_with(OS.get_temp_dir()), "test folder is in the system temp folder: %s" % temp)
	_check(tt.ghost_path().begins_with(temp), "ghost file goes to the test folder: %s" % tt.ghost_path())
	_check(tt.records.path.begins_with(temp), "records file goes to the test folder: %s" % tt.records.path)
	_check(SavePaths.safe("/tmp/x.cfg") == "/tmp/x.cfg", "paths outside user:// are kept")


## A straight 10 s lap along -z at 10 m/s, sampled at 60 Hz.
func _straight_lap(time := 10.0) -> GhostRecording:
	var rec := GhostRecording.new("test")
	var t := 0.0
	while t <= time + 0.0001:
		rec.add(t, Transform3D(Basis.IDENTITY, Vector3(0, 0, -10.0 * t)), 0.1 * t, Vector4(-0.1, -0.1, -0.2, -0.2))
		t += 1.0 / 120.0
	rec.lap_time = time
	return rec


func _check_recording() -> void:
	var rec := _straight_lap()
	_check(absi(rec.size() - 601) <= 2, "samples about 60 a second (%d in 10 s)" % rec.size())
	var mid := rec.transform_at(5.004)
	_check(mid.origin.distance_to(Vector3(0, 0, -50.04)) < 0.01, "position blends between samples")
	_check(absf(rec.steer_at(5.004) - 0.5004) < 0.001, "steer blends between samples")
	_check(rec.drops_at(3.0).is_equal_approx(Vector4(-0.1, -0.1, -0.2, -0.2)), "wheel drops read back")
	_check(rec.transform_at(-1.0).origin.is_equal_approx(Vector3.ZERO), "before the start holds the first place")
	_check(rec.transform_at(99.0).origin.distance_to(Vector3(0, 0, -100)) < 0.2, "after the end holds the last place")
	var turn := GhostRecording.new()
	turn.add(0.0, Transform3D.IDENTITY, 0.0, Vector4.ZERO)
	turn.add(1.0, Transform3D(Basis(Vector3.UP, 1.0), Vector3.ZERO), 0.0, Vector4.ZERO)
	var angle := turn.transform_at(0.5).basis.get_euler().y
	_check(absf(angle - 0.5) < 0.001, "rotation blends between samples (%.3f)" % angle)


func _check_files() -> void:
	var dir := SavePaths.test_dir()
	var path := dir.path_join("ghosts/test.ghost")
	_check(GhostRecording.load_file(path) == null, "no ghost before the first save")
	var rec := _straight_lap()
	_check(rec.save(path) == OK, "ghost saves")
	_check(not FileAccess.file_exists(path + ".tmp"), "no temp file left behind")
	var back := GhostRecording.load_file(path)
	_check(back != null and back.size() == rec.size() and back.lap_time == 10.0 and back.track_id == "test",
		"ghost reads back")
	_check(back != null and back.transform_at(5.0).origin.is_equal_approx(rec.transform_at(5.0).origin),
		"read-back ghost is in the same place")
	var junk := FileAccess.open(dir.path_join("junk.ghost"), FileAccess.WRITE)
	junk.store_string("not a ghost")
	junk.close()
	_check(GhostRecording.load_file(dir.path_join("junk.ghost")) == null, "damaged file is ignored")
	var old := FileAccess.open(dir.path_join("old.ghost"), FileAccess.WRITE)
	old.store_var({"version": GhostRecording.VERSION + 1})
	old.close()
	_check(GhostRecording.load_file(dir.path_join("old.ghost")) == null, "other version is ignored")


func _check_time_trial(tt: TimeTrial) -> void:
	DirAccess.remove_absolute(tt.ghost_path())
	tt.ghost = null
	tt.timer.lap_started.emit()
	_fill(tt._recording, 12.0)
	tt._on_lap_finished(12.0, NAN, true)
	_check(tt.ghost != null and tt.ghost.lap_time == 12.0, "first lap becomes the ghost")
	_check(FileAccess.file_exists(tt.ghost_path()), "ghost saved")

	tt.timer.lap_started.emit()
	_fill(tt._recording, 13.0)
	tt._on_lap_finished(13.0, 1.0, false)
	_check(tt.ghost.lap_time == 12.0, "slower lap doesn't replace the ghost")

	tt.timer.lap_started.emit()
	_fill(tt._recording, 11.0)
	tt._on_lap_finished(11.0, -1.0, true)
	_check(tt.ghost.lap_time == 11.0, "faster lap replaces the ghost")
	var saved := GhostRecording.load_file(tt.ghost_path())
	_check(saved != null and saved.lap_time == 11.0, "faster lap saved")

	tt.timer.lap_started.emit()
	_fill(tt._recording, 5.0)
	tt._on_car_placed()
	_check(tt._recording == null, "reset throws the lap's recording away")


func _fill(rec: GhostRecording, time: float) -> void:
	var t := 0.0
	while t < time:
		rec.add(t, Transform3D(Basis.IDENTITY, Vector3(0, 0, -10.0 * t)), 0.0, Vector4.ZERO)
		t += 1.0 / 60.0


func _check_ghost_car(tt: TimeTrial) -> void:
	var ghost := _main.get_node("GhostCar") as GhostCar
	_check(ghost != null, "GhostCar in main scene")
	var meshes := ghost.find_children("*", "MeshInstance3D", true, false)
	var all_see_through := meshes.size() > 4
	for mesh in meshes:
		var m := (mesh as MeshInstance3D).material_override as StandardMaterial3D
		all_see_through = all_see_through and m != null and m.albedo_color.a < 1.0 \
			and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_check(all_see_through, "every ghost mesh is see-through with no shadow (%d meshes)" % meshes.size())
	_check(ghost.find_children("*", "CollisionObject3D", true, false).is_empty(), "ghost has no collision")

	tt.ghost = _straight_lap()
	tt.timer.cancel()
	ghost._physics_process(1.0 / 120.0)
	_check(not ghost.visible, "hidden when no lap is running")
	tt.timer.running = true
	tt.timer.lap_time = 4.0
	ghost._physics_process(1.0 / 120.0)
	_check(ghost.visible and ghost.global_position.distance_to(Vector3(0, 0, -40)) < 0.01,
		"follows the ghost lap at the same lap time")
	tt.timer.lap_time = 4.1
	ghost._physics_process(1.0 / 120.0)
	var spin := ghost._spins[0].rotation.x
	_check(spin != 0.0, "wheels roll")
	tt.timer.lap_time = 11.0
	ghost._physics_process(1.0 / 120.0)
	_check(not ghost.visible, "hidden after the ghost lap ends")
	tt.timer.lap_time = 4.0
	ghost.toggle()
	ghost._physics_process(1.0 / 120.0)
	_check(not ghost.shown and not ghost.visible, "turns off")
	ghost.toggle()
	ghost._physics_process(1.0 / 120.0)
	_check(ghost.shown and ghost.visible, "turns back on")
	tt.timer.cancel()


func _check_input() -> void:
	var key := false
	var pad := false
	for e in InputMap.action_get_events("toggle_ghost"):
		key = key or (e is InputEventKey and e.physical_keycode == KEY_G)
		pad = pad or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_DPAD_UP)
	_check(key and pad, "G and D-pad up toggle the ghost")


## Existence and change time of the real saved files, to prove the test leaves them alone.
func _real_state(tt: TimeTrial) -> Dictionary:
	var state := {}
	for path in [tt.ghost_dir.path_join(tt.track.track_id + ".ghost"), tt.records_path]:
		var real := ProjectSettings.globalize_path(path)
		state[real] = FileAccess.get_modified_time(real) if FileAccess.file_exists(real) else -1
	return state


func _remove_dir(path: String) -> void:
	if not path.begins_with(OS.get_temp_dir()):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
