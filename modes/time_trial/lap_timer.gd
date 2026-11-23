class_name LapTimer
extends RefCounted
## Lap timing from a car's position each physics tick. Plain logic, no nodes, so tests can feed it.
## Gate 0 is the start/finish line; the rest are checkpoints, passed in order.
## A gate counts only when crossed forward, inside its width. Times use physics time and are
## interpolated inside the tick, so they don't depend on frame rate.

## A move longer than this in one tick is a teleport (a reset), never a crossing.
const MAX_STEP := 20.0
## Gates reach this far past the road edge, so a lap with two wheels on the grass still counts.
const EDGE_MARGIN := 3.0

## Lap started: crossed the start line going forward.
signal lap_started
## Checkpoint passed. delta is against the best lap at the same checkpoint, or NAN if none.
signal split(index: int, time: float, delta: float)
## Lap finished. delta is against the previous best, or NAN if none.
signal lap_finished(time: float, delta: float, is_best: bool)
## Lap thrown away: the start line came round again before every checkpoint.
signal lap_voided

var gates: Array[Transform3D] = []
var half_width := 5.0

var running := false
## Time in the current lap, in seconds.
var lap_time := 0.0
## 0 means the start/finish line is next.
var next_gate := 0
## Times at each checkpoint in the current lap.
var splits: Array[float] = []
## 0 means none yet.
var last_lap := 0.0
## 0 means none yet.
var best_lap := 0.0
var best_splits: Array[float] = []


func _init(gate_list: Array[Transform3D], gate_half_width: float) -> void:
	gates = gate_list
	half_width = gate_half_width


## Moves the timer on by one tick, as the car goes from one place to another.
func step(from: Vector3, to: Vector3, delta: float) -> void:
	if running:
		lap_time += delta
	if from.distance_to(to) > MAX_STEP:
		return

	if running and next_gate != 0:
		var f := crossing(next_gate, from, to)
		if f >= 0.0:
			var t := lap_time - delta * (1.0 - f)
			var k := splits.size()
			splits.append(t)
			split.emit(next_gate, t, t - best_splits[k] if k < best_splits.size() else NAN)
			next_gate = (next_gate + 1) % gates.size()
			return

	var f0 := crossing(0, from, to)
	if f0 < 0.0:
		return
	var since := delta * (1.0 - f0)
	if running and next_gate == 0:
		_finish(lap_time - since)
	elif running:
		lap_voided.emit()
	running = true
	lap_time = since
	splits.clear()
	next_gate = 1 % gates.size()
	lap_started.emit()


## Stops the current lap without a time, such as after a reset.
func cancel() -> void:
	running = false
	lap_time = 0.0
	next_gate = 0
	splits.clear()


## Loads a saved best lap.
func set_best(time: float, best_split_times: Array[float]) -> void:
	best_lap = time
	best_splits = best_split_times.duplicate()


## Where in the move the car crosses a gate forward, 0 to 1, or -1 if it doesn't.
func crossing(index: int, from: Vector3, to: Vector3) -> float:
	var g := gates[index]
	var forward := -g.basis.z
	var before := (from - g.origin).dot(forward)
	var after := (to - g.origin).dot(forward)
	if not (before < 0.0 and after >= 0.0):
		return -1.0
	var f := before / (before - after)
	var side := (from.lerp(to, f) - g.origin).dot(g.basis.x)
	return f if absf(side) <= half_width + EDGE_MARGIN else -1.0


## Lap time as m:ss.mmm.
static func format(seconds: float) -> String:
	var ms := roundi(seconds * 1000.0)
	return "%d:%02d.%03d" % [ms / 60000, (ms / 1000) % 60, ms % 1000]


func _finish(time: float) -> void:
	var delta := time - best_lap if best_lap > 0.0 else NAN
	var is_best := best_lap <= 0.0 or time < best_lap
	last_lap = time
	if is_best:
		best_lap = time
		best_splits = splits.duplicate()
	lap_finished.emit(time, delta, is_best)
