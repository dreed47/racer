class_name Wheel
extends Node3D
## One corner of the car: raycast suspension plus a placeholder tire.
## The car calls simulate() every physics tick.

## Brake force per m/s of wheel speed, before the brake limit kicks in.
## Keeps the brakes from jittering at a standstill.
const BRAKE_GAIN := 4000.0

@export var is_front := false

## Spring compression in metres. 0 means fully extended.
var compression := 0.0
## Suspension force pushing the car up, in N.
var wheel_load := 0.0
var on_ground := false
## Steering angle in radians. Positive turns left.
var steer_angle := 0.0

var _spin := 0.0

@onready var _visual: Node3D = $Visual


func simulate(car: RigidBody3D, setup: CarSetup, drive_n: float, brake_n: float, delta: float) -> void:
	rotation.y = steer_angle
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
		_update_visual(setup.suspension_length, 0.0, setup, delta)
		return

	var contact: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var hit_distance := mount.distance_to(contact)
	compression = reach - hit_distance

	# Spring plus damper, along the car's up axis.
	var extend_speed := _point_velocity(car, mount).dot(up)  # Negative while compressing.
	var damping := setup.damper_bump if extend_speed < 0.0 else setup.damper_rebound
	var spring_rate := setup.spring_rate_front if is_front else setup.spring_rate_rear
	wheel_load = maxf(0.0, spring_rate * compression - damping * extend_speed)
	car.apply_force(up * wheel_load, mount - car.global_position)

	# Placeholder tire. Step 3 replaces this with a real grip curve.
	var forward := (-global_basis.z).slide(normal).normalized()
	var right := global_basis.x.slide(normal).normalized()
	var contact_velocity := _point_velocity(car, contact)
	var long_speed := contact_velocity.dot(forward)
	var lat_speed := contact_velocity.dot(right)

	var long_force := drive_n
	long_force -= clampf(long_speed * BRAKE_GAIN, -brake_n, brake_n)
	long_force -= clampf(long_speed, -1.0, 1.0) * setup.rolling_resistance * wheel_load
	var lat_force := -lat_speed * setup.lateral_stiffness
	# Friction circle: total tire force can't exceed grip times load.
	var tire := Vector2(long_force, lat_force).limit_length(setup.grip * wheel_load)
	car.apply_force(forward * tire.x + right * tire.y, contact - car.global_position)

	_update_visual(hit_distance - setup.wheel_radius, long_speed, setup, delta)


func _point_velocity(car: RigidBody3D, point: Vector3) -> Vector3:
	return car.linear_velocity + car.angular_velocity.cross(point - car.global_position)


func _update_visual(drop: float, long_speed: float, setup: CarSetup, delta: float) -> void:
	_visual.position.y = -drop
	_spin = wrapf(_spin + long_speed / setup.wheel_radius * delta, 0.0, TAU)
	_visual.rotation.x = -_spin
