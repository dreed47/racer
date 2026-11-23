class_name Car
extends RigidBody3D
## Semi-realistic car body. Knows nothing about tracks, game modes or who drives.
## A driver (the player now, AI later) sets throttle, brake, steer and handbrake.

const AIR_DENSITY := 1.225
## Tire and wheel-spin steps per physics tick. Tires are stiff, so they need small steps.
const SUBSTEPS := 20
## How fast traction control cuts power per unit of extra slip, and gives it back, per second.
const TC_CUT_RATE := 40.0
const TC_RECOVER_RATE := 4.0
## Anti-spin starts helping once the slide angle, looking a little ahead, passes this many
## degrees: the first number at the lightest setting, the second at the strongest.
const SPIN_START_LIGHT := 8.0
const SPIN_START_STRONG := 4.0
## How far ahead anti-spin looks at the slide angle, in seconds.
const SPIN_LOOK := 0.15
## Brake torque on the outer front wheel per degree past the start, in N m, and the most it uses.
const SPIN_BRAKE_PER_DEG := 250.0
const SPIN_BRAKE_MAX := 1500.0
## Extra wheel angle into the slide, per degree past the start, at full strength.
const SPIN_STEER_GAIN := 0.8
## ABS lets a wheel's brake off when it turns this much slower than the road, as a share of the
## tire's peak slip ratio, then gives it back at ABS_RECOVER_RATE per second.
const ABS_SLIP := 1.3
const ABS_RECOVER_RATE := 6.0

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
## Share of the throttle traction control is taking away right now, 0 to 1. For readouts.
var traction_cut := 0.0

## Driver aids that come from the learning level (see LearningLevel), not the car's setup.
## Anti-spin: 0 off to 1 strongest. Catches the back of the car when it starts to swing out:
## cuts power, brakes the outer front wheel and steers the front wheels into the slide.
var anti_spin := 0.0
## Anti-lock brakes: eases a wheel's brake while it locks, so you can still steer.
var abs_brakes := false
## Traction control works only while this and setup.traction_control are both on.
var traction_allowed := true
## True while anti-spin or ABS is working. For readouts.
var anti_spin_active := false
var abs_active := false

var wheels: Array[Wheel] = []
var drivetrain: Drivetrain

var _steer_now := 0.0
var _last_slide := 0.0
var _abs_share: Array[float] = [1.0, 1.0, 1.0, 1.0]
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


## Moves the car to a place, stopped, in 1st gear. Takes effect on the next physics step.
func place_at(where: Transform3D) -> void:
	_place_target = where
	_place_pending = true


func _physics_process(delta: float) -> void:
	var speed := forward_speed()

	var lock := steer_lock(absf(speed))
	_steer_now = move_toward(_steer_now, steer, setup.steer_rate * delta)
	var spin_help := _anti_spin(speed, delta)  # Degrees past the start; + means sliding right.
	var full_lock := deg_to_rad(setup.max_steer_deg)
	var angle := clampf(-_steer_now * lock - deg_to_rad(spin_help) * SPIN_STEER_GAIN * anti_spin,
			-full_lock, full_lock)
	$WheelFL.steer_angle = angle
	$WheelFR.steer_angle = angle

	var front_brake := brake * setup.brake_torque * setup.brake_bias_front / 2.0
	var rear_brake := brake * setup.brake_torque * (1.0 - setup.brake_bias_front) / 2.0
	var brakes: Array[float] = [front_brake, front_brake, rear_brake, rear_brake]
	_anti_lock(brakes, speed, delta)
	# Brake the outer front wheel to turn the car back the other way.
	if spin_help != 0.0:
		var outer := 1 if spin_help > 0.0 else 0
		brakes[outer] += minf(SPIN_BRAKE_MAX, absf(spin_help) * SPIN_BRAKE_PER_DEG) * anti_spin
	if handbrake:
		brakes[2] += setup.handbrake_torque / 2.0
		brakes[3] += setup.handbrake_torque / 2.0

	for wheel in wheels:
		wheel.update_suspension(self, setup)
	_anti_roll($WheelFL, $WheelFR, setup.anti_roll_front)
	_anti_roll($WheelRL, $WheelRR, setup.anti_roll_rear)

	var fl: Wheel = $WheelFL
	var fr: Wheel = $WheelFR
	var rl: Wheel = $WheelRL
	var rr: Wheel = $WheelRR
	var drive := _traction_control(throttle, delta)
	if spin_help != 0.0:
		drive *= clampf(1.0 - absf(spin_help) / 3.0 * anti_spin, 0.0, 1.0)
	var r := setup.wheel_radius
	var h := delta / SUBSTEPS
	for i in SUBSTEPS:
		fl.spin_with(-fl.tire_force(setup).x * r, brakes[0], setup.wheel_inertia, h)
		fr.spin_with(-fr.tire_force(setup).x * r, brakes[1], setup.wheel_inertia, h)
		var left_torque := -rl.tire_force(setup).x * r
		var right_torque := -rr.tire_force(setup).x * r
		drivetrain.step(h, drive, rl, rr, left_torque, right_torque, brakes[2], brakes[3])

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
func steer_lock(speed: float) -> float:
	var full := deg_to_rad(setup.max_steer_deg)
	var v := maxf(speed, 1.0)
	var turn := atan(setup.wheelbase * setup.grip * 9.81 / (v * v))
	var slide := deg_to_rad(setup.peak_slip_angle_deg) * setup.steer_assist_slip
	return lerpf(full, minf(full, turn + slide), setup.steer_assist)


## Slide angle: between where the car points and where it goes, flat, in degrees.
## Positive when the car moves to the right of its nose. 0 when slow or reversing.
func slide_angle() -> float:
	var local := global_basis.inverse() * linear_velocity
	if -local.z < 3.0:
		return 0.0
	return rad_to_deg(atan2(local.x, -local.z))


## How far the slide, looking SPIN_LOOK seconds ahead, is past where anti-spin starts, in
## degrees, with the slide's sign. 0 while anti-spin is off or not needed.
func _anti_spin(speed: float, delta: float) -> float:
	var slide := slide_angle()
	var rate := (slide - _last_slide) / delta
	_last_slide = slide
	anti_spin_active = false
	if anti_spin <= 0.0 or speed < 5.0:
		return 0.0
	var ahead := slide + clampf(rate, -60.0, 60.0) * SPIN_LOOK
	# Only while the slide is there and still growing, so it never pushes the other way.
	if signf(ahead) != signf(slide):
		return 0.0
	var start := lerpf(SPIN_START_LIGHT, SPIN_START_STRONG, anti_spin)
	var past := absf(ahead) - start
	if past <= 0.0:
		return 0.0
	anti_spin_active = true
	return signf(ahead) * past


## ABS: trims each wheel's foot-brake torque while that wheel locks. Changes brakes in place.
func _anti_lock(brakes: Array[float], speed: float, delta: float) -> void:
	abs_active = false
	for i in 4:
		var wheel := wheels[i]
		var locking := wheel.on_ground and brakes[i] > 0.0 and absf(speed) > 2.0 \
				and -wheel.slip_ratio * signf(speed) > setup.peak_slip_ratio * ABS_SLIP
		if not abs_brakes:
			_abs_share[i] = 1.0
		elif locking:
			_abs_share[i] = maxf(0.2, _abs_share[i] * 0.6)
		else:
			_abs_share[i] = minf(1.0, _abs_share[i] + ABS_RECOVER_RATE * delta)
		if _abs_share[i] < 0.95 and brakes[i] > 0.0:
			abs_active = true
		brakes[i] *= _abs_share[i]


## Throttle the engine gets after traction control. Watches the rear wheels' spin against
## the road from the last tick and trims power while either spins past the target.
func _traction_control(wanted: float, delta: float) -> float:
	var g := drivetrain.ratio()
	if not (setup.traction_control and traction_allowed) or g == 0.0:
		traction_cut = 0.0
		return wanted
	var spin := 0.0
	for wheel: Wheel in [$WheelRL, $WheelRR]:
		if wheel.on_ground:
			spin = maxf(spin, wheel.slip_ratio * signf(g))
	var target := setup.peak_slip_ratio * setup.traction_slip
	if spin > target:
		traction_cut = minf(1.0, traction_cut + (spin - target) / target * TC_CUT_RATE * delta)
	else:
		traction_cut = maxf(0.0, traction_cut - TC_RECOVER_RATE * delta)
	return wanted * (1.0 - traction_cut)


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
	drivetrain.reset()
	reset_physics_interpolation.call_deferred()
	placed.emit.call_deferred()
