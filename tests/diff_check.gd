extends SceneTree
## Headless check for the limited-slip diff: full throttle in a tight 1st-gear turn with the
## diff open, at the default lock and fully locked, traction control off.
## The inside rear wheel should spin up when open, much less at the default lock, and the car
## should still turn. Touches no files.
## Run: godot --headless --path . -s tests/diff_check.gd

const HZ := 120

var _failed := false
var _locks := [0.0, 0.25, 1.0]
var _results := {}  # Lock to {gap, turned, kmh}.
var _run := -1
var _car: Car
var _tick := 0
var _max_gap := 0.0
var _start_yaw := 0.0
var _turned := 0.0
var _last_yaw := 0.0


func _initialize() -> void:
	root.add_child(load("res://track/test_flat.tscn").instantiate())
	_next_run()


func _physics_process(_delta: float) -> bool:
	_tick += 1
	var t := _tick / float(HZ)
	var kmh := _car.forward_speed() * 3.6
	# Roll up to 25 km/h in 1st, then full right stick and full throttle.
	if t < 4.0:
		_car.throttle = clampf((25.0 - kmh) * 0.2, 0.0, 1.0)
		_last_yaw = _car.global_rotation.y
	else:
		_car.throttle = 1.0
		_car.steer = 1.0
		var left: Wheel = _car.wheels[2]
		var right: Wheel = _car.wheels[3]
		var avg := (absf(left.spin) + absf(right.spin)) / 2.0
		if avg > 1.0:
			_max_gap = maxf(_max_gap, absf(left.spin - right.spin) / avg)
		var yaw := _car.global_rotation.y
		_turned += absf(wrapf(yaw - _last_yaw, -PI, PI))
		_last_yaw = yaw
	if t >= 7.0:
		var lock: float = _locks[_run]
		_results[lock] = {"gap": _max_gap, "turned": rad_to_deg(_turned), "kmh": kmh}
		print("lock %3d %%  rear wheel speed gap up to %5.1f %%  turned %5.0f deg  %5.1f km/h" % [
			lock * 100.0, _max_gap * 100.0, rad_to_deg(_turned), kmh])
		if _run + 1 < _locks.size():
			_next_run()
		else:
			_verdict()
			return true
	return false


func _next_run() -> void:
	if _car:
		root.remove_child(_car)
		_car.free()
	_run += 1
	_tick = 0
	_max_gap = 0.0
	_turned = 0.0
	_car = load("res://car/car.tscn").instantiate()
	_car.setup = _car.setup.duplicate()  # Never change the shared roadster setup.
	_car.setup.traction_control = false
	_car.setup.diff_lock = _locks[_run]
	_car.position = Vector3(0, 0.8, 0)
	root.add_child(_car)


func _verdict() -> void:
	var open: Dictionary = _results[0.0]
	var medium: Dictionary = _results[0.25]
	var locked: Dictionary = _results[1.0]
	var fresh := CarSetup.new()
	_check(is_equal_approx(fresh.diff_lock, 0.25), "default lock is 0.25")
	_check(open.gap > 0.5, "open diff lets the inside wheel spin up (%.0f %%)" % (open.gap * 100.0))
	_check(medium.gap < open.gap * 0.5, "default lock at least halves the spin-up (%.0f %%)" % (medium.gap * 100.0))
	_check(locked.gap <= medium.gap, "full lock keeps the wheels closest (%.0f %%)" % (locked.gap * 100.0))
	_check(medium.turned > 60.0, "car still turns at the default lock (%.0f deg)" % medium.turned)
	print("DIFF CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
