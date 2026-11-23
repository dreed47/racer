extends CanvasLayer
## Shows live controller values so you can check the input map.
## Remove from main.tscn once the car drives.

@onready var _label: Label = $Label


func _process(_delta: float) -> void:
	var pads := Input.get_connected_joypads()
	var pad_name := "none"
	if not pads.is_empty():
		pad_name = Input.get_joy_name(pads[0])

	var lines := PackedStringArray([
		"Controller: %s" % pad_name,
		"Steer:     %+.2f" % Input.get_axis("steer_left", "steer_right"),
		"Throttle:  %.2f" % Input.get_action_strength("throttle"),
		"Brake:     %.2f" % Input.get_action_strength("brake"),
		"Handbrake: %s" % Input.is_action_pressed("handbrake"),
		"Shift up:  %s" % Input.is_action_pressed("shift_up"),
		"Shift down:%s" % Input.is_action_pressed("shift_down"),
		"Reset car: %s" % Input.is_action_pressed("reset_car"),
		"Pause:     %s" % Input.is_action_pressed("pause"),
	])
	_label.text = "\n".join(lines)
