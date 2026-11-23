class_name TrackGuide
extends Node3D
## Help drawn on the road for the learning levels (see LearningLevel).
## LINE: a coloured line along the racing line ahead of the car. Green: you can speed up.
## Yellow: ease off, a slower part is coming. Red: brake now, or you won't slow in time.
## MARKERS: a red and white BRAKE board beside the road where each big slow-down starts,
## with white 100 and 50 boards that far before it.
## NONE: nothing.
## L turns the guide on and off whatever the level, until the game closes.

## Sent when L turns the guide on or off.
signal toggled(shown: bool)

enum { NONE, LINE, MARKERS }

## How many line points ahead the line shows. Points are about 4 m apart.
const AHEAD := 60
const BEHIND := 2
## Line width and height above the road, in metres.
const WIDTH := 0.5
const LIFT := 0.08
## Red when you are this much faster than you can still brake from, in m/s. Yellow within
## YELLOW_MARGIN below that.
const RED_MARGIN := 1.5
const YELLOW_MARGIN := 4.0
## A board goes up where the planned speed falls by at least this much, in m/s.
const BOARD_DROP := 4.2
## Count-down boards go up this many metres before each BRAKE board.
const COUNT_BOARDS: Array[int] = [100, 50]
const GREEN := Color(0.2, 0.85, 0.3)
const YELLOW := Color(1.0, 0.85, 0.1)
const RED := Color(0.95, 0.15, 0.1)

var car: Car
var track: Track
var line: RacingLine
var mode := NONE
## Line point the car is nearest. Set by LearningLevel each tick.
var progress := 0
## Where each brake board stands, as line point indexes. For tests.
var board_points: Array[int] = []
## Where each count-down board stands, as line point indexes, and its number. For tests.
var count_points: Array[int] = []
var count_labels: Array[String] = []
## False after L turns the guide off.
var shown := true

var _mesh := ImmediateMesh.new()
var _line_node := MeshInstance3D.new()
var _boards := Node3D.new()
var _ground := PackedFloat32Array()


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Seen from above whichever way the strip winds.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_node.mesh = _mesh
	_line_node.material_override = material
	_line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line_node)
	add_child(_boards)


## Redraws everything for the current mode and line speeds.
func rebuild() -> void:
	if not is_inside_tree():
		return
	for board in _boards.get_children():
		board.free()
	board_points.clear()
	count_points.clear()
	count_labels.clear()
	_mesh.clear_surfaces()
	_line_node.visible = mode == LINE
	if line == null or line.size() == 0:
		return
	if _ground.size() != line.size():
		_find_ground()
	if mode == MARKERS:
		_place_boards()


## Shows or hides the guide, whatever the level.
func toggle() -> void:
	shown = not shown
	visible = shown
	toggled.emit(shown)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_guide") and get_viewport().gui_get_focus_owner() == null:
		toggle()
	if not shown or mode != LINE or line == null or line.size() == 0 or car == null:
		return
	_draw_line()


## Colour for line point i, by how your speed compares with what you can still brake from.
func colour_at(i: int, metres: float, v: float) -> Color:
	var allowed := sqrt(line.speeds[i] * line.speeds[i] + 2.0 * line.brake_accel * maxf(metres, 0.0))
	if v > allowed + RED_MARGIN:
		return RED
	if v > allowed - YELLOW_MARGIN:
		return YELLOW
	return GREEN


func _draw_line() -> void:
	_mesh.clear_surfaces()
	var n := line.size()
	var v := car.forward_speed()
	var step := line.distance_at(1)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in range(-BEHIND, AHEAD):
		var i := posmod(progress + k, n)
		var colour := colour_at(i, k * step, v)
		# Fade in at the start and out at the far end.
		colour.a = clampf((k + BEHIND) / 3.0, 0.0, 1.0) * clampf((AHEAD - 1 - k) / 10.0, 0.0, 1.0) * 0.85
		var p := line.points[i]
		p.y = _ground[i] + LIFT
		var side := line.right(i) * WIDTH / 2.0
		_mesh.surface_set_color(colour)
		_mesh.surface_add_vertex(p - side)
		_mesh.surface_set_color(colour)
		_mesh.surface_add_vertex(p + side)
	_mesh.surface_end()


## Road height under each line point, from a ray down. Keeps the point's own height if
## the ray finds nothing.
func _find_ground() -> void:
	_ground.resize(line.size())
	for i in line.size():
		_ground[i] = _ground_at(line.points[i])


func _ground_at(where: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(where + Vector3.UP * 3.0, where + Vector3.DOWN * 5.0)
	if car != null:
		query.exclude = [car.get_rid()]
	var hit := space.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else where.y


## One board where each slow-down of at least BOARD_DROP starts: the last point before the
## speeds start falling, if they fall that much before they rise again.
func _place_boards() -> void:
	var n := line.size()
	var s := line.speeds
	for i in n:
		var before := s[posmod(i - 1, n)]
		var after := s[(i + 1) % n]
		if not (after < s[i] - 0.01 and before <= s[i] + 0.01):
			continue
		var lowest := s[i]
		var j := (i + 1) % n
		while s[j] <= lowest + 0.01 and j != i:
			lowest = minf(lowest, s[j])
			j = (j + 1) % n
		if s[i] - lowest >= BOARD_DROP:
			board_points.append(i)
	var step := line.distance_at(1)
	for k in board_points.size():
		var i := board_points[k]
		# Boards go on the outside of the line, where they're easy to see.
		var side := 1.0 if line.offsets[i] >= 0.0 else -1.0
		_add_board(i, side, "BRAKE", RED, Color.WHITE)
		# Count-down boards, unless the last slow-down is still going on there.
		var gap := posmod(i - board_points[k - 1], n) if board_points.size() > 1 else n
		for metres in COUNT_BOARDS:
			var back := roundi(metres / step)
			if back < gap - 2:
				var j := posmod(i - back, n)
				count_points.append(j)
				count_labels.append(str(metres))
				_add_board(j, side, str(metres), Color.WHITE, Color.BLACK)


func _add_board(i: int, side: float, text: String, colour: Color, text_colour: Color) -> void:
	var half := track.gate_half_width() if track != null else 6.0
	var where := line.centre(i) + line.right(i) * side * (half + 1.0)
	where.y = _ground_at(where)
	var board := Node3D.new()
	_boards.add_child(board)
	# Facing back down the road, towards the driver coming.
	board.global_transform = Transform3D(Basis.looking_at(line.direction(i)), where)

	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.1, 1.2, 0.1)
	post.mesh = post_mesh
	post.position = Vector3(0, 0.6, 0)
	post.material_override = _flat(Color(0.85, 0.85, 0.85))
	board.add_child(post)

	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(1.6, 0.7, 0.05)
	panel.mesh = panel_mesh
	panel.position = Vector3(0, 1.5, 0)
	panel.material_override = _flat(colour)
	board.add_child(panel)

	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.004
	label.outline_size = 0
	label.modulate = text_colour
	label.position = Vector3(0, 1.5, 0.04)
	board.add_child(label)


static func _flat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	return m
