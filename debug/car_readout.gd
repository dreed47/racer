extends CanvasLayer
## On-screen numbers for tuning: driver inputs, engine, and each wheel's suspension and tire.

@export var car: Car

@onready var _label: Label = $Label


func _process(_delta: float) -> void:
	if car == null or car.wheels.is_empty():
		return
	var w := car.wheels
	var d := car.drivetrain
	var gear := "R" if d.gear < 0 else ("N" if d.gear == 0 else str(d.gear))
	_label.text = "\n".join(PackedStringArray([
		"Speed    %6.1f km/h" % (car.forward_speed() * 3.6),
		"Gear     %6s" % gear,
		"RPM      %6.0f" % d.rpm(),
		"Clutch   %6s" % ("locked" if d.clutch_locked else "slip"),
		"Throttle %6.2f" % car.throttle,
		"Brake    %6.2f" % car.brake,
		"Steer    %+6.2f" % car.steer,
		"Handbrake  %s" % ("on" if car.handbrake else "off"),
		"G        %+5.2f side  %+5.2f fwd" % [car.g_force.x, car.g_force.y],
		"",
		"Wheel     Load N  Spring mm  Slip %  Angle  Grip",
		_row("Front L", w[0]),
		_row("Front R", w[1]),
		_row("Rear L", w[2]),
		_row("Rear R", w[3]),
	]))


func _row(label: String, wheel: Wheel) -> String:
	if not wheel.on_ground:
		return "%-8s     air" % label
	return "%-8s  %6.0f  %6.0f   %+6.1f  %+5.1f  %4.2f" % [
		label, wheel.wheel_load, wheel.compression * 1000.0, wheel.slip_ratio * 100.0,
		rad_to_deg(wheel.slip_angle), wheel.slip_level]
