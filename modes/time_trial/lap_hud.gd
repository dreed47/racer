extends CanvasLayer
## Lap times at the top centre: current lap, last and best, and the gap to your best
## at each checkpoint and at the line.

## Seconds the gap and messages stay on screen.
const SHOW_TIME := 3.0
const FASTER := Color(0.35, 0.9, 0.4)
const SLOWER := Color(1.0, 0.4, 0.35)
const NEUTRAL := Color(1.0, 1.0, 1.0)

@export var time_trial: TimeTrial

var _lap: Label
var _times: Label
var _note: Label
var _note_left := 0.0


func _ready() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -200.0
	box.offset_right = 200.0
	box.offset_top = 12.0
	add_child(box)
	_lap = _label(box, 40)
	_times = _label(box, 20)
	_note = _label(box, 28)

	var timer := time_trial.timer
	timer.split.connect(func(_i, _t, delta): _show_delta(delta))
	timer.lap_finished.connect(_on_lap_finished)
	timer.lap_voided.connect(func(): _show_note("Missed a checkpoint: lap not counted", SLOWER))


func _process(delta: float) -> void:
	var timer := time_trial.timer
	_lap.text = LapTimer.format(timer.lap_time) if timer.running else "-:--.---"
	_times.text = "Last %s     Best %s" % [_or_dashes(timer.last_lap), _or_dashes(timer.best_lap)]
	_note_left -= delta
	if not timer.running and _note_left <= 0.0:
		# Steady prompt while waiting; a timed note (like a voided lap) shows first.
		_note.text = "Cross the start line to begin"
		_note.add_theme_color_override("font_color", NEUTRAL)
		_note.visible = true
	else:
		_note.visible = _note_left > 0.0


func _on_lap_finished(_time: float, delta: float, is_best: bool) -> void:
	if is_best and is_nan(delta):
		_show_note("First lap set", FASTER)
	elif is_best:
		_show_note("New best  %s" % _signed(delta), FASTER)
	else:
		_show_delta(delta)


func _show_delta(delta: float) -> void:
	if is_nan(delta):
		return
	_show_note(_signed(delta), FASTER if delta < 0.0 else SLOWER)


func _show_note(text: String, colour: Color, seconds := SHOW_TIME) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", colour)
	_note_left = seconds


func _label(parent: Control, size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label


static func _or_dashes(seconds: float) -> String:
	return LapTimer.format(seconds) if seconds > 0.0 else "-:--.---"


static func _signed(seconds: float) -> String:
	return "%+.3f" % seconds
