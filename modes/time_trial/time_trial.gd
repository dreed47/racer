class_name TimeTrial
extends Node
## Time trial mode: one car, one track, laps against your own best.
## Watches the car; never drives it. A reset (the car's placed signal) cancels the lap.

@export var car: Car
@export var track: Track
## Where best laps are kept.
@export var records_path := LapRecords.DEFAULT_PATH

var timer: LapTimer
var records: LapRecords

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
	timer.lap_finished.connect(_on_lap_finished)
	car.placed.connect(_on_car_placed)
	_last_position = car.global_position


func _physics_process(delta: float) -> void:
	var now := car.global_position
	timer.step(_last_position, now, delta)
	_last_position = now


func _on_car_placed() -> void:
	timer.cancel()
	_last_position = car.global_position


func _on_lap_finished(time: float, _delta: float, is_best: bool) -> void:
	if not is_best:
		return
	var err := records.save_best(track.track_id, time, timer.best_splits)
	if err != OK:
		push_warning("Could not save best lap to %s: %s" % [records.path, error_string(err)])
