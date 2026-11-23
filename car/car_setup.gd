class_name CarSetup
extends Resource
## Tunable numbers for one car.
## Units: metres, kilograms, newtons, seconds, radians unless the name says deg or rpm.

@export_group("Body")
@export_range(600, 2000, 10) var mass := 1000.0
@export_range(2.0, 3.2, 0.01) var wheelbase := 2.27
@export_range(1.2, 1.8, 0.01) var track_width := 1.41
## Height of the suspension mounts above the centre of mass.
@export_range(-0.2, 0.5, 0.01) var mount_height := 0.13

@export_group("Suspension")
## Mount to wheel centre with the spring fully extended.
@export_range(0.15, 0.6, 0.01) var suspension_length := 0.35
@export_range(0.25, 0.4, 0.005) var wheel_radius := 0.29
## Spring stiffness in N per metre.
@export_range(10000, 150000, 500) var spring_rate_front := 40000.0
@export_range(10000, 150000, 500) var spring_rate_rear := 35000.0
## Damping in N per m/s while the spring compresses.
@export_range(200, 10000, 50) var damper_bump := 2000.0
## Damping in N per m/s while the spring extends.
@export_range(200, 10000, 50) var damper_rebound := 3000.0

@export_group("Anti-roll bars")
## Extra force in N per metre of difference between left and right spring compression.
## More at one end moves grip away from that end in corners: more rear means less understeer.
@export_range(0, 60000, 500) var anti_roll_front := 0.0
@export_range(0, 60000, 500) var anti_roll_rear := 0.0

@export_group("Steering")
@export_range(10, 45, 0.5) var max_steer_deg := 32.0
## Speed-based steering limit, for a gamepad. 0 off: full stick is always full lock.
## 1 on: full stick turns the wheels only as far as the tires can use at that speed.
@export_range(0, 1, 0.01) var steer_assist := 1.0
## Extra wheel angle the assist allows at full stick, as a part of the peak slip angle.
## 0.4 puts full stick at about peak grip; higher lets you push past it.
@export_range(0, 2, 0.05) var steer_assist_slip := 0.4
## How fast the wheels turn, in full-input units per second.
@export_range(1, 10, 0.1) var steer_rate := 4.0

@export_group("Tires")
## Peak friction coefficient: best tire force is grip times wheel load.
@export_range(0.5, 2, 0.01) var grip := 1.0
## Wheel spin versus ground speed at peak grip. 0.1 means the tire spins 10 % faster.
@export_range(0.03, 0.3, 0.005) var peak_slip_ratio := 0.1
## Slide angle at peak sideways grip.
@export_range(2, 20, 0.5) var peak_slip_angle_deg := 8.0
## Shape of the grip curve. 1.4 keeps about 80 % grip once fully sliding.
## Higher values drop off harder after the peak.
@export_range(1.1, 1.9, 0.01) var tire_shape := 1.4
## How much grip per newton falls as load rises. 0 means none.
@export_range(0, 0.4, 0.01) var load_sensitivity := 0.1
## Load where grip equals the grip value above, in N.
@export_range(1000, 6000, 50) var nominal_load := 2500.0
@export_range(0, 0.05, 0.001) var rolling_resistance := 0.015
## Spin inertia of one wheel and tire, in kg m².
@export_range(0.3, 3, 0.05) var wheel_inertia := 1.0

@export_group("Engine")
## Torque in N m at full throttle, at 0, 1000, 2000 ... rpm.
@export var torque_curve := PackedFloat32Array([80, 100, 125, 140, 148, 152, 150, 140, 120])
@export_range(600, 1500, 10) var idle_rpm := 900.0
## Fuel cuts above this.
@export_range(4000, 10000, 50) var redline_rpm := 7200.0
## Spin inertia of the crank and flywheel, in kg m².
@export_range(0.05, 0.5, 0.01) var engine_inertia := 0.15
## Engine braking torque with the throttle shut, in N m: base plus a part per 1000 rpm.
@export_range(0, 50, 0.5) var engine_friction := 15.0
@export_range(0, 15, 0.5) var engine_friction_per_krpm := 4.0

@export_group("Clutch")
## Automatic clutch: it starts to grip at the first rpm and is fully closed at the second.
@export_range(600, 3000, 10) var clutch_bite_rpm := 1000.0
@export_range(800, 5000, 10) var clutch_full_rpm := 1600.0
## Most torque the clutch can carry before it slips, in N m.
@export_range(100, 800, 10) var clutch_max_torque := 300.0

@export_group("Gearbox")
## Forward gear ratios, first gear first.
@export var gear_ratios := PackedFloat32Array([3.136, 1.888, 1.330, 1.0, 0.814])
@export_range(2, 5, 0.01) var reverse_ratio := 3.758
@export_range(2.5, 6, 0.01) var final_drive := 4.3
## Seconds the clutch stays open while changing gear.
@export_range(0, 1, 0.01) var shift_time := 0.2

@export_group("Brakes")
## Total brake torque over all four wheels, in N m.
@export_range(500, 8000, 50) var brake_torque := 3000.0
@export_range(0.3, 0.8, 0.01) var brake_bias_front := 0.6
## Total handbrake torque over both rear wheels, in N m.
@export_range(0, 5000, 50) var handbrake_torque := 1500.0

@export_group("Aero")
@export_range(0.2, 1, 0.01) var drag_coefficient := 0.4
@export_range(1.2, 3, 0.05) var frontal_area := 1.8

@export_group("Driver aids")
## Cuts engine power when a rear wheel spins faster than the road, so the back stays put.
@export var traction_control := true
## Wheelspin allowed before power is cut, as a share of the tire's peak slip ratio.
## 1 lets the tire reach full grip; lower is safer, higher allows more slide.
@export_range(0.5, 3, 0.05) var traction_slip := 1.0
