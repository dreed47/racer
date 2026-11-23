class_name Drivetrain
extends RefCounted
## Engine, automatic clutch, gearbox and open differential for the two rear wheels.
## The car calls step() once per substep.

## Gear number: -1 reverse, 0 neutral, 1 and up forward.
var gear := 1
var engine_spin := 0.0
## True while the clutch is fully gripping, so engine and wheels turn together.
var clutch_locked := false

var _setup: CarSetup
var _shift_timer := 0.0


func _init(setup: CarSetup) -> void:
	_setup = setup
	engine_spin = rpm_to_spin(setup.idle_rpm)


static func rpm_to_spin(rpm: float) -> float:
	return rpm * TAU / 60.0


func rpm() -> float:
	return engine_spin * 60.0 / TAU


func top_gear() -> int:
	return _setup.gear_ratios.size()


func shift(direction: int) -> void:
	var target := clampi(gear + direction, -1, top_gear())
	if target == gear:
		return
	gear = target
	clutch_locked = false
	_shift_timer = _setup.shift_time


## Engine turns per wheel turn in the current gear. Negative in reverse, 0 in neutral.
func ratio() -> float:
	if gear > 0:
		return _setup.gear_ratios[gear - 1] * _setup.final_drive
	if gear < 0:
		return -_setup.reverse_ratio * _setup.final_drive
	return 0.0


## Engine torque at the crank, in N m, before the clutch.
func engine_torque(throttle: float) -> float:
	var r := rpm()
	if _shift_timer > 0.0:
		throttle = 0.0
	# Idle governor: opens the throttle a little as the engine drops below idle.
	throttle = maxf(throttle, clampf((_setup.idle_rpm - r) / 200.0, 0.0, 1.0))
	var curve := _setup.torque_curve
	var x := clampf(r / 1000.0, 0.0, curve.size() - 1.001)
	var i := int(x)
	var full := lerpf(curve[i], curve[i + 1], x - i)
	var drive := 0.0 if r > _setup.redline_rpm else throttle * full
	var friction := (_setup.engine_friction + _setup.engine_friction_per_krpm * r / 1000.0) * (1.0 - throttle)
	return drive - friction


## Most torque the clutch can carry right now, in N m.
func clutch_capacity() -> float:
	if gear == 0 or _shift_timer > 0.0:
		return 0.0
	var bite := inverse_lerp(_setup.clutch_bite_rpm, _setup.clutch_full_rpm, rpm())
	return _setup.clutch_max_torque * clampf(bite, 0.0, 1.0)


## Moves engine and rear wheels on by h seconds.
## left_torque and right_torque are the tire torques on each wheel; brakes are per wheel.
func step(h: float, throttle: float, left: Wheel, right: Wheel,
		left_torque: float, right_torque: float, left_brake: float, right_brake: float) -> void:
	_shift_timer = maxf(0.0, _shift_timer - h)
	var g := ratio()
	var t_engine := engine_torque(throttle)
	var cap := clutch_capacity()
	var i_wheel := _setup.wheel_inertia
	var i_engine := _setup.engine_inertia
	if cap <= 0.0:
		clutch_locked = false

	if clutch_locked:
		# Engine and the wheels' average spin move as one body through the gears.
		var avg := (left.spin + right.spin) / 2.0
		var diff := (left.spin - right.spin) / 2.0
		var inertia := 2.0 * i_wheel + i_engine * g * g
		var free_avg := avg + (t_engine * g + left_torque + right_torque) * h / inertia
		var new_avg := Wheel.brake_spin(free_avg, (left_brake + right_brake) * h / inertia)
		var new_diff := diff + (left_torque - right_torque) * h / (2.0 * i_wheel)
		left.spin = new_avg + new_diff
		right.spin = new_avg - new_diff
		engine_spin = new_avg * g
		# Torque the clutch had to carry to keep them together. Too much, and it slips.
		var clutch_torque := t_engine - i_engine * (new_avg - avg) * g / h
		if absf(clutch_torque) > cap:
			clutch_locked = false
		return

	var slip := engine_spin - (left.spin + right.spin) / 2.0 * g
	var t_clutch := cap * signf(slip)
	engine_spin = maxf(0.0, engine_spin + (t_engine - t_clutch) * h / i_engine)
	left.spin_with(left_torque + t_clutch * g / 2.0, left_brake, i_wheel, h)
	right.spin_with(right_torque + t_clutch * g / 2.0, right_brake, i_wheel, h)
	var new_slip := engine_spin - (left.spin + right.spin) / 2.0 * g
	if cap > 0.0 and (signf(new_slip) != signf(slip) or absf(new_slip) < 1.0):
		clutch_locked = true
