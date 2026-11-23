class_name Wheel
extends Node3D
## One corner of the car: raycast suspension plus a tire with a grip curve.
## Each physics tick the car calls update_suspension(), then tire_force()
## and spin_with() once per substep, then apply_tire().

## Below this ground speed, slip uses this speed instead, so it stays finite at a standstill.
const MIN_SLIP_SPEED := 3.0

@export var is_front := false

## Spring compression in metres. 0 means fully extended.
var compression := 0.0
## Suspension force pushing the car up, in N.
var wheel_load := 0.0
var on_ground := false
## Steering angle in radians. Positive turns left.
var steer_angle := 0.0
## Wheel spin in rad/s. Positive rolls forward.
var spin := 0.0
## Latest slip, for readouts. Ratio: 0.1 means spinning 10 % faster than the ground.
var slip_ratio := 0.0
var slip_angle := 0.0
## Slip compared with the grip peak: below 1 gripping, 1 at the limit, above 1 sliding.
var slip_level := 0.0

var _contact := Vector3.ZERO
var _forward := Vector3.ZERO
var _right := Vector3.ZERO
var _long_speed := 0.0
var _lat_speed := 0.0
var _force_sum := Vector2.ZERO
var _angle := 0.0

@onready var _visual: Node3D = $Visual


## Casts the ray, applies the spring and damper, and reads the ground speed at the contact.
func update_suspension(car: RigidBody3D, setup: CarSetup) -> void:
	rotation.y = steer_angle
	_force_sum = Vector2.ZERO
	var up := car.global_basis.y
	var mount := global_position
	var reach := setup.suspension_length + setup.wheel_radius
	var query := PhysicsRayQueryParameters3D.create(mount, mount - up * reach)
	query.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(query)

	on_ground = not hit.is_empty()
	if not on_ground:
		compression = 0.0
		wheel_load = 0.0
		_visual.position.y = -setup.suspension_length
		return

	_contact = hit.position
	var normal: Vector3 = hit.normal
	var hit_distance := mount.distance_to(_contact)
	compression = reach - hit_distance
	_visual.position.y = -(hit_distance - setup.wheel_radius)

	var extend_speed := _point_velocity(car, mount).dot(up)  # Negative while compressing.
	var damping := setup.damper_bump if extend_speed < 0.0 else setup.damper_rebound
	var spring_rate := setup.spring_rate_front if is_front else setup.spring_rate_rear
	wheel_load = maxf(0.0, spring_rate * compression - damping * extend_speed)
	car.apply_force(up * wheel_load, mount - car.global_position)

	_forward = (-global_basis.z).slide(normal).normalized()
	_right = global_basis.x.slide(normal).normalized()
	var v := _point_velocity(car, _contact)
	_long_speed = v.dot(_forward)
	_lat_speed = v.dot(_right)


## Adds extra suspension force, such as an anti-roll bar's. Load never goes below 0.
func add_load(car: RigidBody3D, force: float) -> void:
	if not on_ground:
		return
	var applied := maxf(-wheel_load, force)
	wheel_load += applied
	car.apply_force(car.global_basis.y * applied, global_position - car.global_position)


## Tire force from the current spin: x along the wheel, y to its right, in N.
## Adds it to the tick's average. Returns zero in the air.
func tire_force(setup: CarSetup) -> Vector2:
	if not on_ground or wheel_load <= 0.0:
		slip_level = 0.0
		return Vector2.ZERO
	var v_ref := maxf(absf(_long_speed), MIN_SLIP_SPEED)
	slip_ratio = (spin * setup.wheel_radius - _long_speed) / v_ref
	slip_angle = atan2(_lat_speed, v_ref)
	var sx := slip_ratio / setup.peak_slip_ratio
	var sy := slip_angle / deg_to_rad(setup.peak_slip_angle_deg)
	var s := sqrt(sx * sx + sy * sy)
	slip_level = s
	if s < 1e-6:
		return Vector2.ZERO
	var load_factor := clampf(1.0 - setup.load_sensitivity * (wheel_load / setup.nominal_load - 1.0), 0.5, 1.5)
	var c := setup.tire_shape
	var b := tan(PI / (2.0 * c))  # Puts the peak at s = 1.
	var f := setup.grip * load_factor * wheel_load * sin(c * atan(b * s))
	var force := Vector2(f * sx / s, -f * sy / s)
	_force_sum += force
	return force


## Moves spin on by one substep. other_torque drives the wheel; brake_torque only slows it,
## and holds it still when it is strong enough.
func spin_with(other_torque: float, brake_torque: float, inertia: float, h: float) -> void:
	spin = brake_spin(spin + other_torque * h / inertia, brake_torque * h / inertia)


static func brake_spin(free_spin: float, brake_step: float) -> float:
	if absf(free_spin) <= brake_step:
		return 0.0
	return free_spin - signf(free_spin) * brake_step


## Applies the tick's average tire force plus rolling resistance, and turns the visual.
func apply_tire(car: RigidBody3D, setup: CarSetup, substeps: int, delta: float) -> void:
	_angle = wrapf(_angle + spin * delta, 0.0, TAU)
	_visual.rotation.x = -_angle
	if not on_ground:
		return
	var tire := _force_sum / substeps
	tire.x -= clampf(_long_speed, -1.0, 1.0) * setup.rolling_resistance * wheel_load
	car.apply_force(_forward * tire.x + _right * tire.y, _contact - car.global_position)


func _point_velocity(car: RigidBody3D, point: Vector3) -> Vector3:
	return car.linear_velocity + car.angular_velocity.cross(point - car.global_position)
