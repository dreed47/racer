extends SceneTree
## Headless check for the car model: wheels on all four corners, steering wheel and brake lights.
## Writes no files.
## Run: godot --headless --path . -s tests/look_check.gd

var _failed := false
var _car: Car
var _ticks := 0
var _rest := Basis.IDENTITY


func _initialize() -> void:
	_car = load("res://car/car.tscn").instantiate()
	root.add_child(_car)


func _process(_delta: float) -> bool:
	_ticks += 1
	var look := _car.get_node("Look") as CarLook
	var model := look.get_node("Model")
	var steering := model.find_child("steering_wheel", true, false) as Node3D
	var lights := model.find_child("brake_lights", true, false) as MeshInstance3D
	if _ticks == 1:
		_check(steering != null and lights != null, "model has steering_wheel and brake_lights")
		for wheel in _car.wheels:
			var spin := wheel.get_node("Visual/Spin")
			var meshes := spin.find_children("*", "MeshInstance3D", true, false)
			var calipers := wheel.get_node("Visual").get_child_count() - 1
			_check(meshes.size() == 1 and calipers == 1, "%s has a wheel that spins and a caliper" % wheel.name)
		_check(not model.find_child("wheel", true, false).visible, "the model's own wheel is hidden")
		_rest = steering.basis
		_car.set_physics_process(false)  # Keeps the car from setting its own steering.
		_car.brake = 0.0
		return false
	if _ticks == 2:
		var glow: StandardMaterial3D = lights.material_override
		_check(glow.emission_energy_multiplier == 0.0, "brake lights dark with no brake")
		_check(steering.basis.is_equal_approx(_rest), "steering wheel straight with no steering")
		_car.brake = 1.0
		_car.wheels[0].steer_angle = 0.3
		return false
	var glow: StandardMaterial3D = lights.material_override
	_check(glow.emission_energy_multiplier > 1.0, "brake lights glow when braking")
	# Positive steer_angle turns left, so the wheel turns anticlockwise as the driver sees it:
	# the top of the rim moves left (-X).
	var top := steering.basis * Vector3.UP
	_check(top.x < -0.5, "steering wheel turns left with the wheels (top moved %.2f)" % top.x)
	print("LOOK CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failed = true
