extends SceneTree
## Headless check for traction control: full throttle in 1st, straight and in a turn,
## with the aid on and off. Touches no files.
## Run: godot --headless --path . -s tests/aids_check.gd

const HZ := 120

var _failed := false
var _runs := [
	{"name": "launch", "tc": false}, {"name": "launch", "tc": true},
	{"name": "turn", "tc": false}, {"name": "turn", "tc": true},
]
var _results := {}  # Run key to {spin, drift, kmh}.
var _run := -1
var _car: Car
var _tick := 0
var _max_spin := 0.0
var _max_drift := 0.0


func _initialize() -> void:
	root.add_child(load("res://track/test_flat.tscn").instantiate())
	_next_run()


func _physics_process(_delta: float) -> bool:
	_tick += 1
	var t := _tick / float(HZ)
	var run: Dictionary = _runs[_run]
	var kmh := _car.forward_speed() * 3.6
	if run.name == "launch":
		_car.throttle = 1.0 if t > 1.0 else 0.0
	else:
		# Roll up to 25 km/h in 1st, then full right stick and full throttle.
		if t < 4.0:
			_car.throttle = clampf((25.0 - kmh) * 0.2, 0.0, 1.0)
		else:
			_car.throttle = 1.0
			_car.steer = 1.0
	if t > 1.5:
		for wheel in [_car.wheels[2], _car.wheels[3]]:
			_max_spin = maxf(_max_spin, wheel.slip_ratio)
	if run.name == "turn" and t > 4.0:
		var v := _car.linear_velocity
		if v.length() > 1.0:
			var drift := rad_to_deg(absf(v.normalized().signed_angle_to(-_car.global_basis.z, Vector3.UP)))
			_max_drift = maxf(_max_drift, drift)
	var end := 3.0 if run.name == "launch" else 7.0
	if t >= end:
		_results[_key(run)] = {"spin": _max_spin, "drift": _max_drift, "kmh": kmh}
		print("%-6s TC %-3s  rear spin up to %5.1f %%  slide up to %5.1f deg  %5.1f km/h" % [
			run.name, "on" if run.tc else "off", _max_spin * 100.0, _max_drift, kmh])
		if _run + 1 < _runs.size():
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
	_max_spin = 0.0
	_max_drift = 0.0
	_car = load("res://car/car.tscn").instantiate()
	_car.setup = _car.setup.duplicate()  # Never change the shared roadster setup.
	_car.setup.traction_control = _runs[_run].tc
	_car.position = Vector3(0, 0.8, 0)
	root.add_child(_car)


func _verdict() -> void:
	var peak: float = _car.setup.peak_slip_ratio
	var launch_on: Dictionary = _results["launch on"]
	var launch_off: Dictionary = _results["launch off"]
	var turn_on: Dictionary = _results["turn on"]
	var turn_off: Dictionary = _results["turn off"]
	_check(launch_on.kmh >= launch_off.kmh - 1.0, "TC doesn't slow a straight launch")
	_check(turn_off.spin > 2.0 * peak, "without TC, the inside rear wheel spins up in the turn")
	_check(turn_on.spin < 2.0 * peak, "with TC, rear spin stays near the grip peak")
	_check(turn_on.drift < 15.0, "with TC, full throttle in a turn doesn't spin the car")
	_check(turn_on.drift < turn_off.drift, "TC slides less than no TC")
	print("AIDS CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)


static func _key(run: Dictionary) -> String:
	return "%s %s" % [run.name, "on" if run.tc else "off"]


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
