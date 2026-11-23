extends CanvasLayer
## Four tire boxes in the bottom-left corner, laid out like the car seen from above.
## Grey: gripping. Yellow: near the limit, where grip is highest. Red: sliding or spinning.
## "TC" lights up while traction control is cutting power, "ABS" while anti-lock brakes ease a
## wheel, and "SPIN" while anti-spin catches the back of the car.

## Slip levels (1 is the grip peak) where a box turns yellow, then red.
const NEAR_LIMIT := 0.8
const SLIDING := 1.2
const GRIP := Color(0.6, 0.6, 0.6)
const LIMIT := Color(1.0, 0.85, 0.2)
const SLIDE := Color(1.0, 0.25, 0.2)
const AIR := Color(0.2, 0.2, 0.2, 0.6)
const TIRE := Vector2(28, 48)
const GAP := Vector2(44, 70)

@export var car: Car

var _canvas: Control
var _tc: Label
var _abs: Label
var _spin: Label


func _ready() -> void:
	_canvas = Control.new()
	_canvas.anchor_top = 1.0
	_canvas.anchor_bottom = 1.0
	_canvas.offset_left = 24.0
	_canvas.offset_top = -(TIRE.y * 2.0 + GAP.y + 24.0)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_tires)
	add_child(_canvas)
	var x := TIRE.x * 2.0 + GAP.x + 16.0
	var middle := TIRE.y + GAP.y / 2.0 - 16.0
	_tc = _aid_label("TC", Vector2(x, middle))
	_abs = _aid_label("ABS", Vector2(x, middle - 36.0))
	_spin = _aid_label("SPIN", Vector2(x, middle + 36.0))


func _process(_delta: float) -> void:
	_tc.add_theme_color_override("font_color", LIMIT if car.traction_cut > 0.05 else AIR)
	_tc.visible = car.setup.traction_control and car.traction_allowed
	_abs.add_theme_color_override("font_color", LIMIT if car.abs_active else AIR)
	_abs.visible = car.abs_brakes
	_spin.add_theme_color_override("font_color", LIMIT if car.anti_spin_active else AIR)
	_spin.visible = car.anti_spin > 0.0
	_canvas.queue_redraw()


func _aid_label(text: String, where: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = where
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	_canvas.add_child(label)
	return label


static func colour_for(slip_level: float) -> Color:
	if slip_level >= SLIDING:
		return SLIDE
	if slip_level >= NEAR_LIMIT:
		return LIMIT
	return GRIP


func _draw_tires() -> void:
	if car == null or car.wheels.size() < 4:
		return
	# Order matches car.wheels: front left, front right, rear left, rear right.
	var spots := [Vector2(0, 0), Vector2(TIRE.x + GAP.x, 0),
			Vector2(0, TIRE.y + GAP.y), Vector2(TIRE.x + GAP.x, TIRE.y + GAP.y)]
	var body := Rect2(Vector2(TIRE.x / 2.0, TIRE.y / 2.0), Vector2(TIRE.x + GAP.x, TIRE.y + GAP.y))
	_canvas.draw_rect(body, Color(1, 1, 1, 0.25), false, 3.0)
	for i in 4:
		var wheel: Wheel = car.wheels[i]
		var colour := colour_for(wheel.slip_level) if wheel.on_ground else AIR
		var rect := Rect2(spots[i], TIRE)
		_canvas.draw_rect(rect, colour)
		_canvas.draw_rect(rect, Color.BLACK, false, 2.0)
