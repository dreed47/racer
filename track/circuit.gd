class_name Circuit
extends Node3D
## A closed circuit built in code from straights and arcs: road with collision, edge lines,
## a start line, a spawn point and timing gates. Knows nothing about game modes.
## Surfaces tell the wheels how grippy they are through "grip" and "rolling_resistance"
## metadata on their bodies. The road gets them here; set them on the ground in the scene.

## Distance between centreline samples, in metres.
const SAMPLE_STEP := 2.0
const EDGE_LINE_WIDTH := 0.25
## Height of the painted lines above the road, so they don't flicker.
const PAINT_HEIGHT := 0.01
const ROAD_COLOR := Color(0.24, 0.24, 0.26)
const PAINT_COLOR := Color(0.92, 0.92, 0.9)
const DARK_COLOR := Color(0.08, 0.08, 0.08)

## Name that keeps each track's best laps apart.
@export var track_id := "loop_1"
@export_range(6, 20, 0.5) var road_width := 10.0
@export_range(0.5, 2, 0.01) var road_grip := 1.0
## Pieces in driving order, starting at this node and heading along -Z.
## Vector2(length, 0) is a straight. Vector2(radius, degrees) is an arc; positive degrees turn right.
## The last piece must end where the first one starts.
@export var pieces := PackedVector2Array()
## Where the start/finish line is, as a distance along the lap from the first piece.
@export var start_distance := 60.0
## Hidden checkpoints, spread evenly around the lap. A lap counts only after all of them.
@export_range(1, 20) var checkpoints := 6
## How far before the start line the car is placed, so it gets a running start.
@export var spawn_back := 30.0

var _points := PackedVector3Array()  # Centreline in local space. The last point joins the first.
var _distances := PackedFloat64Array()  # Distance along the lap at each point.
var _length := 0.0
var _gap := 0.0
var _heading_gap := 0.0


func _ready() -> void:
	_trace()
	_build()


## Lap length in metres.
func lap_length() -> float:
	return _length


## How far the end of the last piece misses the start, in metres. Should be near 0.
func closure_gap() -> float:
	return _gap


## How far the heading at the end misses the start heading, in radians. Should be near 0.
func heading_gap() -> float:
	return _heading_gap


## Centreline point at a distance along the lap, in world space.
func point_at(distance: float) -> Vector3:
	return to_global(_local_point(distance))


## Driving direction at a distance along the lap, in world space.
func direction_at(distance: float) -> Vector3:
	var ahead := _local_point(distance + 1.0) - _local_point(distance - 1.0)
	return (global_basis * ahead).normalized()


## Start/finish line is gate 0. Checkpoints follow, in driving order.
func gate_count() -> int:
	return checkpoints + 1


## Gate position, facing the driving direction (-Z forward), in world space.
func gate(index: int) -> Transform3D:
	var distance := start_distance + index * _length / gate_count()
	var forward := direction_at(distance)
	return Transform3D(Basis.looking_at(forward, Vector3.UP), point_at(distance))


## Half the width a gate covers, measured from the centreline.
func gate_half_width() -> float:
	return road_width / 2.0


func _trace() -> void:
	_points.clear()
	_distances.clear()
	var p := Vector3.ZERO
	var heading := 0.0
	var distance := 0.0
	_points.append(p)
	_distances.append(0.0)
	for piece in pieces:
		var arc := piece.y != 0.0
		var turn := deg_to_rad(piece.y)
		var piece_length := piece.x * absf(turn) if arc else piece.x
		var steps := maxi(1, ceili(piece_length / SAMPLE_STEP))
		var step_turn := turn / steps
		var chord := 2.0 * piece.x * sin(absf(step_turn) / 2.0) if arc else piece_length / steps
		for i in steps:
			p += _direction(heading + step_turn / 2.0) * chord
			heading += step_turn
			distance += piece_length / steps
			_points.append(p)
			_distances.append(distance)
	_length = distance
	_gap = p.distance_to(Vector3.ZERO)
	_heading_gap = absf(wrapf(heading, -PI, PI))
	# The last point should sit on the first one, so drop it and let the loop wrap.
	_points.remove_at(_points.size() - 1)
	_distances.remove_at(_distances.size() - 1)


func _local_point(distance: float) -> Vector3:
	var d := fposmod(distance, _length)
	var i := clampi(_distances.bsearch(d, false) - 1, 0, _points.size() - 1)
	var j := (i + 1) % _points.size()
	var d_next := _distances[j] if j > 0 else _length
	var t := (d - _distances[i]) / (d_next - _distances[i])
	return _points[i].lerp(_points[j], t)


func _build() -> void:
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var half := road_width / 2.0
	var n := _points.size()
	for i in n:
		var j := (i + 1) % n
		var a := _points[i]
		var b := _points[j]
		var side_a := _right(i)
		var side_b := _right(j)
		var road := _quad(paint, a - side_a * half, a + side_a * half, b - side_b * half, b + side_b * half,
				ROAD_COLOR, 0.0)
		faces.append_array(road)
		var inner := half - EDGE_LINE_WIDTH
		_quad(paint, a - side_a * half, a - side_a * inner, b - side_b * half, b - side_b * inner,
				PAINT_COLOR, PAINT_HEIGHT)
		_quad(paint, a + side_a * inner, a + side_a * half, b + side_b * inner, b + side_b * half,
				PAINT_COLOR, PAINT_HEIGHT)
	_start_line(paint)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RoadMesh"
	mesh_instance.mesh = paint.commit()
	mesh_instance.material_override = material
	add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "Road"
	body.set_meta("grip", road_grip)
	body.set_meta("rolling_resistance", 0.0)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

	var spawn := Marker3D.new()
	spawn.name = "Spawn"
	var spawn_distance := start_distance - spawn_back
	spawn.transform = Transform3D(Basis.looking_at(_local_point(spawn_distance + 1.0)
			- _local_point(spawn_distance - 1.0), Vector3.UP), _local_point(spawn_distance) + Vector3.UP * 0.8)
	add_child(spawn)


## Checkered start/finish line: two rows of squares across the road.
func _start_line(paint: SurfaceTool) -> void:
	var centre := _local_point(start_distance)
	var forward := (_local_point(start_distance + 1.0) - _local_point(start_distance - 1.0)).normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var squares := int(road_width)
	var size := road_width / squares
	for row in 2:
		for k in squares:
			var colour := PAINT_COLOR if (row + k) % 2 == 0 else DARK_COLOR
			var back := centre + forward * size * (row - 1)
			var left := back + right * (k * size - road_width / 2.0)
			_quad(paint, left, left + right * size, left + forward * size, left + right * size + forward * size,
					colour, PAINT_HEIGHT * 2.0)


## One flat quad, from the back-left and back-right corners to the front ones.
## Returns its two triangles for collision.
func _quad(paint: SurfaceTool, back_left: Vector3, back_right: Vector3, front_left: Vector3,
		front_right: Vector3, colour: Color, height: float) -> PackedVector3Array:
	var lift := Vector3.UP * height
	var corners := PackedVector3Array([back_left, front_left, back_right, back_right, front_left, front_right])
	for k in corners.size():
		corners[k] += lift
		paint.set_color(colour)
		paint.set_normal(Vector3.UP)
		paint.add_vertex(corners[k])
	return corners


## Unit vector to the right of the driving direction at point i.
func _right(i: int) -> Vector3:
	var n := _points.size()
	var forward := (_points[(i + 1) % n] - _points[(i - 1 + n) % n]).normalized()
	return Vector3(-forward.z, 0.0, forward.x)


static func _direction(heading: float) -> Vector3:
	return Vector3(sin(heading), 0.0, -cos(heading))
