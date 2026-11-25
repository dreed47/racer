class_name Dashboard
extends CanvasLayer
## Gauges at the bottom centre of the screen: a rev counter with a red zone and a shift light,
## a speed dial with the exact speed in its middle, the gear as a big number between them, and
## bars for the brake and throttle pedals.

## Dial radius, gap between the two dial centres and gap to the bottom of the screen, in pixels.
## SCALE draws that layout 50% bigger. The pivot stays on the bottom edge, so they grow up.
const SCALE := 1.5
const RADIUS := 150.0
const SPACING := 470.0
const MARGIN := 24.0
## The needle sweeps this many degrees, starting bottom-left and going clockwise.
const SWEEP := 240.0
const START := 150.0
const TOP_SPEED := 240.0
## The shift light comes on this far below the redline, and flashes in the last part.
const SHIFT_WARN_RPM := 600.0
const SHIFT_NOW_RPM := 250.0
## Pedal bar size, in pixels.
const BAR := Vector2(34, 110)

const FACE := Color(0.05, 0.05, 0.07, 0.75)
const RIM := Color(0.75, 0.75, 0.8)
const TICK := Color(0.92, 0.92, 0.92)
const NEEDLE := Color(1.0, 0.45, 0.1)
const GREEN := Color(0.2, 0.8, 0.3)
const YELLOW := Color(1.0, 0.8, 0.15)
const RED := Color(0.95, 0.15, 0.1)
const BLUE := Color(0.3, 0.65, 1.0)
const DIM := Color(0.25, 0.25, 0.28)

@export var car: Car

var _canvas: Control
var _font: Font
var _time := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.anchor_left = 0.5
	_canvas.anchor_right = 0.5
	_canvas.anchor_top = 1.0
	_canvas.anchor_bottom = 1.0
	_canvas.offset_left = -(SPACING / 2.0 + RADIUS)
	_canvas.offset_right = SPACING / 2.0 + RADIUS
	_canvas.offset_top = -(2.0 * RADIUS + MARGIN)
	_canvas.offset_bottom = -MARGIN
	_canvas.pivot_offset = Vector2(SPACING / 2.0 + RADIUS, 2.0 * RADIUS)
	_canvas.scale = Vector2(SCALE, SCALE)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_gauges)
	add_child(_canvas)


func _process(delta: float) -> void:
	_time += delta
	_canvas.queue_redraw()


## Top of the rev counter in rpm: the redline plus at least 1000, rounded up to a whole 1000.
func max_rpm() -> float:
	return ceilf((car.setup.redline_rpm + 1000.0) / 1000.0) * 1000.0


## Needle angle in radians for a dial reading from 0 (empty) to 1 (full).
## Angles are clockwise from the right, as on screen.
static func dial_angle(fraction: float) -> float:
	return deg_to_rad(START + SWEEP * clampf(fraction, 0.0, 1.0))


## Off, on, or flashing: 0 when there's no need to shift up, 1 when it's nearly time,
## 2 when it's time now. Never lit in top gear, neutral or reverse.
func shift_light() -> int:
	var d := car.drivetrain
	if d.gear < 1 or d.gear >= d.top_gear():
		return 0
	var rpm := d.rpm()
	if rpm >= car.setup.redline_rpm - SHIFT_NOW_RPM:
		return 2
	if rpm >= car.setup.redline_rpm - SHIFT_WARN_RPM:
		return 1
	return 0


## The gear as the driver sees it: R, N or a number.
func gear_text() -> String:
	var gear := car.drivetrain.gear
	return "R" if gear < 0 else ("N" if gear == 0 else str(gear))


func _draw_gauges() -> void:
	if car == null or car.drivetrain == null:
		return
	var left := Vector2(RADIUS, RADIUS)
	var right := Vector2(RADIUS + SPACING, RADIUS)
	_draw_revs(left)
	_draw_speed(right)
	_draw_gear_and_pedals((left + right) / 2.0)


func _draw_face(centre: Vector2) -> void:
	_canvas.draw_circle(centre, RADIUS, FACE)
	_canvas.draw_arc(centre, RADIUS - 2.0, 0.0, TAU, 96, RIM, 4.0, true)


func _draw_band(centre: Vector2, from: float, to: float, colour: Color) -> void:
	_canvas.draw_arc(centre, RADIUS - 16.0, dial_angle(from), dial_angle(to), 48, colour, 12.0, true)


## Tick marks round the dial. Every step gets a short tick; every label_every-th a long one with
## its number.
func _draw_ticks(centre: Vector2, steps: int, label_every: int, label_scale: float) -> void:
	for i in steps + 1:
		var a := dial_angle(float(i) / steps)
		var out := Vector2.from_angle(a)
		var long := i % label_every == 0
		var inner := RADIUS - (34.0 if long else 26.0)
		_canvas.draw_line(centre + out * inner, centre + out * (RADIUS - 8.0), TICK, 4.0 if long else 2.0, true)
		if long:
			_draw_centred(str(int(i * label_scale)), centre + out * (RADIUS - 56.0), 24, TICK)


func _draw_needle(centre: Vector2, fraction: float) -> void:
	var out := Vector2.from_angle(dial_angle(fraction))
	_canvas.draw_line(centre - out * 18.0, centre + out * (RADIUS - 20.0), Color.BLACK, 9.0, true)
	_canvas.draw_line(centre - out * 16.0, centre + out * (RADIUS - 22.0), NEEDLE, 5.0, true)
	_canvas.draw_circle(centre, 11.0, DIM)
	_canvas.draw_circle(centre, 7.0, NEEDLE)


func _draw_revs(centre: Vector2) -> void:
	var top := max_rpm()
	var redline: float = car.setup.redline_rpm
	_draw_face(centre)
	_draw_band(centre, 0.0, (redline - 1500.0) / top, GREEN)
	_draw_band(centre, (redline - 1500.0) / top, redline / top, YELLOW)
	_draw_band(centre, redline / top, 1.0, RED)
	var thousands := int(top / 1000.0)
	_draw_ticks(centre, thousands * 2, 2, 0.5)
	_draw_centred("x1000 rpm", centre + Vector2(0, 50), 18, TICK)
	_draw_shift_light(centre + Vector2(0, -52))
	_draw_needle(centre, car.drivetrain.rpm() / top)


func _draw_shift_light(where: Vector2) -> void:
	var state := shift_light()
	var lit := state == 1 or (state == 2 and fmod(_time, 0.2) < 0.1)
	var colour := (YELLOW if state == 1 else RED) if lit else DIM
	_canvas.draw_circle(where, 15.0, Color.BLACK)
	_canvas.draw_circle(where, 12.0, colour)
	_draw_centred("SHIFT", where + Vector2(0, 32), 16, colour if lit else DIM.lightened(0.3))


func _draw_speed(centre: Vector2) -> void:
	var kmh := absf(car.forward_speed()) * 3.6
	_draw_face(centre)
	_draw_band(centre, 0.0, 1.0, BLUE.darkened(0.3))
	_draw_ticks(centre, int(TOP_SPEED / 20.0), 2, 20.0)
	_draw_needle(centre, kmh / TOP_SPEED)
	_draw_centred("%d" % roundi(kmh), centre + Vector2(0, 62), 44, Color.WHITE)
	_draw_centred("km/h", centre + Vector2(0, 92), 18, TICK)


func _draw_gear_and_pedals(centre: Vector2) -> void:
	var gear := gear_text()
	var colour := GREEN if gear == "N" else (NEEDLE if gear == "R" else Color.WHITE)
	var box := Rect2(centre + Vector2(-58, -RADIUS + 6.0), Vector2(116, 116))
	_canvas.draw_rect(box, FACE)
	_canvas.draw_rect(box, RIM, false, 3.0)
	_draw_centred(gear, box.get_center() + Vector2(0, 4), 96, colour)
	_draw_centred("GEAR", box.position + Vector2(58, 132), 16, TICK)

	var bottom := RADIUS * 2.0 - 30.0
	_draw_bar(Vector2(centre.x - BAR.x - 10.0, bottom - BAR.y), car.brake, RED, "Brake")
	_draw_bar(Vector2(centre.x + 10.0, bottom - BAR.y), car.throttle, GREEN, "Gas")


func _draw_bar(top_left: Vector2, amount: float, colour: Color, label: String) -> void:
	var frame := Rect2(top_left, BAR)
	_canvas.draw_rect(frame, FACE)
	var fill := BAR.y * clampf(amount, 0.0, 1.0)
	_canvas.draw_rect(Rect2(top_left + Vector2(0, BAR.y - fill), Vector2(BAR.x, fill)), colour)
	_canvas.draw_rect(frame, RIM, false, 2.0)
	_draw_centred(label, top_left + Vector2(BAR.x / 2.0, BAR.y + 22.0), 16, TICK)


## Text centred on a point, with a dark outline so it reads on any background.
func _draw_centred(text: String, where: Vector2, size: int, colour: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var base := where + Vector2(-width / 2.0, size * 0.35)
	_canvas.draw_string_outline(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color.BLACK)
	_canvas.draw_string(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)
