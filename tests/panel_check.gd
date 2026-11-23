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

	# Closing with unsaved changes asks first.
	panel.toggle()
	_check(panel._toggles.has("traction_control"), "on/off settings get a switch")
	panel.set_value("traction_control", false)
	_check(car.setup.traction_control == false, "switch sets the setup")
	panel.set_value("wheelbase", 2.3)
	_check(panel.unsaved_changes() == PackedStringArray(["wheelbase", "traction_control"]),
			"unsaved changes listed (%s)" % [panel.unsaved_changes()])
	panel.toggle()
	_check(panel.is_asking() and panel.is_open() and paused, "closing with unsaved changes asks first")
	panel.back_to_panel()
	_check(panel.is_open() and not panel.is_asking(), "back returns to the setup")
	panel.toggle()
	panel.close()
	_check(not panel.is_open() and not paused, "drive without saving closes")
	_check(is_equal_approx(car.setup.wheelbase, 2.3), "unsaved change stays on the car")
	panel.toggle()
	panel.toggle()
	panel._undo_and_close()
	_check(not panel.is_open() and is_equal_approx(car.setup.wheelbase, 2.5) and car.setup.traction_control,
			"undo changes restores the saved values and closes")
	panel.toggle()
	panel.set_value("wheelbase", 2.4)
	panel.toggle()
	panel._save_and_close()
	_check(not panel.is_open() and not panel.has_unsaved_changes(), "save from the question saves and closes")
	var on_disk := ResourceLoader.load(scratch, "", ResourceLoader.CACHE_MODE_IGNORE) as CarSetup
	_check(on_disk != null and is_equal_approx(on_disk.wheelbase, 2.4), "saved value is in the scratch file")
	panel.toggle()
	panel.toggle()
	_check(not panel.is_open(), "no changes: Tab closes straight away")

	# A real Tab key press while a slider has focus, as when driving the panel by hand.
	panel.toggle()
	panel._first_slider.grab_focus()
	root.push_input(_tab_key())
	_check(not panel.is_open(), "Tab key closes the panel even while a slider has focus")
	root.push_input(_tab_key())
	_check(panel.is_open(), "Tab key opens it again")
	panel.close()

	# Clicking outside the panel closes it, but asks first if there are unsaved changes.
	panel.toggle()
	root.push_input(_click(Vector2(100, 500)))
	_check(not panel.is_open() and not paused, "click outside the panel closes it")
	panel.toggle()
	root.push_input(_click(panel._panel.get_global_rect().get_center()))
	_check(panel.is_open() and not panel.is_asking(), "click inside the panel keeps it open")
	panel.set_value("wheelbase", 2.2)
	root.push_input(_click(Vector2(100, 500)))
	_check(panel.is_asking(), "click outside with unsaved changes asks first")
	panel.back_to_panel()
	_check(_save_button(panel) != null, "panel has a Save button")
	_save_button(panel).pressed.emit()
	_check(not panel.is_open() and not panel.has_unsaved_changes(), "Save button saves and closes")

	DirAccess.remove_absolute(scratch)
	print("PANEL CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _click(where: Vector2) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = where
	click.global_position = where
	return click


func _save_button(panel) -> Button:
	for button in panel._panel.find_children("*", "Button", true, false):
		if button.text == "Save":
			return button
	return null


func _tab_key() -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_TAB
	key.keycode = KEY_TAB
	key.pressed = true
	return key


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
