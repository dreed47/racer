class_name TimeTrial
extends Node
## Time trial mode: one car, one track, laps against your own best.
## Watches the car; never drives it. A reset (the car's placed signal) cancels the lap.
## Records every lap. The fastest one is kept as the ghost (see GhostCar) and saved.

@export var car: Car
@export var track: Track
## Where best laps are kept.
@export var records_path := LapRecords.DEFAULT_PATH
## Folder where ghost laps are kept, one file per track.
@export var ghost_dir := "user://ghosts"

var timer: LapTimer
var records: LapRecords
## Fastest recorded lap on this track, or null if none yet.
var ghost: GhostRecording
## Learning level you're driving at (see LearningLevel). Kept with a new best lap.
var level_name := ""
## Learning level the best lap was driven at, or "" if not known.
var best_level := ""

var _recording: GhostRecording

var _last_position := Vector3.ZERO


func _ready() -> void:
	var gates: Array[Transform3D] = []
	for i in track.gate_count():
		gates.append(track.gate(i))
	timer = LapTimer.new(gates, track.gate_half_width())
	records = LapRecords.new(records_path)
	var saved := records.best(track.track_id)
	if not saved.is_empty():
		timer.set_best(saved.time, saved.splits)
		best_level = saved.level
	ghost = GhostRecording.load_file(ghost_path())
	timer.lap_finished.connect(_on_lap_finished)
	timer.lap_started.connect(_on_lap_started)
	car.placed.connect(_on_car_placed)
	_last_position = car.global_position


func _physics_process(delta: float) -> void:
	var now := car.global_position
	timer.step(_last_position, now, delta)
	_last_position = now
	if timer.running and _recording != null:
		_recording.add_car(timer.lap_time, car)


## Ghost file for this track. Under tests it's in a temp folder (see SavePaths).
func ghost_path() -> String:
	return SavePaths.safe(ghost_dir.path_join(track.track_id + ".ghost"))


func _on_lap_started() -> void:
	_recording = GhostRecording.new(track.track_id)


## Throws away the lap you're on, as a reset does, without moving the car.
## The clock starts again next time you cross the line.
func cancel_lap() -> void:
	timer.cancel()
	_recording = null


func _on_car_placed() -> void:
	timer.cancel()
	_recording = null
	_last_position = car.global_position


func _on_lap_finished(time: float, _delta: float, is_best: bool) -> void:
	_keep_ghost(time)
	if not is_best:
		return
	best_level = level_name
	var err := records.save_best(track.track_id, time, timer.best_splits, level_name)
	if err != OK:
		push_warning("Could not save best lap to %s: %s" % [records.path, error_string(err)])


## Keeps the lap just finished as the ghost if it's the fastest recorded one, and saves it.
func _keep_ghost(time: float) -> void:
	if _recording == null or _recording.size() < 2:
		return
	if ghost != null and time >= ghost.lap_time:
		return
	_recording.add_car(time, car)
	_recording.lap_time = time
	ghost = _recording
	_recording = null
	var err := ghost.save(ghost_path())
	if err != OK:
		push_warning("Could not save ghost lap to %s: %s" % [ghost_path(), error_string(err)])
