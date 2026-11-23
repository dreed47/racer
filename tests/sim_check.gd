extends SceneTree
## Headless physics check for the car. Prints numbers; touches no files.
## Run: godot --headless --path . -s tests/sim_check.gd

const HZ := 120

var _car
var _tick := 0
var _phase := ""
var _phase_start := 0
var _marks := {}
var _corner_steer := 1.0


func _initialize() -> void:
	root.add_child(load("res://track/test_flat.tscn").instantiate())
	_car = load("res://car/car.tscn").instantiate()
	_car.position = Vector3(0, 0.8, 0)
	root.add_child(_car)


func _physics_process(_delta: float) -> bool:
	_tick += 1
	var t := (_tick - _phase_start) / float(HZ)
	var kmh: float = _car.forward_speed() * 3.6
	var dt = _car.drivetrain

	if _phase == "launch":
		# Test driver: shift up near the redline.
		if dt.rpm() > 6800.0 and dt.gear < dt.top_gear():
			_car.shift(1)
		for target in [50, 100]:
			if kmh >= target and not _marks.has(target):
				_marks[target] = t
	if _phase == "corner":
		# Test driver: hold 60 km/h, go straight for 6 s, then steer right.
		_car.throttle = clampf((60.0 - kmh) * 0.2, 0.0, 1.0)
		_car.steer = _corner_steer if t > 6.0 else 0.0
		if dt.gear == 1 and dt.rpm() > 5000.0:
			_car.shift(1)
	if _phase == "brake" and kmh < 0.5 and not _marks.has("stop"):
		_marks["stop"] = t

	match _tick:
		3 * HZ:
			_report("Idle 3 s in 1st (expect 0 km/h, about 900 rpm, clutch slip)")
			_start("launch")
			_car.throttle = 1.0
		13 * HZ:
			_report("After 10 s full throttle, shifting at 6800 rpm")
			print("  0-50 km/h %.1f s, 0-100 km/h %.1f s (a real NA Miata: about 3.5 and 8.5)" % [
				_marks.get(50, -1.0), _marks.get(100, -1.0)])
			_start("brake")
			_car.throttle = 0.0
			_car.brake = 1.0
		18 * HZ:
			_report("After 5 s full brake (expect stopped)")
			print("  stopped after %.2f s" % _marks.get("stop", -1.0))
			_car.brake = 0.0
			while dt.gear > 1:
				_car.shift(-1)
			_start("corner")
		30 * HZ:
			_report("Holding 60 km/h, full right stick for 6 s (expect about 0.85 g, front level near 1)")
			var lat_g: float = _car.linear_velocity.length() * _car.angular_velocity.length() / 9.81
			print("  sideways %.2f g" % lat_g)
			_start("reverse")
			_car.throttle = 0.0
			_car.steer = 0.0
			_car.brake = 1.0
			while dt.gear > -1:
				_car.shift(-1)
		33 * HZ:
			_car.brake = 0.0
			_car.throttle = 0.4
		36 * HZ:
			_report("3 s at 40 % throttle in reverse (expect negative speed)")
			quit()
	return false


func _start(phase: String) -> void:
	_phase = phase
	_phase_start = _tick


func _report(title: String) -> void:
	var dt = _car.drivetrain
	print("\n", title)
	print("  speed %.1f km/h  gear %d  %.0f rpm  clutch %s  heading %.0f deg" % [
		_car.forward_speed() * 3.6, dt.gear, dt.rpm(),
		"locked" if dt.clutch_locked else "slip", rad_to_deg(_car.global_rotation.y)])
	for w in _car.wheels:
		print("  %s  load %5.0f N  spring %5.1f mm  slip %+6.1f %%  angle %+5.1f deg  level %.2f" % [
			w.name, w.wheel_load, w.compression * 1000.0, w.slip_ratio * 100.0,
			rad_to_deg(w.slip_angle), w.slip_level])
