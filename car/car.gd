class_name Car
extends RigidBody3D
## Semi-realistic car body. Knows nothing about tracks, game modes or who drives.
## A driver (the player now, AI later) sets throttle, brake, steer and handbrake.

const AIR_DENSITY := 1.225

@export var setup: CarSetup

## 0 to 1.
var throttle := 0.0
## 0 to 1. Held at a standstill, it reverses.
var brake := 0.0
## -1 full left to 1 full right.
var steer := 0.0
var handbrake := false

var wheels: Array[Wheel] = []

var _steer_now := 0.0
var _reset_pending := false


func _ready() -> void:
	wheels = [$WheelFL, $WheelFR, $WheelRL, $WheelRR]
	mass = setup.mass
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	var x := setup.track_width / 2.0
	var z := setup.wheelbase / 2.0
	var y := setup.mount_height
	$WheelFL.position = Vector3(-x, y, -z)
	$WheelFR.position = Vector3(x, y, -z)
	$WheelRL.position = Vector3(-x, y, z)
	$WheelRR.position = Vector3(x, y, z)


## Speed along the car's nose, in m/s. Negative when reversing.
func forward_speed() -> float:
	return linear_velocity.dot(-global_basis.z)


## Puts the car back on its wheels where it is, facing the same way.
func reset_upright() -> void:
	_reset_pending = true


func _physics_process(delta: float) -> void:
	var speed := forward_speed()

	var speed_factor := clampf(absf(speed) / 40.0, 0.0, 1.0)
	var lock := deg_to_rad(setup.max_steer_deg) * lerpf(1.0, setup.high_speed_steer, speed_factor)
	_steer_now = move_toward(_steer_now, steer, setup.steer_rate * delta)
	var angle := -_steer_now * lock
	$WheelFL.steer_angle = angle
	$WheelFR.steer_angle = angle

	var drive := throttle * setup.drive_force
	var brake_total := brake * setup.brake_force
	if brake > 0.1 and throttle < 0.05 and speed < 0.5:
		drive = -brake * setup.drive_force * setup.reverse_ratio
		brake_total = 0.0
	var front_brake := brake_total * setup.brake_bias_front / 2.0
	var rear_brake := brake_total * (1.0 - setup.brake_bias_front) / 2.0
	if handbrake:
		rear_brake += setup.handbrake_force / 2.0

	for wheel in wheels:
		if wheel.is_front:
			wheel.simulate(self, setup, 0.0, front_brake, delta)
		else:
			wheel.simulate(self, setup, drive / 2.0, rear_brake, delta)

	var v := linear_velocity
	var drag := 0.5 * AIR_DENSITY * setup.drag_coefficient * setup.frontal_area
	apply_central_force(-v * v.length() * drag)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _reset_pending:
		return
	_reset_pending = false
	var facing := -state.transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.001:
		facing = Vector3.FORWARD
	var upright := Basis.looking_at(facing.normalized(), Vector3.UP)
	state.transform = Transform3D(upright, state.transform.origin + Vector3.UP)
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	reset_physics_interpolation.call_deferred()
