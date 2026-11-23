class_name CourseMap
extends CanvasLayer
## Small map of the track in the top-right corner, north up, so the shape stays the same and
## you learn it. Shows you as a white arrow, the AI car as a yellow dot and the start line.
## N or D-pad left turns it on and off.

## Sent when the map is turned on or off.
signal toggled(shown: bool)

## Map size on screen and gap to the screen edge, in pixels.
const SIZE := 400.0
const MARGIN := 24.0
## Space inside the map's box around the track, in pixels.
const PADDING := 26.0
## Grows the arrow, dot and start line so they read well on a big screen.
const MARK := 1.6
## Track outline is sampled every this many metres.
const STEP := 5.0
const ROAD := Color(0.85, 0.85, 0.85)
const ROAD_EDGE := Color(0.1, 0.1, 0.1, 0.9)
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.5)
const YOU := Color.WHITE
const AI := Color(1.0, 0.85, 0.1)
const START := Color(0.95, 0.15, 0.1)

@export var track: Track
@export var car: Car
## Optional. Its car shows only while the AI is on.
@export var ai: AiDriver

var shown := true
## Track outline in map pixels, for tests.
var outline := PackedVector2Array()

var _canvas: Control
var _origin := Vector2.ZERO
var _scale := 1.0


func _ready() -> void:
	_canvas = Control.new()
	_canvas.anchor_left = 1.0
	_canvas.anchor_right = 1.0
	_canvas.offset_left = -(SIZE + MARGIN)
	_canvas.offset_right = -MARGIN
	_canvas.offset_top = MARGIN
	_canvas.offset_bottom = MARGIN + SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	_build_outline()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_map") and get_viewport().gui_get_focus_owner() == null:
		toggle()
	if shown:
		_canvas.queue_redraw()


func toggle() -> void:
	shown = not shown
	_canvas.visible = shown
	toggled.emit(shown)


## Where a point in the world sits on the map, in pixels from the map's top-left corner.
## North (-z) is up and east (+x) is right.
func to_map(where: Vector3) -> Vector2:
	return _origin + Vector2(where.x, where.z) * _scale


func _build_outline() -> void:
	outline.clear()
	if track == null or track.lap_length() <= 0.0:
		return
	var flat := PackedVector2Array()
	var d := 0.0
	while d < track.lap_length():
		var p := track.point_at(d)
		flat.append(Vector2(p.x, p.z))
		d += STEP
	var low := flat[0]
	var high := flat[0]
	for p in flat:
		low = low.min(p)
		high = high.max(p)
	var span := high - low
	_scale = (SIZE - 2.0 * PADDING) / maxf(maxf(span.x, span.y), 1.0)
	# Centre the track in the box.
	_origin = Vector2(SIZE, SIZE) / 2.0 - (low + span / 2.0) * _scale
	for p in flat:
		outline.append(_origin + p * _scale)
	outline.append(outline[0])


func _draw_map() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), BACKGROUND)
	if outline.size() < 2:
		return
	_canvas.draw_polyline(outline, ROAD_EDGE, 15.0, true)
	_canvas.draw_polyline(outline, ROAD, 9.0, true)
	_draw_start()
	if ai != null and ai.active and ai.car != null:
		var p := to_map(ai.car.global_position)
		_canvas.draw_circle(p, 6.0 * MARK, ROAD_EDGE)
		_canvas.draw_circle(p, 4.5 * MARK, AI)
	if car != null:
		_draw_arrow(to_map(car.global_position), car.global_basis.z)


func _draw_start() -> void:
	var gate := track.gate(0)
	var p := to_map(gate.origin)
	var across := Vector2(gate.basis.x.x, gate.basis.x.z).normalized() * 12.0
	_canvas.draw_line(p - across, p + across, ROAD_EDGE, 8.0)
	_canvas.draw_line(p - across, p + across, START, 4.5)


## A triangle pointing the way the car faces. back is the car's +z axis.
func _draw_arrow(p: Vector2, back: Vector3) -> void:
	var ahead := -Vector2(back.x, back.z).normalized()
	if ahead == Vector2.ZERO:
		ahead = Vector2.UP
	ahead *= MARK
	var side := Vector2(-ahead.y, ahead.x)
	var tip := p + ahead * 10.0
	var points := PackedVector2Array([tip, p - ahead * 6.0 + side * 7.0, p - ahead * 3.0, p - ahead * 6.0 - side * 7.0])
	var edge := PackedVector2Array([tip + ahead * 2.0, p - ahead * 7.5 + side * 9.0, p - ahead * 4.0,
			p - ahead * 7.5 - side * 9.0])
	_canvas.draw_colored_polygon(edge, ROAD_EDGE)
	_canvas.draw_colored_polygon(points, YOU)
