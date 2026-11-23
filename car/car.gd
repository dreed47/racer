class_name Car
extends RigidBody3D
## Semi-realistic car body. Knows nothing about tracks, game modes or who drives.
## A driver (the player now, AI later) sets throttle, brake, steer and handbrake.

const AIR_DENSITY := 1.225
## Tire and wheel-spin steps per physics tick. Tires are stiff, so they need small steps.
const SUBSTEPS := 20

@export var setup: CarSetup

## 0 to 1.
var throttle := 0.0
## 0 to 1.
var brake := 0.0
## -1 full left to 1 full right.
var steer := 0.0
var handbrake := false

## Measured acceleration in g: x to the right, y forward. For readouts.
var g_force := Vector2.ZERO

var wheels: Array[Wheel] = []
var drivetrain: Drivetrain

var _steer_now := 0.0
var _last_velocity := Vector3.ZERO
var _place_pending := false
var _place_target := Transform3D.IDENTITY

## Sent after place_at() has moved the car.
signal placed


func _ready() -> void:
	wheels = [$WheelFL, $WheelFR, $WheelRL, $WheelRR]
	drivetrain = Drivetrain.new(setup)
	apply_setup()


## Re-reads setup values that are only used when the car is built: mass and wheel positions.
## Call after changing those. Everything else is read every tick.
func apply_setup() -> void:
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


## Gear change: 1 up, -1 down. Order is R, N, 1, 2 ...
func shift(direction: int) -> void:
	drivetrain.shift(direction)


## Moves the car to a place, stopped. Takes effect on the next physics step.
func place_at(where: Transform3D) -> void:
	_place_target = where
	_place_pending = true


func _physics_process(delta: float) -> void:
	var speed := forward_speed()

	var lock := _steer_lock(absf(speed))
	_steer_now = move_toward(_steer_now, steer, setup.steer_rate * delta)
	var angle := -_steer_now * lock
	$WheelFL.steer_angle = angle
	$WheelFR.steer_angle = angle

	var front_brake := brake * setup.brake_torque * setup.brake_bias_front / 2.0
	var rear_brake := brake * setup.brake_torque * (1.0 - setup.brake_bias_front) / 2.0
	if handbrake:
		rear_brake += setup.handbrake_torque / 2.0

	for wheel in wheels:
		wheel.update_suspension(self, setup)
	_anti_roll($WheelFL, $WheelFR, setup.anti_roll_front)
	_anti_roll($WheelRL, $WheelRR, setup.anti_roll_rear)

	var fl: Wheel = $WheelFL
	var fr: Wheel = $WheelFR
	var rl: Wheel = $WheelRL
	var rr: Wheel = $WheelRR
	var r := setup.wheel_radius
	var h := delta / SUBSTEPS
	for i in SUBSTEPS:
		fl.spin_with(-fl.tire_force(setup).x * r, front_brake, setup.wheel_inertia, h)
		fr.spin_with(-fr.tire_force(setup).x * r, front_brake, setup.wheel_inertia, h)
		var left_torque := -rl.tire_force(setup).x * r
		var right_torque := -rr.tire_force(setup).x * r
		drivetrain.step(h, throttle, rl, rr, left_torque, right_torque, rear_brake, rear_brake)

	for wheel in wheels:
		wheel.apply_tire(self, setup, SUBSTEPS, delta)

	var v := linear_velocity
	var drag := 0.5 * AIR_DENSITY * setup.drag_coefficient * setup.frontal_area
	apply_central_force(-v * v.length() * drag)

	var accel := (v - _last_velocity) / delta
	_last_velocity = v
	g_force = Vector2(accel.dot(global_basis.x), accel.dot(-global_basis.z)) / 9.81


## Wheel angle at full stick. With the assist on, full stick at speed gives about
## the angle of the tightest turn the tires can hold, so more stick never just scrubs.
func _steer_lock(speed: float) -> float:
	var full := deg_to_rad(setup.max_steer_deg)
	var v := maxf(speed, 1.0)
	var turn := atan(setup.wheelbase * setup.grip * 9.81 / (v * v))
	var slide := deg_to_rad(setup.peak_slip_angle_deg) * setup.steer_assist_slip
	return lerpf(full, minf(full, turn + slide), setup.steer_assist)


func _anti_roll(left: Wheel, right: Wheel, stiffness: float) -> void:
	var force := stiffness * (left.compression - right.compression)
	left.add_load(self, force)
	right.add_load(self, -force)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _place_pending:
		return
	_place_pending = false
	state.transform = _place_target
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	for wheel in wheels:
		wheel.spin = 0.0
	reset_physics_interpolation.call_deferred()
	placed.emit.call_deferred()
