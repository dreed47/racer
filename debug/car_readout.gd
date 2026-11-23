extends CanvasLayer
## On-screen numbers for tuning: driver inputs and each wheel's suspension.

@export var car: Car

@onready var _label: Label = $Label


func _process(_delta: float) -> void:
	if car == null or car.wheels.is_empty():
		return
	var w := car.wheels
	_label.text = "\n".join(PackedStringArray([
		"Speed    %6.1f km/h" % (car.forward_speed() * 3.6),
		"Throttle %6.2f" % car.throttle,
		"Brake    %6.2f" % car.brake,
		"Steer    %+6.2f" % car.steer,
		"Handbrake  %s" % ("on" if car.handbrake else "off"),
		"",
		"Wheel     Load N  Spring mm",
		_row("Front L", w[0]),
		_row("Front R", w[1]),
		_row("Rear L", w[2]),
		_row("Rear R", w[3]),
	]))


func _row(label: String, wheel: Wheel) -> String:
	if not wheel.on_ground:
		return "%-8s     air" % label
	return "%-8s  %6.0f  %6.0f" % [label, wheel.wheel_load, wheel.compression * 1000.0]
