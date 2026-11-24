class_name AiDriver
extends Node
## Drives a second car round the track for you to race. It follows a racing line worked out
## from the track (see RacingLine), steering towards a point ahead on the line and braking
## in time for each corner. It ignores the player: no steering round you, though the cars
## do bump. It changes gear itself. Its laps never count towards your times.
## I or D-pad right turns it on and off. Turning it on puts both cars back on the grid,
## with the AI car on your right; it waits until you move off.

## Sent when the AI car is turned on or off.
signal toggled(on: bool)

## Share of the tires' grip the AI plans for at full skill. Calibrated on Ridge.
const CORNER_GRIP := 0.85
const BRAKE_GRIP := 0.85
## How far right of the player's start the AI car starts, in metres.
const GRID_GAP := 3.0
## Steering looks this far ahead: a fixed part plus a part that grows with speed.
const LOOK_BASE := 5.0
const LOOK_TIME := 0.45
## Speed control looks this far ahead, in seconds, to start braking in time.
const SPEED_LOOK := 0.3
## Braking looks this many seconds ahead for slower points.
const BRAKE_LOOK := 4.0
## Start braking once the slowing needed reaches this share of the planned braking.
const BRAKE_START := 0.6
const MAX_BRAKE := 0.85
## Less brake the more the wheels are turned, to leave grip for turning.
const STEER_CUT := 0.8
## Catching a slide, by the angle between where the car points and where it goes, in degrees.
## Past SLIDE_START the AI steers into the slide, COUNTER_GAIN times the extra angle.
## Past SLIDE_LET_GO it lets off the brake too.
const SLIDE_START := 3.0
const SLIDE_LET_GO := 7.0
const COUNTER_GAIN := 1.2
## How hard the steering fights a turn rate that differs from what the line needs. Stops the
## car weaving on fast bends.
const YAW_DAMP := 1.0
## Put back on the line when slower than this for STUCK_TIME, or further than OFF_LINE away.
const STUCK_SPEED := 1.5
const STUCK_TIME := 4.0
const OFF_LINE := 12.0
const FALL_LIMIT := -20.0
## Paint colour of the AI car, so you can tell it from yours.
const PAINT := Color(0.95, 0.7, 0.1)

@export var car: Car
@export var track: Track
## Your car. The AI car starts beside it and waits for it to move off.
@export var player: Car
## How close to the grip limit the AI drives, in %. Lower is slower and safer.
@export_range(30, 100, 1) var skill := 90.0:
	set(value):
		skill = clampf(value, 30.0, 100.0)
		if line != null:
			line.plan_speeds(_corner_accel(), _brake_accel())

var active := false
var line: RacingLine
## Times the car was put back on the line since it was turned on.
var recoveries := 0
## Index of the line point the car is nearest.
var progress := 0

var _waiting := false
var _stuck_time := 0.0


func _ready() -> void:
	line = RacingLine.new(track, 1.6, _corner_accel(), _brake_accel())
	_paint(car)
	if player != null:
		player.placed.connect(_on_player_placed)
	_set_car_on(false)


func _process(_delta: float) -> void:
	# Skip while a menu (the tuning panel) has focus: the D-pad moves through it then.
	if Input.is_action_just_pressed("toggle_ai") and get_viewport().gui_get_focus_owner() == null:
		toggle()


func toggle() -> void:
	set_active(not active)


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_set_car_on(on)
	if on:
		recoveries = 0
		if player != null:
			player.place_at(_spawn())  # The AI car follows through _on_player_placed.
		else:
			place_on_grid()
	toggled.emit(on)


## Puts the AI car on the grid beside the player's start. It waits there for the player.
func place_on_grid() -> void:
	var where := _spawn()
	where.origin += where.basis.x * GRID_GAP
	car.place_at(where)
	progress = line.nearest(where.origin)
	_waiting = player != null
	_stuck_time = 0.0


func _physics_process(delta: float) -> void:
	if not active:
		return
	var v := car.forward_speed()
	progress = line.nearest(car.global_position, progress)
	if _waiting:
		_hold()
		if player.forward_speed() > 1.0 or player.global_position.distance_to(_spawn().origin) > 3.0:
			_waiting = false
		return
	if car.is_placing():
		return  # Its old position would look far off the line.
	if _needs_rescue(v, delta):
		_rescue()
		return
	_steer(v)
	_drive(v)
	_change_gear(v)


func _hold() -> void:
	car.throttle = 0.0
	car.brake = 1.0
	car.steer = 0.0
	car.handbrake = false


## Pure pursuit: aim the front wheels so the car's path arcs through a point on the line ahead.
func _steer(v: float) -> void:
	var look := LOOK_BASE + LOOK_TIME * maxf(v, 0.0)
	var target := car.to_local(line.point_ahead(progress, look))
	var distance := Vector2(target.x, target.z).length()
	var alpha := atan2(target.x, -target.z)  # Positive when the point is to the right.
	var bend := 2.0 * sin(alpha) / maxf(distance, 1.0)  # Curvature of the arc to the point.
	var angle := atan(car.setup.wheelbase * bend)
	# Damp the weave: steer less while the car turns faster than the arc needs, more while slower.
	var yaw := -car.angular_velocity.dot(car.global_basis.y)  # Positive when turning right.
	angle += YAW_DAMP * car.setup.wheelbase * (bend * v - yaw) / maxf(v, 5.0)
	# Steer into a slide: point the front wheels more towards where the car is going.
	var slide := _slide_angle()
	if absf(slide) > deg_to_rad(SLIDE_START):
		angle += COUNTER_GAIN * (slide - signf(slide) * deg_to_rad(SLIDE_START))
	car.steer = clampf(angle / car.steer_lock(absf(v)), -1.0, 1.0)


## Angle between where the car points and where it is going, flat, in radians.
## Positive when the car is moving to the right of its nose.
func _slide_angle() -> float:
	var local := car.global_basis.inverse() * car.linear_velocity
	if -local.z < 3.0:
		return 0.0
	return atan2(local.x, -local.z)


## Throttle and brake to hold the line's speed. Brakes as hard as the slowest point ahead needs.
func _drive(v: float) -> void:
	var want := line.speed_ahead(progress, maxf(v, 0.0) * SPEED_LOOK + 2.0)
	var need := _braking_needed(v)
	car.handbrake = false
	if need < BRAKE_START * line.brake_accel and want - v >= -0.5:
		var throttle := clampf(0.3 + 0.5 * (want - v), 0.0, 1.0)
		# Ease off while any tire slides: spinning rears or fronts pushing wide.
		var slide := 0.0
		for wheel in car.wheels:
			slide = maxf(slide, wheel.slip_level)
		if slide > 1.1:
			throttle *= clampf(1.0 - (slide - 1.1), 0.0, 1.0)
		car.throttle = throttle
		car.brake = 0.0
		return
	car.throttle = 0.0
	# Brakes off while the car slides sideways, or the rear tires can't grip to stop it.
	if absf(_slide_angle()) > deg_to_rad(SLIDE_LET_GO):
		car.brake = 0.0
		return
	var full := car.setup.grip * RacingLine.GRAVITY
	var brake := clampf(need / full + 0.15 * (v - want), 0.05, MAX_BRAKE)
	# Leave grip for turning: less brake the more the wheels are turned.
	brake *= clampf(1.0 - STEER_CUT * absf(car.steer), 0.0, 1.0)
	# Simple ABS: ease off while a front tire locks. Let go almost fully while a rear tire
	# slides, since braking while turning can swing the back of the car round.
	for i in 4:
		var slip := car.wheels[i].slip_level
		if i < 2 and slip > 1.0:
			brake *= 0.7
		elif i >= 2 and slip > 0.8:
			brake *= 0.3
	car.brake = brake


## Slowing needed to reach the slowest point ahead in time, in m/s².
func _braking_needed(v: float) -> float:
	var need := 0.0
	var reach := maxf(v, 0.0) * BRAKE_LOOK
	var metres := 4.0
	while metres <= reach:
		var w := line.speed_ahead(progress, metres)
		need = maxf(need, (v * v - w * w) / (2.0 * metres))
		metres += 4.0
	return need


## Up near the redline. Down only on the throttle, when the engine is low in its range and the
## lower gear still leaves room to rev: a downshift while slowing makes engine braking spin
## the rear wheels. Rpm is worked out from road speed, since the engine slows during a shift.
func _change_gear(v: float) -> void:
	var dt := car.drivetrain
	if dt.gear < 1:
		car.shift(1)
		return
	var redline := car.setup.redline_rpm
	var rpm := _rpm_in(dt.gear, v)
	if rpm > redline - 300.0 and dt.gear < dt.top_gear():
		car.shift(1)
	elif (dt.gear > 1 and car.throttle > 0.5 and rpm < redline * 0.5
			and _rpm_in(dt.gear - 1, v) < redline - 1500.0
			and car.wheels[2].slip_level < 1.0 and car.wheels[3].slip_level < 1.0):
		car.shift(-1)


## Engine rpm in a forward gear at a road speed, with no wheelspin.
func _rpm_in(gear: int, v: float) -> float:
	var spin := maxf(v, 0.0) / car.setup.wheel_radius * car.setup.gear_ratios[gear - 1] * car.setup.final_drive
	return spin * 60.0 / TAU


func _needs_rescue(v: float, delta: float) -> bool:
	_stuck_time = _stuck_time + delta if absf(v) < STUCK_SPEED else 0.0
	var off := car.global_position.distance_to(line.points[progress]) > OFF_LINE
	return _stuck_time > STUCK_TIME or off or car.global_position.y < FALL_LIMIT


## Back on the line at the nearest point, pointing the right way.
func _rescue() -> void:
	recoveries += 1
	_stuck_time = 0.0
	var where := Transform3D(Basis.looking_at(line.direction(progress)), line.points[progress] + Vector3.UP * 0.8)
	car.place_at(where)
	_hold()


func _on_player_placed() -> void:
	if active:
		place_on_grid()


func _set_car_on(on: bool) -> void:
	car.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	car.visible = on
	if not on:
		_hold()


func _spawn() -> Transform3D:
	return (track.get_node("Spawn") as Node3D).global_transform


func _corner_accel() -> float:
	return skill / 100.0 * CORNER_GRIP * car.setup.grip * RacingLine.GRAVITY


func _brake_accel() -> float:
	return skill / 100.0 * BRAKE_GRIP * car.setup.grip * RacingLine.GRAVITY


## Gives the car its own body colour.
static func _paint(target: Car) -> void:
	for mesh: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s) as StandardMaterial3D
			if m != null and m.resource_name == "paint":
				var copy := m.duplicate() as StandardMaterial3D
				copy.albedo_color = PAINT
				mesh.set_surface_override_material(s, copy)
