class_name CarSetup
extends Resource
## Tunable numbers for one car.
## Units: metres, kilograms, newtons, seconds, radians unless the name says deg or rpm.

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

@export_group("Tires")
## Peak friction coefficient: best tire force is grip times wheel load.
@export var grip := 1.0
## Wheel spin versus ground speed at peak grip. 0.1 means the tire spins 10 % faster.
@export var peak_slip_ratio := 0.1
## Slide angle at peak sideways grip.
@export var peak_slip_angle_deg := 8.0
## Shape of the grip curve. 1.4 keeps about 80 % grip once fully sliding.
## Higher values drop off harder after the peak.
@export var tire_shape := 1.4
## How much grip per newton falls as load rises. 0 means none.
@export var load_sensitivity := 0.1
## Load where grip equals the grip value above, in N.
@export var nominal_load := 2500.0
@export var rolling_resistance := 0.015
## Spin inertia of one wheel and tire, in kg m².
@export var wheel_inertia := 1.0

@export_group("Engine")
## Torque in N m at full throttle, at 0, 1000, 2000 ... rpm.
@export var torque_curve := PackedFloat32Array([80, 100, 125, 140, 148, 152, 150, 140, 120])
@export var idle_rpm := 900.0
## Fuel cuts above this.
@export var redline_rpm := 7200.0
## Spin inertia of the crank and flywheel, in kg m².
@export var engine_inertia := 0.15
## Engine braking torque with the throttle shut, in N m: base plus a part per 1000 rpm.
@export var engine_friction := 15.0
@export var engine_friction_per_krpm := 4.0

@export_group("Clutch")
## Automatic clutch: it starts to grip at the first rpm and is fully closed at the second.
@export var clutch_bite_rpm := 1000.0
@export var clutch_full_rpm := 1600.0
## Most torque the clutch can carry before it slips, in N m.
@export var clutch_max_torque := 300.0

@export_group("Gearbox")
## Forward gear ratios, first gear first.
@export var gear_ratios := PackedFloat32Array([3.136, 1.888, 1.330, 1.0, 0.814])
@export var reverse_ratio := 3.758
@export var final_drive := 4.3
## Seconds the clutch stays open while changing gear.
@export var shift_time := 0.2

@export_group("Brakes")
## Total brake torque over all four wheels, in N m.
@export var brake_torque := 3000.0
@export var brake_bias_front := 0.6
## Total handbrake torque over both rear wheels, in N m.
@export var handbrake_torque := 1500.0

@export_group("Aero")
@export var drag_coefficient := 0.4
@export var frontal_area := 1.8
