class_name PlayerDriver
extends Node
## Reads the controller and drives one car.
## An AI driver would set the same car fields.

@export var car: Car
## Higher values make small stick moves gentler.
@export var steer_curve := 1.5


func _physics_process(_delta: float) -> void:
	if car == null:
		return
	var stick := Input.get_axis("steer_left", "steer_right")
	car.steer = signf(stick) * pow(absf(stick), steer_curve)
	car.throttle = Input.get_action_strength("throttle")
	car.brake = Input.get_action_strength("brake")
	car.handbrake = Input.is_action_pressed("handbrake")
	if Input.is_action_just_pressed("reset_car"):
		car.reset_upright()
