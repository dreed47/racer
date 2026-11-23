class_name LearningLevel
extends Node
## How much the game helps you drive, from Noob (most help) to Expert (none).
## Sets the car's aids (anti-spin, ABS, traction control), the AI car's skill, and the guide
## on the road (a coloured line or brake boards). At Noob it also limits your top speed and
## brakes for you before a corner you're coming into too fast.
## Must sit between the player's driver and the car in the scene, so it can change the
## driver's throttle and brake before the car uses them.
## The level is picked in the tuning panel and kept in user://settings.cfg.

## Sent when the level changes.
signal changed(level: int)

enum { NOOB, NOVICE, EXPERIENCED, EXPERT }
const NAMES: Array[String] = ["Noob", "Novice", "Experienced", "Expert"]
## What each level gives. anti_spin: 0 to 1. top_kmh: 0 for no limit. guide: what shows on
## the road. plan: share of the tires' grip the guide's speeds are worked out for.
const LEVELS: Array[Dictionary] = [
	{"anti_spin": 1.0, "abs": true, "tc": true, "top_kmh": 80.0, "auto_brake": true,
			"guide": TrackGuide.LINE, "plan": 0.7, "ai_skill": 50.0},
	{"anti_spin": 0.6, "abs": true, "tc": true, "top_kmh": 0.0, "auto_brake": false,
			"guide": TrackGuide.LINE, "plan": 0.75, "ai_skill": 65.0},
	{"anti_spin": 0.3, "abs": false, "tc": true, "top_kmh": 0.0, "auto_brake": false,
			"guide": TrackGuide.MARKERS, "plan": 0.85, "ai_skill": 80.0},
	{"anti_spin": 0.0, "abs": false, "tc": false, "top_kmh": 0.0, "auto_brake": false,
			"guide": TrackGuide.NONE, "plan": 0.85, "ai_skill": 90.0},
]
const SETTINGS_PATH := "user://settings.cfg"
## Auto-brake starts once the slowing needed reaches this share of the guide's planned braking.
const AUTO_BRAKE_START := 0.7
## Auto-brake looks this many seconds ahead for slower points.
const AUTO_BRAKE_LOOK := 4.0
## Auto-brake and the line only follow you while you're this close to the guide line, in metres.
const NEAR_LINE := 15.0

@export var car: Car
@export var track: Track
## Optional. Its skill follows the level.
@export var ai: AiDriver
## Optional. Changing level cancels the lap you're on, and best laps keep the level.
@export var time_trial: TimeTrial
## Where the level is kept. Under tests it's in a temp folder (see SavePaths).
@export var settings_path := SETTINGS_PATH

var level := NOOB
## Line with the speeds for this level. Shared with the guide.
var line: RacingLine
## Line point the car is nearest.
var progress := 0
## Brake the auto-brake added on the last tick, 0 to 1. For tests and readouts.
var auto_brake := 0.0

var _guide: TrackGuide


func _ready() -> void:
	_guide = TrackGuide.new()
	_guide.car = car
	_guide.track = track
	add_child(_guide)
	level = load_level()
	# The AI driver may come later in the scene, so its line may not exist yet.
	_finish_setup.call_deferred()
	_apply()


func _finish_setup() -> void:
	if ai != null and ai.line != null:
		line = ai.line.copy()
	else:
		line = RacingLine.new(track)
	_guide.line = line
	_apply()


## The line or boards on the road. L turns it on and off.
func guide() -> TrackGuide:
	return _guide


## Name of the current level, such as "Noob".
func level_name() -> String:
	return NAMES[level]


## Changes the level, applies it and keeps it for next time.
func set_level(value: int) -> void:
	value = clampi(value, NOOB, EXPERT)
	if value == level:
		return
	level = value
	_apply()
	save_level()
	if time_trial != null:
		time_trial.cancel_lap()
	changed.emit(level)


## The saved level, or Noob if none is saved.
func load_level() -> int:
	var file := ConfigFile.new()
	if file.load(SavePaths.safe(settings_path)) != OK:
		return NOOB
	return clampi(int(file.get_value("driver", "level", NOOB)), NOOB, EXPERT)


func save_level() -> Error:
	var path := SavePaths.safe(settings_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := ConfigFile.new()
	file.load(path)  # Keep any other settings in the file.
	file.set_value("driver", "level", level)
	var err := file.save(path)
	if err != OK:
		push_warning("Could not save the level to %s: %s" % [path, error_string(err)])
	return err


func settings() -> Dictionary:
	return LEVELS[level]


func _apply() -> void:
	var s := settings()
	car.anti_spin = s.anti_spin
	car.abs_brakes = s.abs
	car.traction_allowed = s.tc
	if ai != null:
		ai.skill = s.ai_skill
	if time_trial != null:
		time_trial.level_name = level_name()
	if line != null:
		var grip: float = s.plan * car.setup.grip * RacingLine.GRAVITY
		var top: float = s.top_kmh / 3.6 if s.top_kmh > 0.0 else RacingLine.TOP_SPEED
		line.plan_speeds(grip, grip, top)
	_guide.mode = s.guide
	_guide.rebuild()


# Runs after the player's driver has set the pedals and before the car uses them.
func _physics_process(_delta: float) -> void:
	auto_brake = 0.0
	var s := settings()
	var v := car.forward_speed()
	if line != null:
		progress = line.nearest(car.global_position, progress)
		_guide.progress = progress
	if s.top_kmh > 0.0:
		_limit_speed(v, s.top_kmh / 3.6)
	if s.auto_brake and line != null and v > 3.0 \
			and car.global_position.distance_to(line.points[progress]) < NEAR_LINE:
		_brake_for_corners(v)


## Eases the throttle off near the top speed, and brakes gently if a hill pushes you past it.
func _limit_speed(v: float, top: float) -> void:
	car.throttle = minf(car.throttle, clampf((top - v) / 2.0, 0.0, 1.0))
	if v > top + 2.0:
		car.brake = maxf(car.brake, clampf((v - top - 2.0) * 0.1, 0.0, 0.4))


## Brakes when you come into a slower part of the line faster than you could stop for it,
## and only as hard as needed. Your own braking counts: it adds only what's missing.
func _brake_for_corners(v: float) -> void:
	var need := 0.0
	var metres := 4.0
	while metres <= v * AUTO_BRAKE_LOOK:
		var w := line.speed_ahead(progress, metres)
		need = maxf(need, (v * v - w * w) / (2.0 * metres))
		metres += 4.0
	if need < AUTO_BRAKE_START * line.brake_accel:
		return
	var full := car.setup.grip * RacingLine.GRAVITY
	auto_brake = clampf(need / full, 0.1, 0.8)
	car.throttle = 0.0
	car.brake = maxf(car.brake, auto_brake)
