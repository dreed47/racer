extends SceneTree
## Headless physics check for the car. Prints numbers; touches no files.
## Run: godot --headless --path . -s tests/sim_check.gd

const HZ := 120

var _car
var _tick := 0


func _initialize() -> void:
	root.add_child(load("res://track/test_flat.tscn").instantiate())
	_car = load("res://car/car.tscn").instantiate()
	root.add_child(_car)
	_car.position = Vector3(0, 0.8, 0)


func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _car.brake > 0.0 and _stop_time < 0.0 and _car.forward_speed() < 0.3:
		_stop_time = (_tick - 7 * HZ) / float(HZ)
	match _tick:
		2 * HZ:
			_report("Settled 2 s (expect front ~61 mm, rear ~70 mm)")
			_ramp_check()
			_car.throttle = 1.0
		7 * HZ:
			_report("After 5 s full throttle (expect ~65-70 km/h)")
			_car.throttle = 0.0
			_car.brake = 1.0
		11 * HZ:
			_report("After 4 s full brake (stops, then creeps back in reverse)")
			print("  stopped after %.2f s" % _stop_time)
			_car.brake = 0.0
			_car.throttle = 0.5
			_car.steer = 1.0
		16 * HZ:
			_report("After 5 s half throttle, full right lock")
			quit()
	return false


var _stop_time := -1.0


func _process(_delta: float) -> bool:
	return false


func _report(title: String) -> void:
	print("\n", title)
	print("  speed %.1f km/h  pos (%.1f, %.2f, %.1f)  heading %.0f deg" % [
		_car.forward_speed() * 3.6, _car.global_position.x, _car.global_position.y,
		_car.global_position.z, rad_to_deg(_car.global_rotation.y)])
	for w in _car.wheels:
		print("  %s  load %6.0f N  spring %5.1f mm  ground %s" % [
			w.name, w.wheel_load, w.compression * 1000.0, w.on_ground])


func _ramp_check() -> void:
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(30, 5, -66.5), Vector3(30, -5, -66.5))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		print("  ramp check: ray hit nothing")
		return
	print("  ray at far end of ramp hit %s at %.2f m (expect Ramp, ~1.8)" % [hit.collider.name, hit.position.y])
