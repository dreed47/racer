extends SceneTree
## Headless check for the tuning panel: slider changes reach the car, Save writes, Revert reads back.
## Saves only to a file in the system temp folder, never to the real car setup.
## Run: godot --headless --path . -s tests/panel_check.gd

var _failed := false
var _panel
var _car
var _scratch := ""


func _initialize() -> void:
	var scratch := OS.get_temp_dir().path_join("racer_panel_check_%d.tres" % OS.get_process_id())
	_check(scratch.begins_with(OS.get_temp_dir()) and not scratch.begins_with("res://"),
			"save path is in the temp folder: %s" % scratch)

	var car: Car = load("res://car/car.tscn").instantiate()
	car.setup = car.setup.duplicate()  # Leave the cached real setup alone.
	root.add_child(car)
	var panel = load("res://debug/tuning_panel.gd").new()
	panel.save_path = scratch
	panel.car = car
	root.add_child(panel)
	_check(panel.save_path == scratch, "panel uses the scratch path")
	_panel = panel
	_car = car
	_scratch = scratch


# Nodes are ready only once the tree runs, so the checks wait for the first frame.
func _process(_delta: float) -> bool:
	var panel = _panel
	var car: Car = _car
	var scratch := _scratch

	_check(panel._sliders.size() > 30, "panel has a slider per number (%d)" % panel._sliders.size())
	_check(not panel._sliders.has("torque_curve"), "arrays are left out")

	panel.toggle()
	_check(panel.is_open() and paused, "opening pauses the game")

	panel.set_value("wheelbase", 2.5)
	_check(is_equal_approx(car.setup.wheelbase, 2.5), "slider sets the setup")
	_check(is_equal_approx(car.get_node("WheelFL").position.z, -1.25), "wheel moves with wheelbase")

	_check(panel.save() == OK, "save works")
	panel.set_value("wheelbase", 2.1)
	_check(panel.revert() == OK, "revert works")
	_check(is_equal_approx(car.setup.wheelbase, 2.5), "revert brings back the saved value")
	_check(is_equal_approx(panel._sliders["wheelbase"].value, 2.5), "slider follows revert")

	panel.toggle()
	_check(not panel.is_open() and not paused, "closing unpauses")

	DirAccess.remove_absolute(scratch)
	print("PANEL CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
