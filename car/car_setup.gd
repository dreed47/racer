class_name CarSetup
extends Resource
## Tunable numbers for one car.
## Units: metres, kilograms, newtons, seconds.

@export_group("Body")
@export var mass := 1000.0
@export var wheelbase := 2.27
@export var track_width := 1.41
## Height of the suspension mounts above the centre of mass.
@export var mount_height := 0.13

@export_group("Suspension")
## Mount to wheel centre with the spring fully extended.
@export var suspension_length := 0.35
@export var wheel_radius := 0.29
## Spring stiffness in N per metre.
@export var spring_rate_front := 40000.0
@export var spring_rate_rear := 35000.0
## Damping in N per m/s while the spring compresses.
@export var damper_bump := 2000.0
## Damping in N per m/s while the spring extends.
@export var damper_rebound := 3000.0

@export_group("Steering")
@export var max_steer_deg := 32.0
## Fraction of full lock left at 144 km/h and above.
@export var high_speed_steer := 0.35
## How fast the wheels turn, in full-input units per second.
@export var steer_rate := 4.0

@export_group("Placeholder tires")
## Step 3 replaces these with a real grip curve.
## Friction coefficient: maximum tire force is grip times wheel load.
@export var grip := 1.0
## Sideways force in N per m/s of sideways slide.
@export var lateral_stiffness := 3000.0
@export var rolling_resistance := 0.015

@export_group("Placeholder drive")
## Step 3 replaces these with an engine and gearbox.
## Total push at the rear wheels, in N.
@export var drive_force := 4000.0
## Fraction of drive force used in reverse.
@export var reverse_ratio := 0.4
## Total brake force, in N.
@export var brake_force := 9000.0
@export var brake_bias_front := 0.6
@export var handbrake_force := 6000.0

@export_group("Aero")
@export var drag_coefficient := 0.4
@export var frontal_area := 1.8
