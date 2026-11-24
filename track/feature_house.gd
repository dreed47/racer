class_name FeatureHouse
extends Node3D
## One house on the Clarion detour, modelled in detail: a ranch with a white-sided garage,
## a recessed porch with columns, and a red brick wing with black shutters, under a gable roof.
## Built from the data file's "feature_house" entry. Local x runs along the house to the east,
## local z points out of the front, y is up from the floor.
## Two simple figures, the owners, stand by the door and wave.

## Driveway centre (along the house, x), width and height above the ground, in metres.
const DRIVE_X := -6.3
const DRIVE_WIDTH := 6.2
const DRIVE_LIFT := 0.06
const SKIN := Color(0.93, 0.76, 0.64)
const PANTS := Color(0.2, 0.24, 0.34)
const SHOES := Color(0.15, 0.13, 0.12)

const SIDING := Color(0.93, 0.93, 0.9)
const SIDING_LINE := Color(0.8, 0.8, 0.78)
const TRIM := Color(0.97, 0.97, 0.96)
const BRICK := Color(0.52, 0.2, 0.15)
const MORTAR := Color(0.62, 0.55, 0.5)
const FOUNDATION := Color(0.5, 0.5, 0.48)
const ROOF := Color(0.26, 0.26, 0.27)
const GLASS := Color(0.12, 0.15, 0.18)
const BLACK := Color(0.06, 0.06, 0.06)
const LAMP_GLASS := Color(0.95, 0.85, 0.55)
const CONCRETE := Color(0.62, 0.61, 0.58)
const ASPHALT := Color(0.2, 0.2, 0.21)
const MULCH := Color(0.12, 0.08, 0.06)
const LEAF := Color(0.22, 0.42, 0.12)
const FIR := Color(0.12, 0.3, 0.12)
const RED_LEAF := Color(0.42, 0.16, 0.16)

const EAVE := 2.7
const RIDGE := 5.0
const OVERHANG := 0.45
const PORCH_DEPTH := 1.8
const PORCH_FLOOR := 0.2

var _paint: SurfaceTool
var _faces := PackedVector3Array()
var _half := 9.5  # Half the length.
var _h := 5.0  # Half the depth; the front wall is at z = _h.
var _track: Node3D


## Places and builds the house. track is the RoadTrack it belongs to, for ground heights.
func build(data: Dictionary, track: Node3D, road_points: PackedVector3Array, road_half_width: float) -> void:
	_track = track
	name = "FeatureHouse"
	_half = float(data.length) / 2.0
	_h = float(data.depth) / 2.0
	var front := Vector3(data.front[0], 0.0, data.front[1]).normalized()
	var along := Vector3(front.z, 0.0, -front.x)
	transform = Transform3D(Basis(along, Vector3.UP, front), Vector3(data.x, data.floor, data.z))

	_paint = SurfaceTool.new()
	_paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	_walls()
	_garage()
	_porch()
	_brick_wing()
	_roof()
	_yard(road_points, road_half_width)
	var mesh := MeshInstance3D.new()
	mesh.name = "HouseMesh"
	mesh.mesh = _paint.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.85
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	add_child(mesh)
	_add_collision()
	_add_owners()


# Main box ------------------------------------------------------------------------------------


func _walls() -> void:
	var t := 0.2
	var low := -1.5  # Foundation runs into the ground, so a slope never shows a gap.
	# Back and the two ends.
	_box(Vector3(-_half, low, -_h), Vector3(_half, EAVE, -_h + t), SIDING)
	_box(Vector3(-_half, low, -_h), Vector3(-_half + t, EAVE, _h), SIDING)
	_box(Vector3(_half - t, low, -_h), Vector3(_half, EAVE, _h), BRICK)
	# Front: garage part, recessed porch wall, brick wing.
	_box(Vector3(-_half, low, _h - t), Vector3(-3.0, EAVE, _h), SIDING)
	_box(Vector3(-3.0, low, _h - PORCH_DEPTH - t), Vector3(3.0, EAVE, _h - PORCH_DEPTH), SIDING)
	_box(Vector3(3.0, low, _h - t), Vector3(_half, EAVE, _h), BRICK)
	# Porch side walls.
	_box(Vector3(-3.2, low, _h - PORCH_DEPTH), Vector3(-3.0, EAVE, _h), SIDING)
	_box(Vector3(3.0, low, _h - PORCH_DEPTH), Vector3(3.2, EAVE, _h), BRICK)
	# Grey foundation strip showing above the ground.
	for z in [_h + 0.005, -_h - 0.005]:
		var n := Vector3(0, 0, signf(z))
		_rect_z(-_half, _half, low, 0.15, z, n, FOUNDATION)
	for x in [-_half - 0.005, _half + 0.005]:
		_rect_x(-_h, _h, low, 0.15, x, Vector3(signf(x), 0, 0), FOUNDATION)
	# Siding lines on the white walls, brick courses on the red ones.
	for k in range(1, 13):
		var y := 0.15 + k * 0.2
		_rect_z(-_half, -3.0, y, y + 0.015, _h + 0.004, Vector3.BACK, SIDING_LINE)
		_rect_z(-3.0, 3.0, y, y + 0.015, _h - PORCH_DEPTH + 0.004, Vector3.BACK, SIDING_LINE)
		_rect_z(-_half, _half, y, y + 0.015, -_h - 0.004, Vector3.FORWARD, SIDING_LINE)
		_rect_x(-_h, _h, y, y + 0.015, -_half - 0.004, Vector3.LEFT, SIDING_LINE)
	var y := 0.22
	while y < EAVE:
		_rect_z(3.0, _half, y, y + 0.012, _h + 0.004, Vector3.BACK, MORTAR)
		_rect_x(-_h, _h, y, y + 0.012, _half + 0.004, Vector3.RIGHT, MORTAR)
		y += 0.075
	# A back window or two, so the house isn't blank from the far side.
	for x in [-5.0, 1.0, 6.0]:
		_window(x, 1.0, 1.2, 1.2, -_h - 0.01, -1.0, 3, 2, false)


func _garage() -> void:
	var left := -8.75
	var right := -3.85
	var top := 2.1
	var z := _h + 0.03
	_box(Vector3(left - 0.12, 0.0, _h), Vector3(right + 0.12, top + 0.12, _h + 0.02), TRIM)
	_box(Vector3(left, 0.0, _h), Vector3(right, top, z), TRIM)
	# Panel grooves, and the row of little windows near the top.
	for k in range(1, 4):
		var gy := k * top / 4.0
		_rect_z(left, right, gy - 0.015, gy + 0.015, z + 0.002, Vector3.BACK, SIDING_LINE)
	var pane_y := top * 0.75 + 0.15
	for pair in 4:
		var cx := lerpf(left, right, (pair + 0.5) / 4.0)
		for side in [-1.0, 1.0]:
			var px: float = cx + side * 0.16
			_rect_z(px - 0.12, px + 0.12, pane_y, pane_y + 0.18, z + 0.003, Vector3.BACK, GLASS)
	_wall_lamp(-9.15, 2.0, _h)
	_wall_lamp(-3.45, 2.0, _h)


func _porch() -> void:
	var back := _h - PORCH_DEPTH
	_box(Vector3(-3.0, -1.0, back), Vector3(3.0, PORCH_FLOOR, _h + 0.25), CONCRETE)
	# Columns and the beam they hold.
	for x in [-2.8, -0.55, 2.8]:
		_box(Vector3(x - 0.11, PORCH_FLOOR, _h - 0.25), Vector3(x + 0.11, EAVE, _h - 0.03), TRIM)
	_box(Vector3(-3.0, EAVE - 0.3, _h - 0.25), Vector3(3.0, EAVE, _h), TRIM)
	# Porch ceiling.
	_box(Vector3(-3.0, EAVE - 0.02, back), Vector3(3.0, EAVE, _h), TRIM)
	# Big front window, the door with its little arched light, and lanterns.
	_window(-1.75, 0.95, 1.6, 1.45, back + 0.01, 1.0, 4, 3, false)
	var door_l := 0.35
	var door_r := 1.3
	_box(Vector3(door_l - 0.1, PORCH_FLOOR, back), Vector3(door_r + 0.1, 2.32, back + 0.04), TRIM)
	_box(Vector3(door_l, PORCH_FLOOR, back), Vector3(door_r, 2.2, back + 0.07), Color(0.98, 0.98, 0.97))
	_rect_z(door_l + 0.25, door_r - 0.25, 1.92, 2.08, back + 0.072, Vector3.BACK, GLASS)
	for row in 2:
		var py := 0.5 + row * 0.8
		_rect_z(door_l + 0.12, door_r - 0.12, py, py + 0.6, back + 0.072, Vector3.BACK, Color(0.92, 0.92, 0.9))
	_box(Vector3(door_r - 0.2, 1.0, back + 0.07), Vector3(door_r - 0.14, 1.18, back + 0.1), BLACK)
	_wall_lamp(door_l - 0.35, 1.85, back)
	# House number on the column.
	var number := Label3D.new()
	number.text = "403"
	number.font_size = 64
	number.pixel_size = 0.004
	number.modulate = BLACK
	number.outline_size = 0
	number.position = Vector3(-0.55, 1.95, _h - 0.02)
	add_child(number)
	# Floor lanterns, and a black bistro table with two chairs.
	for x in [2.4, 2.65]:
		_box(Vector3(x - 0.09, PORCH_FLOOR, back + 0.25), Vector3(x + 0.09, PORCH_FLOOR + 0.38, back + 0.43), BLACK)
		_box(Vector3(x - 0.06, PORCH_FLOOR + 0.08, back + 0.24), Vector3(x + 0.06, PORCH_FLOOR + 0.3, back + 0.44),
				LAMP_GLASS)
	var table := Vector3(-1.75, PORCH_FLOOR, back + 0.55)
	_box(table + Vector3(-0.03, 0.0, -0.03), table + Vector3(0.03, 0.72, 0.03), BLACK)
	_box(table + Vector3(-0.3, 0.72, -0.3), table + Vector3(0.3, 0.75, 0.3), BLACK)
	for side in [-1.0, 1.0]:
		var c: Vector3 = table + Vector3(side * 0.6, 0.0, 0.05)
		for leg_x in [-0.17, 0.17]:
			for leg_z in [-0.17, 0.17]:
				var foot: Vector3 = c + Vector3(leg_x, 0.0, leg_z)
				_box(foot + Vector3(-0.015, 0.0, -0.015), foot + Vector3(0.015, 0.45, 0.015), BLACK)
		_box(c + Vector3(-0.2, 0.45, -0.2), c + Vector3(0.2, 0.48, 0.2), BLACK)
		var back_x: float = c.x + side * 0.19
		_box(Vector3(back_x - 0.015, c.y + 0.45, c.z - 0.2), Vector3(back_x + 0.015, c.y + 0.95, c.z + 0.2), BLACK)


func _brick_wing() -> void:
	for x in [4.95, 8.15]:
		_window(x, 0.9, 1.2, 1.35, _h + 0.01, 1.0, 3, 2, true)


func _roof() -> void:
	var slope := (RIDGE - EAVE) / _h
	var edge_z := _h + OVERHANG
	var edge_y := EAVE - OVERHANG * slope
	var x0 := -_half - 0.35
	var x1 := _half + 0.35
	# Shingles in strips, each a slightly different grey, as the real roof is streaked.
	var strips := 10
	for side in [-1.0, 1.0]:
		for k in strips:
			var t0 := float(k) / strips
			var t1 := float(k + 1) / strips
			var za: float = side * lerpf(edge_z, 0.0, t0)
			var zb: float = side * lerpf(edge_z, 0.0, t1)
			var ya := lerpf(edge_y, RIDGE, t0)
			var yb := lerpf(edge_y, RIDGE, t1)
			var shade := 1.0 + 0.08 * sin(k * 2.3 + side)
			var colour := Color(ROOF.r * shade, ROOF.g * shade, ROOF.b * shade)
			var a := Vector3(x0, ya, za)
			var b := Vector3(x1, ya, za)
			var c := Vector3(x1, yb, zb)
			var d := Vector3(x0, yb, zb)
			var n := (b - a).cross(d - a).normalized()
			if n.y < 0.0:
				n = -n
			_quad(a, b, c, d, n, colour)
		# Fascia and soffit along the eave.
		var z_out: float = side * edge_z
		_box(Vector3(x0, edge_y - 0.2, minf(z_out, z_out - side * 0.05)),
				Vector3(x1, edge_y + 0.02, maxf(z_out, z_out - side * 0.05)), TRIM)
		_rect_y(x0, x1, minf(side * _h, z_out), maxf(side * _h, z_out), edge_y - 0.2, TRIM)
	# Gable ends: the end walls carry on up to the ridge.
	for x in [-_half, _half]:
		var colour := SIDING if x < 0.0 else BRICK
		var n := Vector3(signf(x), 0, 0)
		var a := Vector3(x, EAVE, -_h)
		var b := Vector3(x, EAVE, _h)
		var top := Vector3(x, RIDGE, 0.0)
		_tri(a, b, top, n, colour)
		_tri(a + n * 0.01, b + n * 0.01, top + n * 0.01, n, colour)
		# Rake trim along the gable's two sloping edges.
		for z_end in [-edge_z, edge_z]:
			var e := Vector3(x + signf(x) * 0.35, edge_y, z_end)
			var r := Vector3(x + signf(x) * 0.35, RIDGE, 0.0)
			_quad(e, r, r + Vector3.DOWN * 0.18, e + Vector3.DOWN * 0.18, n, TRIM)
	# Chimney behind the ridge, a little west of centre.
	var cx := 0.4
	var cz := -1.2
	_box(Vector3(cx - 0.55, 3.2, cz - 0.4), Vector3(cx + 0.55, 6.2, cz + 0.4), BRICK)
	_box(Vector3(cx - 0.62, 6.2, cz - 0.47), Vector3(cx + 0.62, 6.3, cz + 0.47), CONCRETE)
	var y := 3.3
	while y < 6.2:
		_rect_z(cx - 0.55, cx + 0.55, y, y + 0.012, cz + 0.405, Vector3.BACK, MORTAR)
		_rect_x(cz - 0.4, cz + 0.4, y, y + 0.012, cx - 0.555, Vector3.LEFT, MORTAR)
		_rect_x(cz - 0.4, cz + 0.4, y, y + 0.012, cx + 0.555, Vector3.RIGHT, MORTAR)
		y += 0.075


# Yard ----------------------------------------------------------------------------------------


func _yard(road_points: PackedVector3Array, road_half_width: float) -> void:
	_driveway(road_points, road_half_width)
	# Front walk from the porch steps round to the driveway.
	_ground_strip(Vector2(0.8, _h + 0.2), Vector2(0.8, _h + 2.0), 1.0, CONCRETE, 0.05)
	_ground_strip(Vector2(1.3, _h + 1.95), Vector2(-3.2, _h + 2.25), 1.0, CONCRETE, 0.05)
	# Mulch beds along the front.
	_ground_strip(Vector2(-4.9, _h + 0.8), Vector2(-3.05, _h + 0.8), 1.6, MULCH, 0.03)
	_ground_strip(Vector2(-3.0, _h + 0.85), Vector2(0.3, _h + 0.85), 1.3, MULCH, 0.03)
	_ground_strip(Vector2(1.3, _h + 1.0), Vector2(_half + 0.4, _h + 1.0), 2.0, MULCH, 0.03)
	# Lamp post by the walk.
	var post := Vector3(-3.7, _ground(-3.7, _h + 3.0), _h + 3.0)
	_box(post + Vector3(-0.05, -0.3, -0.05), post + Vector3(0.05, 2.1, 0.05), BLACK)
	_box(post + Vector3(-0.14, 2.1, -0.14), post + Vector3(0.14, 2.5, 0.14), BLACK)
	_box(post + Vector3(-0.11, 2.14, -0.15), post + Vector3(0.11, 2.44, 0.15), LAMP_GLASS)
	_box(post + Vector3(-0.15, 2.14, -0.11), post + Vector3(0.15, 2.44, 0.11), LAMP_GLASS)
	_box(post + Vector3(-0.17, 2.5, -0.17), post + Vector3(0.17, 2.56, 0.17), BLACK)
	# Shrubs: round ones, two tall evergreens, a red-leafed one by the garage.
	var shrubs := [[-2.2, 0.85, 0.62], [-1.15, 0.85, 0.66], [2.0, 0.75, 0.5], [4.6, 0.9, 0.8], [6.5, 0.95, 0.6],
			[7.8, 1.0, 0.75], [9.1, 0.9, 0.55], [8.6, 2.1, 0.5], [5.6, 2.3, 0.45]]
	for s in shrubs:
		var shade := 0.85 + 0.3 * fposmod(s[0] * 0.37, 1.0)
		_shrub(s[0], _h + s[1], s[2], Color(LEAF.r * shade, LEAF.g * shade, LEAF.b * shade))
	_shrub(5.6, _h + 0.8, 0.55, RED_LEAF)
	_shrub(-4.3, _h + 0.9, 0.65, RED_LEAF)
	_evergreen(-3.4, _h + 0.6, 2.9)
	_evergreen(3.6, _h + 0.9, 2.5)


func _ground(x: float, z: float) -> float:
	var world := transform * Vector3(x, 0.0, z)
	return _track.ground_height(world.x, world.z) - transform.origin.y


## The driveway: from the garage straight out to the road's edge line, its end cut to the road's
## angle. Near the road it rises with the grass shoulder (which sits above the ground), so the
## shoulder never hides it, and it meets the road at the road's own height.
func _driveway(road_points: PackedVector3Array, road_half_width: float) -> void:
	var road := PackedVector3Array()
	for p in road_points:
		var local := transform.affine_inverse() * p
		if Vector2(local.x, local.z).length() < 80.0:  # Only the road in front of the house.
			road.append(local)
	var columns := 6
	var ends: Array[Vector2] = []  # For each column across the drive: z of its end, road height there.
	for c in columns + 1:
		var x := DRIVE_X - DRIVE_WIDTH / 2.0 + DRIVE_WIDTH * c / columns
		ends.append(_road_edge(road, x, road_half_width))
	var rows := maxi(1, ceili((ends[columns / 2].x - _h) / 0.75))
	var grid: Array[PackedVector3Array] = []
	for c in columns + 1:
		var x := DRIVE_X - DRIVE_WIDTH / 2.0 + DRIVE_WIDTH * c / columns
		var line := PackedVector3Array()
		for r in rows + 1:
			var z := lerpf(_h, ends[c].x, float(r) / rows)
			var y := _ground(x, z) + DRIVE_LIFT
			if not is_nan(ends[c].y):
				# Shoulder slope (0.27 m over 4 m), carried on down until it meets the ground.
				y = maxf(y, ends[c].y + DRIVE_LIFT - (ends[c].x - z) * 0.0675)
			line.append(Vector3(x, y, z))
		grid.append(line)
	for c in columns:
		for r in rows:
			_quad(grid[c][r], grid[c + 1][r], grid[c + 1][r + 1], grid[c][r + 1], Vector3.UP, ASPHALT)


## Where a line straight out from the house at x first reaches the road's edge: (z, road height).
## Height is NAN if no road is near, and z is then a short default.
func _road_edge(road: PackedVector3Array, x: float, half: float) -> Vector2:
	var z := _h
	while z < _h + 60.0:
		var here := Vector2(x, z)
		for k in road.size() - 1:
			var a := Vector2(road[k].x, road[k].z)
			var b := Vector2(road[k + 1].x, road[k + 1].z)
			var ab := b - a
			if ab.length_squared() > 25.0:
				continue  # A gap where road far from the house was left out.
			var t := clampf((here - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if here.distance_to(a + ab * t) <= half - 0.05:
				return Vector2(z, lerpf(road[k].y, road[k + 1].y, t))
		z += 0.1
	return Vector2(_h + 8.0, NAN)


## A flat strip lying on the ground from a to b (x, z), width wide.
func _ground_strip(a: Vector2, b: Vector2, width: float, colour: Color, lift: float) -> void:
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x) * width / 2.0
	var steps := maxi(1, ceili(a.distance_to(b) / 1.5))
	for k in steps:
		var p0 := a.lerp(b, float(k) / steps)
		var p1 := a.lerp(b, float(k + 1) / steps)
		var corners: Array[Vector3] = []
		for p in [p0 - side, p0 + side, p1 + side, p1 - side]:
			corners.append(Vector3(p.x, _ground(p.x, p.y) + lift, p.y))
		_quad(corners[0], corners[1], corners[2], corners[3], Vector3.UP, colour)


func _shrub(x: float, z: float, radius: float, colour: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 1.8
	sphere.radial_segments = 12
	sphere.rings = 6
	var shrub := MeshInstance3D.new()
	shrub.mesh = sphere
	shrub.material_override = _material(colour)
	shrub.position = Vector3(x, _ground(x, z) + radius * 0.8, z)
	add_child(shrub)


func _evergreen(x: float, z: float, height: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = height * 0.2
	cone.height = height
	cone.radial_segments = 10
	var tree := MeshInstance3D.new()
	tree.mesh = cone
	tree.material_override = _material(FIR)
	tree.position = Vector3(x, _ground(x, z) + height / 2.0, z)
	add_child(tree)


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.95
	return material


# Owners --------------------------------------------------------------------------------------


## The owners' photo, cut out, standing on the porch behind the shrubs. Only if the local file is there.
func _add_owners() -> void:
	var owners := Node3D.new()
	owners.name = "Owners"
	owners.position = Vector3(0.8, PORCH_FLOOR, _h - 0.7)
	add_child(owners)
	# She is on the left in a turquoise top, he is on the right in a pink shirt.
	_person(owners, -0.24, 1.62, Color(0.1, 0.72, 0.85), Color(0.25, 0.17, 0.12), -1.0)
	_person(owners, 0.24, 1.8, Color(0.94, 0.52, 0.55), Color(0.92, 0.92, 0.9), 1.0)


## One rough figure, height tall, at x. Raises the outer arm (side -1 left, 1 right) to wave
## and puts the inner arm round the other person.
func _person(parent: Node3D, x: float, height: float, shirt: Color, hair: Color, side: float) -> void:
	var k := height / 1.75
	var body := Node3D.new()
	body.position = Vector3(x, 0.0, 0.0)
	parent.add_child(body)
	for leg in [-0.09, 0.09]:
		_part(body, _capsule(0.07 * k, 0.86 * k), Vector3(leg * k, 0.43 * k, 0.0), Vector3.ZERO, PANTS)
		_part(body, _box_mesh(Vector3(0.11, 0.07, 0.24) * k), Vector3(leg * k, 0.035, 0.05 * k), Vector3.ZERO, SHOES)
	_part(body, _capsule(0.17 * k, 0.68 * k), Vector3(0.0, 1.16 * k, 0.0), Vector3.ZERO, shirt)
	_part(body, _capsule(0.05 * k, 0.12 * k), Vector3(0.0, 1.5 * k, 0.0), Vector3.ZERO, SKIN)
	var head := SphereMesh.new()
	head.radius = 0.11 * k
	head.height = 0.25 * k
	_part(body, head, Vector3(0.0, 1.64 * k, 0.0), Vector3.ZERO, SKIN)
	var top := SphereMesh.new()
	top.radius = 0.115 * k
	top.height = 0.14 * k
	_part(body, top, Vector3(0.0, 1.71 * k, -0.015 * k), Vector3.ZERO, hair)
	if hair.r < 0.5:
		# Longer dark hair down to the shoulders.
		_part(body, _capsule(0.1 * k, 0.3 * k), Vector3(0.0, 1.56 * k, -0.05 * k), Vector3.ZERO, hair)
	# Waving arm: shoulder, elbow out to the side, hand up high.
	var shoulder := Vector3(side * 0.19 * k, 1.42 * k, 0.0)
	var elbow := shoulder + Vector3(side * 0.24 * k, 0.08 * k, 0.0)
	var wrist := elbow + Vector3(side * 0.05 * k, 0.28 * k, 0.0)
	_limb(body, shoulder, elbow, 0.05 * k, shirt)
	_limb(body, elbow, wrist, 0.045 * k, SKIN)
	var hand := SphereMesh.new()
	hand.radius = 0.055 * k
	hand.height = 0.11 * k
	_part(body, hand, wrist + Vector3(0.0, 0.04 * k, 0.0), Vector3.ZERO, SKIN)
	# Inner arm round the other person's back.
	var inner := Vector3(-side * 0.19 * k, 1.4 * k, 0.0)
	_limb(body, inner, inner + Vector3(-side * 0.34 * k, -0.12 * k, -0.12 * k), 0.05 * k, SKIN)


## A capsule from a to b, radius thick.
func _limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, colour: Color) -> void:
	var up := (b - a).normalized()
	var across := up.cross(Vector3.FORWARD)
	if across.length() < 0.01:
		across = up.cross(Vector3.RIGHT)
	across = across.normalized()
	var part := MeshInstance3D.new()
	part.mesh = _capsule(radius, a.distance_to(b) + radius * 2.0)
	part.material_override = _material(colour)
	part.transform = Transform3D(Basis(across, up, across.cross(up)), (a + b) / 2.0)
	parent.add_child(part)


func _part(parent: Node3D, mesh: Mesh, at: Vector3, rotation_xyz: Vector3, colour: Color) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _material(colour)
	part.position = at
	part.rotation = rotation_xyz
	parent.add_child(part)


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	capsule.radial_segments = 10
	capsule.rings = 3
	return capsule


func _box_mesh(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


# Collision -----------------------------------------------------------------------------------


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "FeatureHouseBody"
	body.set_meta("grip", 0.6)
	body.set_meta("rolling_resistance", 0.0)
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(_half * 2.0, EAVE + 2.0, _h * 2.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, (EAVE - 2.0) / 2.0, 0.0)
	body.add_child(collision)


# Drawing -------------------------------------------------------------------------------------


## A window facing out along z (facing is +1 for the front, -1 for the back), with a white frame,
## dark glass split into panes, and black shutters if asked.
func _window(cx: float, bottom: float, width: float, height: float, z: float, facing: float, cols: int,
		rows: int, shutters: bool) -> void:
	var n := Vector3(0, 0, facing)
	var out := facing * 0.01
	var l := cx - width / 2.0
	var r := cx + width / 2.0
	_box(Vector3(l - 0.1, bottom - 0.12, minf(z, z + facing * 0.06)),
			Vector3(r + 0.1, bottom + height + 0.1, maxf(z, z + facing * 0.06)), TRIM)
	var gz := z + facing * 0.065
	_rect_z(l, r, bottom, bottom + height, gz, n, GLASS)
	for c in range(1, cols):
		var x := lerpf(l, r, float(c) / cols)
		_rect_z(x - 0.02, x + 0.02, bottom, bottom + height, gz + out, n, TRIM)
	for row in range(1, rows):
		var y := lerpf(bottom, bottom + height, float(row) / rows)
		_rect_z(l, r, y - 0.02, y + 0.02, gz + out, n, TRIM)
	if shutters:
		for side in [-1.0, 1.0]:
			var sx: float = cx + side * (width / 2.0 + 0.38)
			_box(Vector3(sx - 0.24, bottom - 0.1, minf(z, z + facing * 0.05)),
					Vector3(sx + 0.24, bottom + height + 0.1, maxf(z, z + facing * 0.05)), BLACK)


func _wall_lamp(x: float, y: float, z: float) -> void:
	_box(Vector3(x - 0.04, y + 0.1, z), Vector3(x + 0.04, y + 0.16, z + 0.15), BLACK)
	_box(Vector3(x - 0.1, y - 0.15, z + 0.08), Vector3(x + 0.1, y + 0.2, z + 0.26), BLACK)
	_box(Vector3(x - 0.08, y - 0.1, z + 0.075), Vector3(x + 0.08, y + 0.14, z + 0.265), LAMP_GLASS)


## An axis-aligned box from corner lo to corner hi. Its faces are also collision only for the
## main walls, which the one big box shape covers anyway, so none are kept here.
func _box(lo: Vector3, hi: Vector3, colour: Color) -> void:
	_rect_x(lo.z, hi.z, lo.y, hi.y, lo.x, Vector3.LEFT, colour)
	_rect_x(lo.z, hi.z, lo.y, hi.y, hi.x, Vector3.RIGHT, colour)
	_rect_z(lo.x, hi.x, lo.y, hi.y, lo.z, Vector3.FORWARD, colour)
	_rect_z(lo.x, hi.x, lo.y, hi.y, hi.z, Vector3.BACK, colour)
	_rect_y(lo.x, hi.x, lo.z, hi.z, hi.y, colour)
	_rect_y(lo.x, hi.x, lo.z, hi.z, lo.y, colour, Vector3.DOWN)


func _rect_z(x0: float, x1: float, y0: float, y1: float, z: float, n: Vector3, colour: Color) -> void:
	_quad(Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z), n, colour)


func _rect_x(z0: float, z1: float, y0: float, y1: float, x: float, n: Vector3, colour: Color) -> void:
	_quad(Vector3(x, y0, z0), Vector3(x, y0, z1), Vector3(x, y1, z1), Vector3(x, y1, z0), n, colour)


func _rect_y(x0: float, x1: float, z0: float, z1: float, y: float, colour: Color, n := Vector3.UP) -> void:
	_quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), n, colour)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, colour: Color) -> void:
	_tri(a, b, c, n, colour)
	_tri(a, c, d, n, colour)


## One triangle, wound so its front face is the side normal n points to.
func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, colour: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var swap := b
		b = c
		c = swap
	for corner in [a, b, c]:
		_paint.set_color(colour)
		_paint.set_normal(n)
		_paint.add_vertex(corner)
