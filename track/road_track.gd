class_name RoadTrack
extends Track
## A track along real roads, built in code from a data file made by a tool such as
## tools/clarion/build_track.py: road with painted lines, grass shoulders, bridges with rails,
## hilly ground, box buildings and trees. See README.md, "Clarion loop".

const EDGE_LINE_WIDTH := 0.25
const CENTRE_LINE_WIDTH := 0.15
## Centre line dashes: this many points painted, then this many left bare (points are 2 m apart).
const DASH_POINTS := 2
const GAP_POINTS := 3
## Height of the painted lines above the road, so they don't flicker.
const PAINT_HEIGHT := 0.01
const ROAD_COLOR := Color(0.24, 0.24, 0.26)
const PAINT_COLOR := Color(0.92, 0.92, 0.9)
const YELLOW_COLOR := Color(0.9, 0.75, 0.2)
const DARK_COLOR := Color(0.08, 0.08, 0.08)
const SHOULDER_COLOR := Color(0.25, 0.38, 0.18)
const RAIL_COLOR := Color(0.7, 0.7, 0.68)
const CONCRETE_COLOR := Color(0.55, 0.54, 0.5)
## Grass strip either side of the road, sloping down to the ground the data tool carved.
const SHOULDER_WIDTH := 4.0
const SHOULDER_DROP := 0.27
const RAIL_HEIGHT := 0.9
const RAIL_GAP := 0.3
const DECK_DEPTH := 1.6
## Smoothing passes over the saved centreline points. See _smooth_points().
const SMOOTH_PASSES := 8
## Road points in each mesh piece, so pieces out of view are skipped.
const CHUNK_POINTS := 125
## Terrain cells in each tile, each way. Tiles are square, as height map collision likes.
const TILE_CELLS := 64
const GRASS := {"grip": 0.6, "rolling_resistance": 0.06}
const SOLID := {"grip": 0.6, "rolling_resistance": 0.0}
const STUB_SHOULDER := 2.0
const SKIRT_DEPTH := 0.3
const BARRIER_ORANGE := Color(0.95, 0.42, 0.08)
const BARRIER_WHITE := Color(0.95, 0.95, 0.92)
const BARRICADE_WIDTH := 2.4
const BOARD_HEIGHTS: Array[float] = [0.55, 0.95]
const BOARD_DEPTH := 0.22
const STRIPE_WIDTH := 0.3
const CONE_AHEAD := 1.0
const BARRIER_BOX_HEIGHT := 1.5
const BARRIER_BOX_DEPTH := 1.6
const SIGN_GREEN := Color(0.05, 0.4, 0.22)
const SIGN_POST_COLOR := Color(0.6, 0.6, 0.6)
const SIGN_HEIGHT := 3.4  # Top of the street-name plate above the street.
const SIGN_PLATE_HEIGHT := 0.7  # Big enough to read at speed.
const SIGN_POST_WIDTH := 0.1
const SIGN_POST_SINK := 0.4
const SIGN_CHAR_WIDTH := 0.3  # Plate length per letter; matches SIGN_CHAR_WIDTH in build_track.py.
const SIGN_PLATE_PAD := 0.6  # Plate length past the words; matches SIGN_PLATE_PAD in build_track.py.
const SIGN_PIXEL_SIZE := 0.011
const BUILDING_COLORS: Array[Color] = [Color(0.62, 0.55, 0.48), Color(0.7, 0.68, 0.62), Color(0.5, 0.36, 0.3),
		Color(0.78, 0.76, 0.7), Color(0.45, 0.47, 0.5), Color(0.66, 0.6, 0.52)]

## The data file, as JSON. Its terrain heights sit next to it.
## Read as soon as it is set, so the road is known before the track is ready: nodes that
## come before it in the scene, or get ready first, can still ask about it.
@export_file("*.json") var data_path := "":
	set(value):
		data_path = value
		_loaded = _load()
@export_range(0.5, 2, 0.01) var road_grip := 1.0
## Where the start/finish line is, as a distance along the data's centreline.
@export var start_distance := 90.0
## Hidden checkpoints, spread evenly round the lap. A lap counts only after all of them.
## Each one is also a split time.
@export_range(1, 20) var checkpoints := 3
## How far before the start line the car is placed, so it gets a running start.
@export var spawn_back := 30.0
## Ground material, so the ground shows speed.
@export var grass_material: Material

var _points := PackedVector3Array()  # Centreline in local space. The last point joins the first.
var _distances := PackedFloat64Array()
var _bridge := PackedByteArray()  # 1 where the point is on a bridge.
var _length := 0.0
var _half := 6.0
var _data := {}
var _loaded := false
var _heights := PackedFloat32Array()
var _cell := 10.0
var _x0 := 0.0
var _z0 := 0.0
var _width := 0
var _depth := 0


func _ready() -> void:
	if not _loaded:
		return
	_build_road()
	_build_side_streets()
	_build_terrain()
	_build_buildings()
	_build_trees()
	_add_spawn()


func lap_length() -> float:
	return _length


func start_line_distance() -> float:
	return start_distance


func point_at(distance: float) -> Vector3:
	return to_global(_local_point(distance))


func direction_at(distance: float) -> Vector3:
	var ahead := _local_point(distance + 1.0) - _local_point(distance - 1.0)
	return (global_basis * ahead).normalized()


func gate_count() -> int:
	return checkpoints + 1


func gate(index: int) -> Transform3D:
	var distance := start_distance + index * _length / gate_count()
	var forward := direction_at(distance)
	forward.y = 0.0
	return Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), point_at(distance))


func gate_half_width() -> float:
	return _half


## On a long road, a reset puts the car back on the road where it is, not at the start.
func reset_transform(near: Vector3) -> Transform3D:
	var local := to_local(near)
	var best := 0
	var best_distance := INF
	for i in _points.size():
		var d := _points[i].distance_squared_to(local)
		if d < best_distance:
			best_distance = d
			best = i
	return global_transform * _placement(_distances[best])


## Ground height at a local x, z, in local space.
func ground_height(x: float, z: float) -> float:
	var c := clampf((x - _x0) / _cell, 0.0, _width - 1.001)
	var r := clampf((z - _z0) / _cell, 0.0, _depth - 1.001)
	var c0 := int(c)
	var r0 := int(r)
	var fc := c - c0
	var fr := r - r0
	var top := lerpf(_height(c0, r0), _height(c0 + 1, r0), fc)
	var bottom := lerpf(_height(c0, r0 + 1), _height(c0 + 1, r0 + 1), fc)
	return lerpf(top, bottom, fr)


func _load() -> bool:
	_points.clear()
	_distances.clear()
	var text := FileAccess.get_file_as_string(data_path)
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("%s: can't read %s" % [track_id, data_path])
		return false
	_data = parsed
	_half = _data.road_half_width
	var flat: Array = _data.points
	for i in range(0, flat.size(), 3):
		_points.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
	_smooth_points()
	_bridge.resize(_points.size())
	_bridge.fill(0)
	for span in _data.bridges:
		for i in range(int(span[0]), int(span[1]) + 1):
			_bridge[i % _points.size()] = 1
	_length = 0.0
	for i in _points.size():
		_distances.append(_length)
		_length += _points[i].distance_to(_points[(i + 1) % _points.size()])

	var terrain: Dictionary = _data.terrain
	_cell = terrain.cell
	_x0 = terrain.x0
	_z0 = terrain.z0
	_width = int(terrain.width)
	_depth = int(terrain.depth)
	var bytes := FileAccess.get_file_as_bytes(data_path.get_base_dir().path_join(terrain.file))
	_heights = bytes.to_float32_array()
	if _heights.size() != _width * _depth:
		push_error("%s: terrain heights don't match the data file" % track_id)
		return false
	return true


## Evens out the 1 cm rounding in the saved points. Left in, it makes small kinks every
## 2 m that shake the car at speed. A few passes move the road by millimetres only.
func _smooth_points() -> void:
	var n := _points.size()
	for pass_number in SMOOTH_PASSES:
		var before := _points.duplicate()
		for i in n:
			_points[i] = (before[(i - 1 + n) % n] + 2.0 * before[i] + before[(i + 1) % n]) / 4.0


func _height(c: int, r: int) -> float:
	return _heights[clampi(r, 0, _depth - 1) * _width + clampi(c, 0, _width - 1)]


func _local_point(distance: float) -> Vector3:
	var d := fposmod(distance, _length)
	var i := clampi(_distances.bsearch(d, false) - 1, 0, _points.size() - 1)
	var j := (i + 1) % _points.size()
	var d_next := _distances[j] if j > 0 else _length
	var t := (d - _distances[i]) / (d_next - _distances[i])
	return _points[i].lerp(_points[j], t)


## Where a car goes at a distance along the lap: on the road, facing the driving direction.
func _placement(distance: float) -> Transform3D:
	var forward := _local_point(distance + 1.0) - _local_point(distance - 1.0)
	return Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP),
			_local_point(distance) + Vector3.UP * 0.8)


## Unit vector to the right of the driving direction at point i, kept level.
func _right(i: int) -> Vector3:
	var n := _points.size()
	var forward := _points[(i + 1) % n] - _points[(i - 1 + n) % n]
	return Vector3(-forward.z, 0.0, forward.x).normalized()


func _build_road() -> void:
	var n := _points.size()
	var road_faces := PackedVector3Array()
	var shoulder_faces := PackedVector3Array()
	var rail_faces := PackedVector3Array()
	var paint: SurfaceTool = null
	var chunk := 0
	var inner := _half - EDGE_LINE_WIDTH
	var outer := _half + SHOULDER_WIDTH
	var down := Vector3.DOWN * SHOULDER_DROP
	# Where a side street joins, the road's edge stays open: no edge line and no grass shoulder.
	var cuts: Dictionary = _data.get("mouth_cuts", {})
	var open_left := {}
	var open_right := {}
	for k in cuts.get("left", []):
		open_left[int(k)] = true
	for k in cuts.get("right", []):
		open_right[int(k)] = true
	for i in n:
		if i % CHUNK_POINTS == 0:
			if paint:
				_add_mesh("Road%d" % chunk, paint)
				chunk += 1
			paint = SurfaceTool.new()
			paint.begin(Mesh.PRIMITIVE_TRIANGLES)
		var j := (i + 1) % n
		var a := _points[i]
		var b := _points[j]
		var ra := _right(i)
		var rb := _right(j)
		road_faces.append_array(_quad(paint, a - ra * _half, a + ra * _half, b - rb * _half, b + rb * _half,
				ROAD_COLOR, 0.0))
		# The edge line stays solid past side streets, as on the real road.
		_quad(paint, a - ra * _half, a - ra * inner, b - rb * _half, b - rb * inner, PAINT_COLOR, PAINT_HEIGHT)
		_quad(paint, a + ra * inner, a + ra * _half, b + rb * inner, b + rb * _half, PAINT_COLOR, PAINT_HEIGHT)
		if i % (DASH_POINTS + GAP_POINTS) < DASH_POINTS:
			var w := CENTRE_LINE_WIDTH / 2.0
			_quad(paint, a - ra * w, a + ra * w, b - rb * w, b + rb * w, YELLOW_COLOR, PAINT_HEIGHT)
		if _bridge[i] or _bridge[j]:
			# Rails to stop the car going over, and the side of the deck below the road.
			for side in [-1.0, 1.0]:
				var ea: Vector3 = a + ra * side * (_half + RAIL_GAP)
				var eb: Vector3 = b + rb * side * (_half + RAIL_GAP)
				rail_faces.append_array(_wall(paint, ea, eb, RAIL_HEIGHT, RAIL_COLOR))
				_wall(paint, a + ra * side * _half + Vector3.DOWN * DECK_DEPTH,
						b + rb * side * _half + Vector3.DOWN * DECK_DEPTH, DECK_DEPTH, CONCRETE_COLOR)
			if i % 20 == 0:
				_add_pillar(a)
		else:
			if not open_left.has(i):
				shoulder_faces.append_array(_quad(paint, a - ra * outer + down, a - ra * _half,
						b - rb * outer + down, b - rb * _half, SHOULDER_COLOR, -0.02))
			if not open_right.has(i):
				shoulder_faces.append_array(_quad(paint, a + ra * _half, a + ra * outer + down,
						b + rb * _half, b + rb * outer + down, SHOULDER_COLOR, -0.02))
	_start_line(paint)
	_add_mesh("Road%d" % chunk, paint)
	_add_body("Road", road_faces, {"grip": road_grip, "rolling_resistance": 0.0})
	_add_body("Shoulder", shoulder_faces, GRASS)
	_add_body("Rail", rail_faces, SOLID)


## Short pieces of the streets that meet the loop, each closed by striped barricades and cones.
## The stub road is drivable up to the barricades, which stop the car like a wall.
func _build_side_streets() -> void:
	var list: Array = _data.get("side_streets", [])
	if list.is_empty():
		return
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var road_faces := PackedVector3Array()
	var shoulder_faces := PackedVector3Array()
	var barrier_body := _body("Barriers", SOLID)
	var posts: Array[Transform3D] = []
	var cones: Array[Transform3D] = []
	var down := Vector3.DOWN * SHOULDER_DROP
	for stub: Dictionary in list:
		var flat: Array = stub.edges
		var lefts := PackedVector3Array()
		var rights := PackedVector3Array()
		for k in range(0, flat.size(), 6):
			lefts.append(Vector3(flat[k], flat[k + 1], flat[k + 2]))
			rights.append(Vector3(flat[k + 3], flat[k + 4], flat[k + 5]))
		var shoulder_from := int(stub.shoulder_from)
		# Rounded paved corners between the stub and the loop's edge.
		var corner_reach := [0.0, 0.0]
		for corner: Dictionary in stub.get("corners", []):
			corner_reach[int(corner.side)] = float(corner.reach)
			var strip: Array = corner.strip
			for k in range(0, strip.size() - 6, 6):
				var o0 := Vector3(strip[k], strip[k + 1], strip[k + 2])
				var i0 := Vector3(strip[k + 3], strip[k + 4], strip[k + 5])
				var o1 := Vector3(strip[k + 6], strip[k + 7], strip[k + 8])
				var i1 := Vector3(strip[k + 9], strip[k + 10], strip[k + 11])
				# Corners on the two sides mirror each other; keep every quad facing up.
				if (i0 - o0).cross(o1 - o0).y > 0.0:
					road_faces.append_array(_quad(paint, o0, i0, o1, i1, ROAD_COLOR, 0.0))
				else:
					road_faces.append_array(_quad(paint, i0, o0, i1, o1, ROAD_COLOR, 0.0))
		for k in lefts.size() - 1:
			var bl := lefts[k]
			var br := rights[k]
			var fl := lefts[k + 1]
			var fr := rights[k + 1]
			road_faces.append_array(_quad(paint, bl, br, fl, fr, ROAD_COLOR, 0.0))
			if k < shoulder_from:
				# Near the loop the stub can sit a little above the ground; a grass-coloured skirt hides the gap.
				# No skirt where a paved corner meets that edge.
				var along := (k + 1) * float(_data.get("step", 2.0))
				if along > corner_reach[0]:
					_wall(paint, bl + Vector3.DOWN * SKIRT_DEPTH, fl + Vector3.DOWN * SKIRT_DEPTH, SKIRT_DEPTH,
							SHOULDER_COLOR)
				if along > corner_reach[1]:
					_wall(paint, br + Vector3.DOWN * SKIRT_DEPTH, fr + Vector3.DOWN * SKIRT_DEPTH, SKIRT_DEPTH,
							SHOULDER_COLOR)
				continue
			var out_b := (br - bl).normalized() * STUB_SHOULDER
			var out_f := (fr - fl).normalized() * STUB_SHOULDER
			shoulder_faces.append_array(_quad(paint, bl - out_b + down, bl, fl - out_f + down, fl,
					SHOULDER_COLOR, -0.02))
			shoulder_faces.append_array(_quad(paint, br, br + out_b + down, fr, fr + out_f + down,
					SHOULDER_COLOR, -0.02))
		_add_barrier(paint, barrier_body, stub, posts, cones)
		_add_name_sign(paint, stub)
	_add_mesh("SideStreetMesh", paint)
	_add_body("SideStreets", road_faces, {"grip": road_grip, "rolling_resistance": 0.0})
	_add_body("SideShoulders", shoulder_faces, GRASS)

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.1, 1.2, 0.1)
	var post_multimesh := _multimesh(post_mesh, posts.size())
	for k in posts.size():
		post_multimesh.set_instance_transform(k, posts[k])
	_add_multimesh("BarrierPosts", post_multimesh, BARRIER_WHITE)
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.04
	cone_mesh.bottom_radius = 0.2
	cone_mesh.height = 0.7
	cone_mesh.radial_segments = 8
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.1
	band_mesh.bottom_radius = 0.13
	band_mesh.height = 0.15
	band_mesh.radial_segments = 8
	var cone_multimesh := _multimesh(cone_mesh, cones.size())
	var band_multimesh := _multimesh(band_mesh, cones.size())
	for k in cones.size():
		cone_multimesh.set_instance_transform(k, cones[k].translated(Vector3.UP * 0.35))
		band_multimesh.set_instance_transform(k, cones[k].translated(Vector3.UP * 0.42))
	_add_multimesh("Cones", cone_multimesh, BARRIER_ORANGE)
	_add_multimesh("ConeBands", band_multimesh, BARRIER_WHITE)


## Three barricades across one stub, cones in front of them, a sign, and one solid box
## around it all so the car stops there.
func _add_barrier(paint: SurfaceTool, body: StaticBody3D, stub: Dictionary, posts: Array[Transform3D],
		cones: Array[Transform3D]) -> void:
	var b: Array = stub.barrier
	var foot := Vector3(b[0], b[1], b[2])
	var toward_loop := Vector3(b[3], 0.0, b[4]).normalized()
	var right := Vector3(-toward_loop.z, 0.0, toward_loop.x)
	var half := float(stub.half_width)
	var spacing := (half * 2.0 - BARRICADE_WIDTH) / 2.0
	for slot in [-1.0, 0.0, 1.0]:
		var centre: Vector3 = foot + right * slot * spacing
		var left_end := centre - right * BARRICADE_WIDTH / 2.0
		for side in [0.15, BARRICADE_WIDTH - 0.15]:
			posts.append(Transform3D(Basis.IDENTITY, left_end + right * side + Vector3.UP * 0.6))
		for height in BOARD_HEIGHTS:
			_striped_board(paint, left_end + Vector3.UP * height, right, toward_loop)
	for k in 4:
		var across := (k - 1.5) * half * 0.5
		cones.append(Transform3D(Basis.IDENTITY, foot + toward_loop * CONE_AHEAD + right * across))

	var sign_label := Label3D.new()
	sign_label.text = "ROAD CLOSED"
	sign_label.font_size = 48
	sign_label.pixel_size = 0.006
	sign_label.modulate = DARK_COLOR
	sign_label.outline_modulate = BARRIER_WHITE
	sign_label.outline_size = 24
	sign_label.position = foot + Vector3.UP * 1.45 + toward_loop * 0.05
	sign_label.basis = Basis(-right, Vector3.UP, toward_loop)
	add_child(sign_label)

	var shape := BoxShape3D.new()
	shape.size = Vector3(half * 2.0 + 1.0, BARRIER_BOX_HEIGHT, BARRIER_BOX_DEPTH)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(Basis(-right, Vector3.UP, toward_loop),
			foot + Vector3.UP * BARRIER_BOX_HEIGHT / 2.0 + toward_loop * (CONE_AHEAD / 2.0))
	body.add_child(collision)


## A green street-name sign on a post at the street's corner. The plate runs along the street,
## so drivers on the loop read it as they pass. The name is on both faces.
func _add_name_sign(paint: SurfaceTool, stub: Dictionary) -> void:
	var spot: Array = stub.get("sign_post", [])
	var text: String = stub.get("sign", "")
	if spot.is_empty() or text.is_empty():
		return
	var foot := Vector3(spot[0], spot[1], spot[2])
	var along := Vector3(spot[3], 0.0, spot[4]).normalized()
	var across := Vector3(-along.z, 0.0, along.x)
	var bottom := foot + Vector3.DOWN * SIGN_POST_SINK
	var post_top := foot + Vector3.UP * SIGN_HEIGHT
	var w := SIGN_POST_WIDTH / 2.0
	_wall(paint, bottom - along * w, bottom + along * w, SIGN_HEIGHT + SIGN_POST_SINK, SIGN_POST_COLOR)
	_wall(paint, bottom - across * w, bottom + across * w, SIGN_HEIGHT + SIGN_POST_SINK, SIGN_POST_COLOR)
	var length := SIGN_CHAR_WIDTH * text.length() + SIGN_PLATE_PAD
	var low := post_top + Vector3.DOWN * SIGN_PLATE_HEIGHT
	_wall(paint, low - along * length / 2.0, low + along * length / 2.0, SIGN_PLATE_HEIGHT, SIGN_GREEN)
	for side in [-1.0, 1.0]:
		var facing: Vector3 = across * side
		var label := Label3D.new()
		label.text = text
		label.font_size = 48
		label.pixel_size = SIGN_PIXEL_SIZE
		label.double_sided = false
		label.modulate = BARRIER_WHITE
		label.outline_size = 0
		label.position = low + Vector3.UP * SIGN_PLATE_HEIGHT / 2.0 + facing * 0.03
		label.basis = Basis(Vector3.UP.cross(facing), Vector3.UP, facing)
		add_child(label)


## One barricade board: slanted orange and white stripes from left_end along right.
func _striped_board(paint: SurfaceTool, left_end: Vector3, right: Vector3, normal: Vector3) -> void:
	var up := Vector3.UP * BOARD_DEPTH
	var slant := BOARD_DEPTH * 0.8
	var stripes := int(ceil(BARRICADE_WIDTH / STRIPE_WIDTH))
	for k in stripes:
		var u0 := k * STRIPE_WIDTH
		var u1 := minf(u0 + STRIPE_WIDTH, BARRICADE_WIDTH)
		# Bottom edge along the board, top edge shifted sideways for the slant, clipped to the ends.
		var b0 := left_end + right * u0
		var b1 := left_end + right * u1
		var t0 := left_end + right * minf(u0 + slant, BARRICADE_WIDTH) + up
		var t1 := left_end + right * minf(u1 + slant, BARRICADE_WIDTH) + up
		if k == 0:
			# The corner left of the first slanted stripe.
			_triangle(paint, b0, b0 + up, t0, normal, BARRIER_WHITE)
		var colour := BARRIER_ORANGE if k % 2 == 0 else BARRIER_WHITE
		_triangle(paint, b0, t0, b1, normal, colour)
		_triangle(paint, b1, t0, t1, normal, colour)


## One triangle facing normal; the shared material shows it from both sides.
func _triangle(paint: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, colour: Color) -> void:
	for corner in [a, b, c]:
		paint.set_color(colour)
		paint.set_normal(normal)
		paint.add_vertex(corner)


## A concrete pillar from under the deck down into the ground.
func _add_pillar(top: Vector3) -> void:
	var bottom := ground_height(top.x, top.z) - 1.0
	var height := top.y - DECK_DEPTH - bottom
	if height < 2.0:
		return
	var box := BoxMesh.new()
	box.size = Vector3(2.0, height, 2.0)
	var pillar := MeshInstance3D.new()
	pillar.mesh = box
	pillar.material_override = _plain_material(CONCRETE_COLOR)
	pillar.position = Vector3(top.x, bottom + height / 2.0, top.z)
	add_child(pillar)


## Checkered start/finish line: two rows of squares across the road.
func _start_line(paint: SurfaceTool) -> void:
	var centre := _local_point(start_distance)
	var forward := (_local_point(start_distance + 1.0) - _local_point(start_distance - 1.0)).normalized()
	var right := Vector3(-forward.z, 0.0, forward.x).normalized()
	var road_width := _half * 2.0
	var squares := int(road_width)
	var size := road_width / squares
	for row in 2:
		for k in squares:
			var colour := PAINT_COLOR if (row + k) % 2 == 0 else DARK_COLOR
			var back := centre + forward * size * (row - 1)
			var left := back + right * (k * size - _half)
			_quad(paint, left, left + right * size, left + forward * size, left + right * size + forward * size,
					colour, PAINT_HEIGHT * 2.0)


## One quad from the back-left and back-right corners to the front ones.
## Returns its two triangles for collision.
func _quad(paint: SurfaceTool, back_left: Vector3, back_right: Vector3, front_left: Vector3,
		front_right: Vector3, colour: Color, height: float) -> PackedVector3Array:
	var lift := Vector3.UP * height
	var corners := PackedVector3Array([back_left, front_left, back_right, back_right, front_left, front_right])
	var normal := (back_right - back_left).cross(front_left - back_left).normalized()
	if normal.y < 0.0:
		normal = -normal
	for k in corners.size():
		corners[k] += lift
		paint.set_color(colour)
		paint.set_normal(normal)
		paint.add_vertex(corners[k])
	return corners


## An upright strip from a to b, rising by height. Returns its triangles for collision.
func _wall(paint: SurfaceTool, a: Vector3, b: Vector3, height: float, colour: Color) -> PackedVector3Array:
	var up := Vector3.UP * height
	var corners := PackedVector3Array([a, a + up, b, b, a + up, b + up])
	var normal := (b - a).cross(Vector3.UP).normalized()
	for k in corners.size():
		paint.set_color(colour)
		paint.set_normal(normal)
		paint.add_vertex(corners[k])
	return corners


func _add_mesh(mesh_name: String, paint: SurfaceTool) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = paint.commit()
	mesh_instance.material_override = _vertex_material()
	add_child(mesh_instance)


func _add_body(body_name: String, faces: PackedVector3Array, surface: Dictionary) -> void:
	if faces.is_empty():
		return
	var body := _body(body_name, surface)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _body(body_name: String, surface: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.set_meta("grip", surface.grip)
	body.set_meta("rolling_resistance", surface.rolling_resistance)
	add_child(body)
	return body


var _shared_vertex_material: StandardMaterial3D


func _vertex_material() -> StandardMaterial3D:
	if _shared_vertex_material == null:
		_shared_vertex_material = StandardMaterial3D.new()
		_shared_vertex_material.vertex_color_use_as_albedo = true
		_shared_vertex_material.vertex_color_is_srgb = true
		_shared_vertex_material.roughness = 0.9
		_shared_vertex_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shared_vertex_material


func _plain_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material


## Ground in square tiles: a mesh to see and a height map to drive on for each.
func _build_terrain() -> void:
	var body := _body("Ground", GRASS)
	var tiles_x := ceili((_width - 1) / float(TILE_CELLS))
	var tiles_z := ceili((_depth - 1) / float(TILE_CELLS))
	var side := TILE_CELLS + 1
	for tz in tiles_z:
		for tx in tiles_x:
			var c0 := tx * TILE_CELLS
			var r0 := tz * TILE_CELLS
			var map := PackedFloat32Array()
			map.resize(side * side)
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			vertices.resize(side * side)
			normals.resize(side * side)
			for k in side:
				for i in side:
					var c := c0 + i
					var r := r0 + k
					var h := _height(c, r)
					map[k * side + i] = h / _cell
					vertices[k * side + i] = Vector3(_x0 + c * _cell, h, _z0 + r * _cell)
					var dx := _height(c + 1, r) - _height(c - 1, r)
					var dz := _height(c, r + 1) - _height(c, r - 1)
					normals[k * side + i] = Vector3(-dx, 2.0 * _cell, -dz).normalized()
			var indices := PackedInt32Array()
			for k in TILE_CELLS:
				for i in TILE_CELLS:
					var v := k * side + i
					indices.append_array([v, v + 1, v + side, v + 1, v + side + 1, v + side])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var tile := MeshInstance3D.new()
			tile.name = "Ground%d_%d" % [tx, tz]
			tile.mesh = mesh
			tile.material_override = grass_material
			add_child(tile)

			# The height map is centred on its shape; scaling it by the cell size scales the
			# heights too, which is why they were divided by it above.
			var shape := HeightMapShape3D.new()
			shape.map_width = side
			shape.map_depth = side
			shape.map_data = map
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.transform = Transform3D(Basis.from_scale(Vector3.ONE * _cell),
					Vector3(_x0 + (c0 + TILE_CELLS / 2.0) * _cell, 0.0, _z0 + (r0 + TILE_CELLS / 2.0) * _cell))
			body.add_child(collision)


func _build_buildings() -> void:
	var list: Array = _data.get("buildings", [])
	if list.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = BoxMesh.new()
	multimesh.instance_count = list.size()
	var body := _body("Buildings", SOLID)
	for i in list.size():
		var b: Array = list[i]
		# Centre x, z, yaw, length, width, base, height. Yaw turns length from +x towards +z.
		var basis := Basis(Vector3.UP, -float(b[2]))
		var centre := Vector3(b[0], float(b[5]) + float(b[6]) / 2.0, b[1])
		var size := Vector3(b[3], b[6], b[4])
		multimesh.set_instance_transform(i, Transform3D(basis.scaled_local(size), centre))
		multimesh.set_instance_color(i, BUILDING_COLORS[i % BUILDING_COLORS.size()])
		var box := BoxShape3D.new()
		box.size = size
		var collision := CollisionShape3D.new()
		collision.shape = box
		collision.transform = Transform3D(basis, centre)
		body.add_child(collision)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	var instance := MultiMeshInstance3D.new()
	instance.name = "BuildingMeshes"
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)


func _build_trees() -> void:
	var list: Array = _data.get("trees", [])
	if list.is_empty():
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.3
	trunk.height = 2.5
	trunk.radial_segments = 6
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 2.6
	crown.height = 7.0
	crown.radial_segments = 8
	var trunks := _multimesh(trunk, list.size())
	var crowns := _multimesh(crown, list.size())
	var body := _body("Trees", SOLID)
	var shape := CylinderShape3D.new()
	shape.radius = 0.4
	shape.height = 6.0
	for i in list.size():
		var t: Array = list[i]
		var s := float(t[3])
		var foot := Vector3(t[0], t[1], t[2])
		var basis := Basis.from_scale(Vector3.ONE * s)
		trunks.set_instance_transform(i, Transform3D(basis, foot + Vector3.UP * 1.0 * s))
		crowns.set_instance_transform(i, Transform3D(basis, foot + Vector3.UP * 5.5 * s))
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = foot + Vector3.UP * 2.0
		body.add_child(collision)
	_add_multimesh("TreeTrunks", trunks, Color(0.35, 0.25, 0.17))
	_add_multimesh("TreeCrowns", crowns, Color(0.13, 0.3, 0.12))


func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	return multimesh


func _add_multimesh(node_name: String, multimesh: MultiMesh, colour: Color) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = _plain_material(colour)
	add_child(instance)


func _add_spawn() -> void:
	var spawn := Marker3D.new()
	spawn.name = "Spawn"
	spawn.transform = _placement(start_distance - spawn_back)
	add_child(spawn)
