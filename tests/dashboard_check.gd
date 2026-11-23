extends SceneTree
## Headless check for the gauges: they sit at the bottom centre clear of the map and grip display,
## the rev counter scale fits the redline, the shift light, the gear text, and F3 for the old
## text readout. Touches no files.
## Run: godot --headless --path . -s tests/dashboard_check.gd

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
	_check_layout()
	_check_scales()
	_check_shift_light()
	_check_readout()
	_main.free()
	print("DASHBOARD CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _dash() -> Dashboard:
	return _main.get_node("Dashboard") as Dashboard


func _check_layout() -> void:
	# Headless runs in a tiny window, so work out where each box lands on a full-size screen.
	var size := Vector2(1920, 1080)
	var screen := Rect2(Vector2.ZERO, size)
	var area := _on_screen(_dash()._canvas, size)
	_check(screen.encloses(area), "gauges fit on a 1920 x 1080 screen (%s)" % area)
	_check(absf(area.get_center().x - 960.0) < 1.0, "gauges are centred")
	_check(area.end.y > 1000.0, "gauges sit at the bottom")
	var map := _main.get_node("CourseMap") as CourseMap
	_check(not area.intersects(_on_screen(map._canvas, size)), "gauges clear the map")
	# The grip display has no size of its own: it draws four tires and the TC and ABS labels
	# up from its corner. Allow 400 px across for them.
	var grip: Control = _main.get_node("GripDisplay")._canvas
	var corner := _on_screen(grip, size).position
	_check(not area.intersects(Rect2(corner.x, corner.y, 400.0, size.y - corner.y)), "gauges clear the grip display")


## Where an anchored control would sit on a screen of the given size.
func _on_screen(control: Control, size: Vector2) -> Rect2:
	var top_left := Vector2(control.anchor_left, control.anchor_top) * size \
			+ Vector2(control.offset_left, control.offset_top)
	var bottom_right := Vector2(control.anchor_right, control.anchor_bottom) * size \
			+ Vector2(control.offset_right, control.offset_bottom)
	return Rect2(top_left, bottom_right - top_left)


func _check_scales() -> void:
	var dash := _dash()
	var car: Car = dash.car
	_check(dash.max_rpm() >= car.setup.redline_rpm + 1000.0 and fmod(dash.max_rpm(), 1000.0) == 0.0,
			"rev counter goes past the redline to a whole 1000 (%.0f)" % dash.max_rpm())
	_check(is_equal_approx(Dashboard.dial_angle(0.0), deg_to_rad(150.0)), "empty dial points bottom-left")
	_check(is_equal_approx(Dashboard.dial_angle(1.0), deg_to_rad(390.0)), "full dial points bottom-right")
	_check(Dashboard.dial_angle(2.0) == Dashboard.dial_angle(1.0), "needle stops at the end of the dial")
	var middle := Vector2.from_angle(Dashboard.dial_angle(0.5))
	_check(middle.y < -0.99, "half way points straight up")


func _check_shift_light() -> void:
	var dash := _dash()
	var car: Car = dash.car
	var d := car.drivetrain
	var redline: float = car.setup.redline_rpm
	d.gear = 2
	d.engine_spin = Drivetrain.rpm_to_spin(3000.0)
	_check(dash.shift_light() == 0, "shift light off at 3000 rpm")
	d.engine_spin = Drivetrain.rpm_to_spin(redline - 400.0)
	_check(dash.shift_light() == 1, "shift light on near the redline")
	d.engine_spin = Drivetrain.rpm_to_spin(redline - 100.0)
	_check(dash.shift_light() == 2, "shift light flashes at the redline")
	d.gear = d.top_gear()
	_check(dash.shift_light() == 0, "no shift light in top gear")
	d.gear = 0
	_check(dash.shift_light() == 0 and dash.gear_text() == "N", "neutral shows N, no shift light")
	d.gear = -1
	_check(dash.shift_light() == 0 and dash.gear_text() == "R", "reverse shows R, no shift light")
	d.gear = 3
	_check(dash.gear_text() == "3", "3rd gear shows 3")
	d.reset()


func _check_readout() -> void:
	var readout: CanvasLayer = _main.get_node("CarReadout")
	_check(not readout.visible, "old text readout is hidden at the start")
	var f3 := InputEventKey.new()
	f3.physical_keycode = KEY_F3
	f3.pressed = true
	_check(InputMap.event_is_action(f3, "toggle_readout", true), "F3 shows and hides the text readout")
	var clash := ""
	for action in InputMap.get_actions():
		if action != "toggle_readout" and not action.begins_with("ui_") and InputMap.event_is_action(f3, action, true):
			clash = action
	_check(clash == "", "no other action uses F3 %s" % clash)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
