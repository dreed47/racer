class_name HouseKit
extends Node3D
## The neighbourhood's houses, modelled in six styles taken from photos of Clarion homes:
## split-level, porch colonial, gable-front, ranch with garage, garage colonial and plain ranch.
## Each house gets a style that fits its size and storeys, and colours from the town's usual
## siding, brick, shutters and roofs, all picked from its seed, so it looks the same every run.
##
## A house is built in its own frame: x along its front, y up from its ground floor, z out of
## its front. Houses are batched into one mesh per CHUNK square, with the small details in a
## second mesh that is only drawn up close. Wall and roof textures come from house.gdshader.

const SHADER := preload("res://track/house.gdshader")
const CHUNK := 250.0
const DETAIL_RANGE := 220.0
const STOREY := 2.75  # Floor to floor.
const OVERHANG := 0.35

enum Style { SPLIT_LEVEL, PORCH_COLONIAL, GABLE_FRONT, RANCH_GARAGE, GARAGE_COLONIAL, RANCH }
enum Tex { PLAIN, SIDING, BRICK, BOARD, SHINGLE, METAL, PANEL, GLASS }

const SIDINGS: Array[Color] = [Color(0.93, 0.93, 0.9), Color(0.92, 0.88, 0.74), Color(0.8, 0.72, 0.57),
		Color(0.7, 0.78, 0.85), Color(0.38, 0.29, 0.22)]
const BRICKS: Array[Color] = [Color(0.56, 0.25, 0.18), Color(0.62, 0.32, 0.23), Color(0.72, 0.6, 0.45)]
const SHUTTERS: Array[Color] = [Color(0.07, 0.07, 0.08), Color(0.12, 0.16, 0.3), Color(0.26, 0.27, 0.29)]
const ROOFS: Array[Color] = [Color(0.44, 0.44, 0.44), Color(0.22, 0.22, 0.24), Color(0.34, 0.25, 0.19)]
const METAL_ROOF := Color(0.55, 0.57, 0.58)
const BOARDS: Array[Color] = [Color(0.3, 0.23, 0.17), Color(0.24, 0.26, 0.29)]
const DOORS: Array[Color] = [Color(0.95, 0.95, 0.93), Color(0.08, 0.08, 0.09), Color(0.5, 0.13, 0.12),
		Color(0.14, 0.2, 0.34), Color(0.45, 0.3, 0.18)]
const TRIM := Color(0.95, 0.95, 0.93)
const GLASS := Color(0.1, 0.13, 0.17)
const FOUNDATION := Color(0.55, 0.54, 0.5)
const CONCRETE := Color(0.66, 0.65, 0.62)
const BLACK := Color(0.06, 0.06, 0.06)
const LAMP := Color(0.95, 0.85, 0.55)

## Vertices for one mesh, filled a quad at a time.
class Buffer:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = index
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m

var styles_built := {}  # Style name to count, for tests.
var _rng := RandomNumberGenerator.new()
var _basis := Basis()
var _origin := Vector3.ZERO
var _foot := -1.0  # Lowest ground under the house, below its floor.
var _yard := -0.3  # Ground a few metres out from the front, below the floor.
var _stoop := Vector3.ZERO  # Door x, slab top and outer edge z, where its steps start.
var _buf: Buffer
var _fine: Buffer
var _faces := PackedVector3Array()
# This house's colours.
var _siding := Color.WHITE
var _brick := Color.WHITE
var _shutter := Color.BLACK
var _roof := Color.GRAY
var _roof_tex := Tex.SHINGLE
var _door := Color.WHITE
var _shutters := true


## Builds every house in list (the "houses" from clarion.json; heights above the track's base,
## like every other y) and returns the faces of their walls and roofs, for the Buildings body.
func build(list: Array) -> PackedVector3Array:
	name = "Houses"
	_faces = PackedVector3Array()
	var chunks := {}
	for h: Dictionary in list:
		var key := Vector2i(floori(float(h.x) / CHUNK), floori(float(h.z) / CHUNK))
		if not chunks.has(key):
			chunks[key] = [Buffer.new(), Buffer.new()]
		_buf = chunks[key][0]
		_fine = chunks[key][1]
		_house(h)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	for key: Vector2i in chunks:
		for k in 2:
			var buffer: Buffer = chunks[key][k]
			if buffer.verts.is_empty():
				continue
			var part := MeshInstance3D.new()
			part.name = "%s%d_%d" % ["HouseDetail" if k == 1 else "HouseMesh", key.x, key.y]
			part.mesh = buffer.mesh()
			part.material_override = material
			if k == 1:
				part.visibility_range_end = DETAIL_RANGE
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(part)
	return _faces


func _house(h: Dictionary) -> void:
	_rng.seed = int(h.seed)
	var front := Vector3(float(h.front[0]), 0.0, float(h.front[1])).normalized()
	var along := Vector3(front.z, 0.0, -front.x)
	# Half the houses are built mirrored, so a wing or garage can be on either side.
	if _rng.randf() < 0.5:
		along = -along
	_basis = Basis(along, Vector3.UP, front)
	_origin = Vector3(float(h.x), float(h.floor), float(h.z))
	_foot = minf(float(h.foot) - float(h.floor), -0.3)
	_yard = clampf(float(h.get("yard", h.floor)) - float(h.floor), _foot, -0.3)
	var w := float(h.width)
	var d := float(h.depth)
	var storeys := int(h.storeys)
	_siding = SIDINGS[_rng.randi() % SIDINGS.size()]
	_brick = BRICKS[_rng.randi() % BRICKS.size()]
	_shutter = SHUTTERS[_rng.randi() % SHUTTERS.size()]
	_roof = ROOFS[_rng.randi() % ROOFS.size()]
	_roof_tex = Tex.SHINGLE
	_door = DOORS[_rng.randi() % DOORS.size()]
	_shutters = _rng.randf() < 0.65
	var style := _pick_style(w, d, storeys)
	styles_built[Style.keys()[style]] = styles_built.get(Style.keys()[style], 0) + 1
	match style:
		Style.SPLIT_LEVEL:
			_split_level(w, d)
		Style.PORCH_COLONIAL:
			_porch_colonial(w, d)
		Style.GABLE_FRONT:
			_gable_front(w, d, storeys)
		Style.RANCH_GARAGE:
			_ranch_garage(w, d)
		Style.GARAGE_COLONIAL:
			_garage_colonial(w, d)
		_:
			_ranch(w, d)
	_steps()


func _pick_style(w: float, d: float, storeys: int) -> Style:
	if storeys < 2:
		return Style.RANCH_GARAGE if w >= 13.0 and d >= 7.0 and _rng.randf() < 0.7 else Style.RANCH
	var options: Array[Style] = [Style.GABLE_FRONT]
	if w >= 10.0 and d >= 7.5:
		options.append(Style.PORCH_COLONIAL)
	if w >= 13.0 and d >= 7.0:
		options.append(Style.SPLIT_LEVEL)
	if w >= 15.0 and d >= 7.0:
		options.append(Style.GARAGE_COLONIAL)
	return options[_rng.randi() % options.size()]


# Styles --------------------------------------------------------------------------------------


## Two-storey block at one end, brick below and siding above, with a one-storey wing holding the
## front door under a porch, and a garage at the wing's far end when there's room.
func _split_level(w: float, d: float) -> void:
	var hw := w / 2.0
	var hd := d / 2.0
	if _rng.randf() < 0.4:
		_roof = METAL_ROOF
		_roof_tex = Tex.METAL
	var tall := clampf(w * 0.42, 6.0, 9.0)
	var x_join := -hw + tall
	var top := 2.0 * STOREY
	_walls(-hw, x_join, -hd, hd, top, _brick, Tex.BRICK, _siding, Tex.SIDING, STOREY)
	var front_gable := _rng.randf() < 0.6
	if front_gable:
		_gable(-hw, x_join, -hd, hd, top, _rise(tall, 0.55, 1.6, 3.2), false, _siding, Tex.SIDING)
	else:
		_gable(-hw, x_join, -hd, hd, top, _rise(d, 0.45, 1.4, 3.0), true, _siding, Tex.SIDING)
	var mid := (-hw + x_join) / 2.0
	_row(Vector3.BACK, Vector3(-hw, 0, hd), Vector3(x_join, 0, hd), 2 if tall >= 8.0 else 1, 0.9, 1.1, 1.4)
	_row(Vector3.BACK, Vector3(-hw, 0, hd), Vector3(x_join, 0, hd), 2, STOREY + 0.8, 1.0, 1.3)
	_sides(-hw, x_join, -hd, hd, 2, true, false, true)
	# The wing.
	var wz0 := -hd + minf(1.0, d * 0.1)
	var wz1 := hd - minf(1.6, d * 0.15)
	_walls(x_join, hw, wz0, wz1, STOREY, _siding, Tex.SIDING, _siding, Tex.SIDING, STOREY)
	_gable(x_join - 0.2, hw, wz0, wz1, STOREY, _rise(wz1 - wz0, 0.42, 1.2, 2.4), true, _siding, Tex.SIDING)
	var porch_end := hw
	if hw - x_join >= 9.5:
		porch_end = hw - 3.9
		_garage_door(Vector3(hw - 1.95, 0.0, wz1), 2.6)
	var door_x := x_join + 1.3
	_door_at(Vector3(door_x, 0.0, wz1))
	_row(Vector3.BACK, Vector3(door_x + 0.8, 0, wz1), Vector3(porch_end, 0, wz1),
			maxi(1, int((porch_end - door_x - 0.8) / 2.6)), 0.9, 1.3, 1.4)
	_porch(x_join + 0.1, porch_end, wz1, minf(wz1 + 1.6, hd), STOREY - 0.25, false)
	_sides(x_join, hw, wz0, wz1, 1, false, true, true)
	if _rng.randf() < 0.4:
		_chimney(Vector3(-hw - 0.4, 0.0, 0.0), top + 2.0, Vector3(0.7, 0.0, 1.2))


## Two-storey siding house with tall white posts holding a porch roof across its front, and a
## one-storey wing when it's wide enough.
func _porch_colonial(w: float, d: float) -> void:
	var hw := w / 2.0
	var hd := d / 2.0
	var main := w if w < 14.0 or _rng.randf() < 0.4 else clampf(w * 0.72, 10.0, 16.0)
	if w - main < 4.0:
		main = w
	var x1 := -hw + main
	var porch := minf(2.2, d * 0.22)
	var zf := hd - porch
	var top := 2.0 * STOREY
	_walls(-hw, x1, -hd, zf, top, _siding, Tex.SIDING, _siding, Tex.SIDING, top)
	_gable(-hw, x1, -hd, zf, top, _rise(zf + hd, 0.5, 1.6, 3.4), true, _siding, Tex.SIDING)
	var count := maxi(3, int(main / 2.7))
	_row(Vector3.BACK, Vector3(-hw, 0, zf), Vector3(x1, 0, zf), count, STOREY + 0.8, 1.0, 1.35)
	var door_x := (-hw + x1) / 2.0
	_door_at(Vector3(door_x, 0.0, zf))
	_row(Vector3.BACK, Vector3(-hw, 0, zf), Vector3(x1, 0, zf), count, 0.85, 1.0, 1.5,
			[Vector2(door_x + hw - 0.9, door_x + hw + 0.9)])
	_porch(-hw, x1, zf, hd, STOREY, true)
	_sides(-hw, x1, -hd, zf, 2, true, main >= w, true)
	if main < w:
		var wz0 := -hd + 1.0
		_walls(x1, hw, wz0, zf, STOREY, _siding, Tex.SIDING, _siding, Tex.SIDING, STOREY)
		_gable(x1 - 0.2, hw, wz0, zf, STOREY, _rise(zf - wz0, 0.42, 1.2, 2.4), true, _siding, Tex.SIDING)
		_row(Vector3.BACK, Vector3(x1, 0, zf), Vector3(hw, 0, zf), maxi(1, int((hw - x1) / 3.0)), 0.9, 1.0, 1.4)
		_sides(x1, hw, wz0, zf, 1, false, true, true)
	if _rng.randf() < 0.6:
		_chimney(Vector3(-hw - 0.4, 0.0, (zf - hd) / 2.0), top + 2.6, Vector3(0.7, 0.0, 1.2))


## Narrow two-storey house with its gable to the street: brick below, dark vertical boards
## above, and a garage beside it when the lot is wide.
func _gable_front(w: float, d: float, storeys: int) -> void:
	var hw := w / 2.0
	var hd := d / 2.0
	var main := minf(w, 10.0) if w >= 13.0 else w
	if w - main < 3.6:
		main = w
	var x1 := -hw + main
	var top := storeys * STOREY
	var board: Color = BOARDS[_rng.randi() % BOARDS.size()] if _rng.randf() < 0.6 else _siding
	var board_tex := Tex.BOARD if board != _siding else Tex.SIDING
	_walls(-hw, x1, -hd, hd, top, _brick, Tex.BRICK, board, board_tex, STOREY if storeys > 1 else 1.0)
	var rise := _rise(main, 0.62, 2.0, 4.5)
	_gable(-hw, x1, -hd, hd, top, rise, false, board, board_tex)
	var door_x := -hw + main * (0.7 if _rng.randf() < 0.5 else 0.3)
	_door_at(Vector3(door_x, 0.0, hd))
	_row(Vector3.BACK, Vector3(-hw, 0, hd), Vector3(x1, 0, hd), 3, 0.9, 1.1, 1.4,
			[Vector2(door_x + hw - 0.9, door_x + hw + 0.9)])
	if storeys > 1:
		_row(Vector3.BACK, Vector3(-hw, 0, hd), Vector3(x1, 0, hd), 2, STOREY + 0.8, 1.0, 1.3)
	if rise > 2.6:
		_window(Vector3.BACK, Vector3((-hw + x1) / 2.0, top + rise * 0.3, hd), 0.8, 0.8, false, true)
	_sides(-hw, x1, -hd, hd, storeys, true, main >= w, true)
	if main < w:
		var gz0 := hd - minf(d, 7.0)
		_walls(x1, hw, gz0, hd, STOREY, _brick, Tex.BRICK, _brick, Tex.BRICK, STOREY)
		_gable(x1, hw, gz0, hd, STOREY, _rise(hw - x1, 0.5, 1.0, 2.6), false, board, board_tex)
		_garage_doors(x1, hw, hd)
		_sides(x1, hw, gz0, hd, 1, false, true, false)


## One-storey brick ranch with a front-gable garage stepped forward, a chimney and shutters.
func _ranch_garage(w: float, d: float) -> void:
	var hw := w / 2.0
	var hd := d / 2.0
	var g := 6.4 if w >= 17.0 else 3.9
	var x1 := hw - g
	var zf := hd - (1.2 if d >= 8.0 else 0.6)
	var wall := _brick if _rng.randf() < 0.7 else _siding
	var tex := Tex.BRICK if wall == _brick else Tex.SIDING
	_walls(-hw, x1, -hd, zf, STOREY, wall, tex, wall, tex, STOREY)
	var rise := _rise(zf + hd, 0.42, 1.3, 2.8)
	_gable(-hw, x1 + 0.3, -hd, zf, STOREY, rise, true, wall, tex)
	var gz0 := hd - minf(d, 7.4)
	_walls(x1, hw, gz0, hd, STOREY, wall, tex, wall, tex, STOREY)
	_gable(x1, hw, gz0, hd, STOREY, _rise(g, 0.5, 1.0, 2.4), false, _siding, Tex.SIDING)
	_garage_doors(x1, hw, hd)
	var door_x := x1 - 1.3
	_door_at(Vector3(door_x, 0.0, zf))
	var span := door_x - 0.8 + hw
	if span > 4.5:
		_window(Vector3.BACK, Vector3(-hw + span * 0.62, 0.8, zf), 2.0, 1.4, _shutters, true)
		_row(Vector3.BACK, Vector3(-hw, 0, zf), Vector3(-hw + span * 0.62 - 1.4, 0, zf),
				maxi(1, int((span * 0.62 - 1.4) / 2.8)), 0.9, 1.0, 1.3)
	else:
		_row(Vector3.BACK, Vector3(-hw, 0, zf), Vector3(door_x - 0.8, 0, zf), 1, 0.9, 1.0, 1.3)
	_sides(-hw, x1, -hd, zf, 1, true, false, true)
	_sides(x1, hw, gz0, hd, 1, false, true, false)
	if _rng.randf() < 0.6:
		_chimney(Vector3(-hw + (x1 + hw) * 0.3, 0.0, -hd * 0.3), STOREY + rise + 0.8, Vector3(0.9, 0.0, 0.7))


## Two-storey house, brick below and siding above, shutters on every front window, a little
## portico over the middle door, and a one-storey garage wing set back at one side.
func _garage_colonial(w: float, d: float) -> void:
	var hw := w / 2.0
	var hd := d / 2.0
	_shutters = _rng.randf() < 0.85
	if _rng.randf() < 0.6:
		_shutter = SHUTTERS[1]
	var g := 6.6 if w >= 18.5 else 4.0
	var x1 := hw - g
	var top := 2.0 * STOREY
	_walls(-hw, x1, -hd, hd, top, _brick, Tex.BRICK, _siding, Tex.SIDING, STOREY)
	var rise := _rise(d, 0.45, 1.8, 3.4)
	_gable(-hw, x1, -hd, hd, top, rise, true, _siding, Tex.SIDING)
	var main := w - g
	var count := clampi(int(main / 2.6), 3, 5)
	var door_x := (-hw + x1) / 2.0
	_row(Vector3.BACK, Vector3(-hw, 0, hd), Vector3(x1, 0, hd), count, STOREY + 0.8, 1.0, 1.35)
	_row(Vector3.BACK, Vector3(-hw, 0, hd), Vector3(x1, 0, hd), count, 0.85, 1.0, 1.5,
			[Vector2(door_x + hw - 0.9, door_x + hw + 0.9)])
	_door_at(Vector3(door_x, 0.0, hd))
	_portico(door_x, hd)
	_sides(-hw, x1, -hd, hd, 2, true, false, true)
	var gz0 := -hd + minf(1.5, d * 0.15)
	var gz1 := hd - 1.0
	var wall := _siding if _rng.randf() < 0.6 else _brick
	var tex := Tex.SIDING if wall == _siding else Tex.BRICK
	_walls(x1, hw, gz0, gz1, STOREY, wall, tex, wall, tex, STOREY)
	_gable(x1 - 0.2, hw, gz0, gz1, STOREY, _rise(gz1 - gz0, 0.42, 1.2, 2.6), true, wall, tex)
	_garage_doors(x1, hw, gz1)
	_sides(x1, hw, gz0, gz1, 1, false, true, true)
	if _rng.randf() < 0.5:
		_chimney(Vector3(-hw - 0.4, 0.0, 0.0), top + rise + 0.6, Vector3(0.7, 0.0, 1.2))


## Small one-storey house, brick or siding, no garage.
func _ranch(w: float, d: float) -> void:
	var hw := w / 2.0
	var hd := d / 2.0
	var wall := _brick if _rng.randf() < 0.45 else _siding
	var tex := Tex.BRICK if wall == _brick else Tex.SIDING
	_walls(-hw, hw, -hd, hd, STOREY, wall, tex, wall, tex, STOREY)
	var side_gable := w >= d * 0.9
	var rise := _rise(d if side_gable else w, 0.45, 1.2, 2.8)
	_gable(-hw, hw, -hd, hd, STOREY, rise, side_gable, _siding if tex == Tex.BRICK else wall, Tex.SIDING)
	var door_x := w * _rng.randf_range(-0.2, 0.25)
	_door_at(Vector3(door_x, 0.0, hd))
	_row(Vector3.BACK, Vector3(-hw, 0, hd), Vector3(hw, 0, hd), maxi(2, int((w - 1.5) / 3.0)), 0.9, 1.1, 1.35,
			[Vector2(door_x + hw - 0.9, door_x + hw + 0.9)])
	if _rng.randf() < 0.35:
		_portico(door_x, hd)
	_sides(-hw, hw, -hd, hd, 1, true, true, true)
	if _rng.randf() < 0.4:
		_chimney(Vector3(hw * 0.4, 0.0, -hd * 0.3), STOREY + rise + 0.7, Vector3(0.8, 0.0, 0.7))


# Parts ---------------------------------------------------------------------------------------


## Roof rise for a span at a pitch (rise over half the span), within limits.
func _rise(span: float, pitch: float, low: float, high: float) -> float:
	return clampf(span / 2.0 * pitch, low, high)


## Four walls of a block from the floor to top, one colour and texture below split and another
## above, standing on a foundation that reaches down into the ground.
func _walls(x0: float, x1: float, z0: float, z1: float, top: float, low: Color, low_tex: Tex, high: Color,
		high_tex: Tex, split: float) -> void:
	var corners := [Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(x0, 0, z0)]
	var outs := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]
	split = minf(split, top)
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var n: Vector3 = outs[k]
		_quad(_buf, a, b, b + Vector3.UP * split, a + Vector3.UP * split, n, low, low_tex, true)
		if split < top:
			_quad(_buf, a + Vector3.UP * split, b + Vector3.UP * split, b + Vector3.UP * top, a + Vector3.UP * top,
					n, high, high_tex, true)
	_box(_buf, Vector3(x0 - 0.05, _foot, z0 - 0.05), Vector3(x1 + 0.05, 0.22, z1 + 0.05), FOUNDATION, Tex.PLAIN, false)


## A gable roof over the block from x0 to x1 and z0 to z1 with its eaves at height eave; the
## ridge runs along x if along_x, else along z (gable to the street). The gable ends carry on
## the top wall's colour and texture.
func _gable(x0: float, x1: float, z0: float, z1: float, eave: float, rise: float, along_x: bool,
		gable: Color, gable_tex: Tex) -> void:
	var r0 := x0 if along_x else z0
	var r1 := x1 if along_x else z1
	var c0 := z0 if along_x else x0
	var c1 := z1 if along_x else x1
	var cm := (c0 + c1) / 2.0
	var top := eave + rise
	var o := OVERHANG
	var drop := o * rise / ((c1 - c0) / 2.0)
	var edge := eave - drop
	for side in [-1.0, 1.0]:
		var c_edge: float = (c1 + o) if side > 0.0 else (c0 - o)
		var a := _p(along_x, r0 - o, edge, c_edge)
		var b := _p(along_x, r1 + o, edge, c_edge)
		var c := _p(along_x, r1 + o, top, cm)
		var d := _p(along_x, r0 - o, top, cm)
		_quad_out(_buf, a, b, c, d, Vector3.UP, _roof, _roof_tex, true)
		# Fascia along the eave.
		var out := _p(along_x, 0.0, 0.0, side)
		_quad(_buf, a + Vector3.DOWN * 0.18, b + Vector3.DOWN * 0.18, b, a, out, TRIM, Tex.PLAIN, false)
		# Soffit back to the wall.
		var c_wall: float = c1 if side > 0.0 else c0
		_quad(_buf, a + Vector3.DOWN * 0.18, b + Vector3.DOWN * 0.18, _p(along_x, r1 + o, eave - 0.18, c_wall),
				_p(along_x, r0 - o, eave - 0.18, c_wall), Vector3.DOWN, TRIM, Tex.PLAIN, false)
	for end in [-1.0, 1.0]:
		var r: float = r1 if end > 0.0 else r0
		var out := _p(along_x, end, 0.0, 0.0)
		var a := _p(along_x, r, eave, c0)
		var b := _p(along_x, r, eave, c1)
		var t := _p(along_x, r, top, cm)
		_tri(_buf, a, b, t, out, gable, gable_tex, true)
		# Rake boards along the two sloping edges, out past the gable.
		var rr: float = r + end * o
		for c_edge in [c0 - o, c1 + o]:
			var e := _p(along_x, rr, edge, c_edge)
			var ridge := _p(along_x, rr, top, cm)
			_quad(_fine, e, ridge, ridge + Vector3.DOWN * 0.18, e + Vector3.DOWN * 0.18, out, TRIM, Tex.PLAIN, false)


## A point given along the ridge (r), up (y) and across it (c).
func _p(along_x: bool, r: float, y: float, c: float) -> Vector3:
	return Vector3(r, y, c) if along_x else Vector3(c, y, r)


## A porch across the front from x0 to x1, out from the wall at z_wall to z_out: a slab, white
## posts, a beam and a shed roof. Tall porches get posts at least every 2.6 m.
func _porch(x0: float, x1: float, z_wall: float, z_out: float, height: float, tall: bool) -> void:
	if x1 - x0 < 2.0 or z_out - z_wall < 0.8:
		return
	_box(_buf, Vector3(x0, _foot, z_wall), Vector3(x1, 0.2, z_out), CONCRETE, Tex.PLAIN, false)
	_stoop = Vector3(clampf(_stoop.x, x0 + 0.8, x1 - 0.8), 0.2, maxf(_stoop.z, z_out))
	var posts := maxi(2, int(ceil((x1 - x0) / (2.6 if tall else 3.2))) + 1)
	var size := 0.24 if tall else 0.18
	for k in posts:
		var x := lerpf(x0 + 0.25, x1 - 0.25, float(k) / (posts - 1))
		_box(_buf, Vector3(x - size / 2.0, 0.2, z_out - 0.3 - size / 2.0),
				Vector3(x + size / 2.0, height, z_out - 0.3 + size / 2.0), TRIM, Tex.PLAIN, false, false)
	_box(_buf, Vector3(x0, height - 0.3, z_out - 0.45), Vector3(x1, height, z_out - 0.15), TRIM, Tex.PLAIN, false)
	var a := Vector3(x0 - 0.1, height, z_out + 0.15)
	var b := Vector3(x1 + 0.1, height, z_out + 0.15)
	var c := Vector3(x1 + 0.1, height + 0.55, z_wall)
	var d := Vector3(x0 - 0.1, height + 0.55, z_wall)
	_quad_out(_buf, a, b, c, d, Vector3.UP, _roof, _roof_tex, false)
	_quad(_buf, a + Vector3.DOWN * 0.15, b + Vector3.DOWN * 0.15, b, a, Vector3.BACK, TRIM, Tex.PLAIN, false)


## A small gabled hood on two posts over a front door at x on the wall at z.
func _portico(x: float, z: float) -> void:
	var half := 1.1
	var depth := 1.3
	var h := 2.55
	_box(_buf, Vector3(x - half, _foot, z), Vector3(x + half, 0.18, z + depth), CONCRETE, Tex.PLAIN, false)
	_stoop = Vector3(x, 0.18, z + depth)
	for side in [-1.0, 1.0]:
		var px: float = x + side * (half - 0.15)
		_box(_buf, Vector3(px - 0.09, 0.18, z + depth - 0.24), Vector3(px + 0.09, h, z + depth - 0.06),
				TRIM, Tex.PLAIN, false, false)
	var top := h + 0.8
	for side in [-1.0, 1.0]:
		var e: float = x + side * (half + 0.1)
		_quad_out(_buf, Vector3(e, h, z), Vector3(e, h, z + depth + 0.1), Vector3(x, top, z + depth + 0.1),
				Vector3(x, top, z), Vector3.UP, _roof, _roof_tex, false)
	_tri(_buf, Vector3(x - half - 0.1, h, z + depth + 0.1), Vector3(x + half + 0.1, h, z + depth + 0.1),
			Vector3(x, top, z + depth + 0.1), Vector3.BACK, TRIM, Tex.PLAIN, false)


## A front door centred on at (on the wall's base line), with its frame, a step, a knob and a lamp.
func _door_at(at: Vector3) -> void:
	var n := Vector3.BACK
	_flat(_buf, n, at, -0.6, 0.6, 0.0, 2.25, 0.03, TRIM, Tex.PLAIN)
	_flat(_buf, n, at, -0.47, 0.47, 0.0, 2.12, 0.045, _door, Tex.PLAIN)
	_flat(_fine, n, at, -0.3, 0.3, 1.55, 1.95, 0.05, GLASS, Tex.GLASS)
	_flat(_fine, n, at, 0.3, 0.37, 0.98, 1.06, 0.06, BLACK, Tex.PLAIN)
	_box(_buf, Vector3(at.x - 0.8, _foot, at.z), Vector3(at.x + 0.8, 0.0, at.z + 0.9), CONCRETE, Tex.PLAIN, false)
	_stoop = Vector3(at.x, 0.0, at.z + 0.9)
	_box(_fine, Vector3(at.x + 0.75, 1.75, at.z), Vector3(at.x + 0.93, 2.1, at.z + 0.16), BLACK, Tex.PLAIN, false)
	_flat(_fine, n, Vector3(at.x, 0.0, at.z + 0.161), 0.78, 0.9, 1.8, 2.05, 0.0, LAMP, Tex.PLAIN)


## Garage doors along the front wall from x0 to x1 at z: one wide or two single doors for a
## two-car garage, one single door otherwise.
func _garage_doors(x0: float, x1: float, z: float) -> void:
	var width := x1 - x0
	if width >= 6.0:
		if _rng.randf() < 0.5:
			_garage_door(Vector3((x0 + x1) / 2.0, 0.0, z), minf(4.9, width - 1.0))
		else:
			_garage_door(Vector3(x0 + width * 0.27, 0.0, z), 2.5)
			_garage_door(Vector3(x0 + width * 0.73, 0.0, z), 2.5)
	else:
		_garage_door(Vector3((x0 + x1) / 2.0, 0.0, z), minf(2.6, width - 0.8))


func _garage_door(at: Vector3, width: float) -> void:
	var n := Vector3.BACK
	var half := width / 2.0
	_flat(_buf, n, at, -half - 0.12, half + 0.12, 0.0, 2.27, 0.03, TRIM, Tex.PLAIN)
	_flat(_buf, n, at, -half, half, 0.0, 2.15, 0.045, TRIM.darkened(0.04), Tex.PANEL)
	if _rng.randf() < 0.4:
		var panes := maxi(2, int(width / 0.6))
		for k in panes:
			var u := lerpf(-half, half, (k + 0.5) / panes)
			_flat(_fine, n, at, u - 0.2, u + 0.2, 1.7, 1.95, 0.05, GLASS, Tex.GLASS)
	_box(_buf, Vector3(at.x - half - 0.1, _foot, at.z), Vector3(at.x + half + 0.1, 0.02, at.z + 1.0),
			CONCRETE, Tex.PLAIN, false)
	_apron(at.x - half - 0.1, at.x + half + 0.1, at.z + 1.0)


## Where the yard falls away in front of a garage, a concrete apron sloping from the door's slab
## at z down to the yard, so the slab doesn't stand on a bare block.
func _apron(x0: float, x1: float, z: float) -> void:
	var drop := 0.02 - _yard
	if drop < 0.2:
		return
	var z1 := z + clampf(drop * 5.0, 1.5, 6.0)
	var a := Vector3(x0, 0.02, z)
	var b := Vector3(x1, 0.02, z)
	var c := Vector3(x1, _yard, z1)
	var d := Vector3(x0, _yard, z1)
	_quad_out(_buf, d, c, b, a, Vector3.UP, CONCRETE, Tex.PLAIN, false)
	_quad(_buf, Vector3(x0, _foot, z), Vector3(x0, _foot, z1), d, a, Vector3.LEFT, CONCRETE, Tex.PLAIN, false)
	_quad(_buf, Vector3(x1, _foot, z1), Vector3(x1, _foot, z), b, c, Vector3.RIGHT, CONCRETE, Tex.PLAIN, false)
	_quad(_buf, Vector3(x0, _foot, z1), Vector3(x1, _foot, z1), c, d, Vector3.BACK, CONCRETE, Tex.PLAIN, false)


## Steps down from the front door's stoop, porch or portico slab to the yard, when it is more
## than one step above it: 0.3 m treads, risers of at most 0.19 m.
func _steps() -> void:
	var drop := _stoop.y - _yard
	if drop < 0.3:
		return
	var count := int(ceil(drop / 0.19))
	var rise := drop / count
	var x := _stoop.x
	for k in range(1, count):
		var z := _stoop.z + (k - 1) * 0.3
		_box(_buf, Vector3(x - 0.7, _foot, z), Vector3(x + 0.7, _stoop.y - k * rise, z + 0.3), CONCRETE,
				Tex.PLAIN, false)


## A window on a wall facing n, centred on at's x or z, with its sill at at.y: a white frame,
## glass, a cross of muntins up close, and shutters if asked.
func _window(n: Vector3, at: Vector3, w: float, h: float, shutters: bool, panes: bool) -> void:
	var half := w / 2.0
	_flat(_buf, n, at, -half - 0.09, half + 0.09, -0.1, h + 0.09, 0.03, TRIM, Tex.PLAIN)
	_flat(_buf, n, at, -half, half, 0.0, h, 0.045, GLASS, Tex.GLASS)
	if panes:
		_flat(_fine, n, at, -0.025, 0.025, 0.0, h, 0.055, TRIM, Tex.PLAIN)
		_flat(_fine, n, at, -half, half, h * 0.5 - 0.025, h * 0.5 + 0.025, 0.055, TRIM, Tex.PLAIN)
	if shutters:
		var sw := clampf(w * 0.42, 0.35, 0.55)
		for side in [-1.0, 1.0]:
			var u0: float = side * (half + 0.12)
			var u1: float = side * (half + 0.12 + sw)
			_flat(_buf, n, at, minf(u0, u1), maxf(u0, u1), -0.05, h + 0.05, 0.04, _shutter, Tex.PLAIN)


## count windows evenly along the wall from a to b (on its base line), facing n, skipping any
## whose spot (distance from a) falls inside one of the avoid ranges. Front windows get shutters.
func _row(n: Vector3, a: Vector3, b: Vector3, count: int, sill: float, w: float, h: float,
		avoid: Array = []) -> void:
	var length := a.distance_to(b)
	if length < w + 0.8:
		return
	count = mini(count, int(length / (w + 0.7)))
	for k in count:
		var t := (k + 0.5) / count
		var at := t * length
		var blocked := false
		for range_: Vector2 in avoid:
			if at + w / 2.0 > range_.x and at - w / 2.0 < range_.y:
				blocked = true
		if blocked:
			continue
		var spot := a.lerp(b, t)
		_window(n, Vector3(spot.x, sill, spot.z), w, h, _shutters and n == Vector3.BACK, true)


## Plain windows on a block's left, right and back walls, one row per storey.
func _sides(x0: float, x1: float, z0: float, z1: float, storeys: int, left: bool, right: bool, back: bool) -> void:
	for s in storeys:
		var sill := 0.9 + s * STOREY
		if left:
			_row(Vector3.LEFT, Vector3(x0, 0, z1), Vector3(x0, 0, z0), int((z1 - z0) / 4.5), sill, 0.9, 1.2)
		if right:
			_row(Vector3.RIGHT, Vector3(x1, 0, z0), Vector3(x1, 0, z1), int((z1 - z0) / 4.5), sill, 0.9, 1.2)
		if back:
			_row(Vector3.FORWARD, Vector3(x1, 0, z0), Vector3(x0, 0, z0), int((x1 - x0) / 3.8), sill, 1.0, 1.2)


## A brick chimney from the ground (or through the roof) to height, centred on at, size wide.
func _chimney(at: Vector3, height: float, size: Vector3) -> void:
	var lo := Vector3(at.x - size.x / 2.0, _foot, at.z - size.z / 2.0)
	var hi := Vector3(at.x + size.x / 2.0, height, at.z + size.z / 2.0)
	_box(_buf, lo, hi, _brick, Tex.BRICK, false)
	_box(_buf, Vector3(lo.x - 0.06, height, lo.z - 0.06), Vector3(hi.x + 0.06, height + 0.1, hi.z + 0.06),
			CONCRETE, Tex.PLAIN, false)


# Drawing -------------------------------------------------------------------------------------


## A rectangle on a wall facing n, through at, from u0 to u1 across the wall and y0 to y1 above
## at, standing off the wall by off.
func _flat(buf: Buffer, n: Vector3, at: Vector3, u0: float, u1: float, y0: float, y1: float, off: float,
		colour: Color, tex: Tex) -> void:
	var t := Vector3.UP.cross(n)
	var base := at + n * off
	_quad(buf, base + t * u0 + Vector3.UP * y0, base + t * u1 + Vector3.UP * y0, base + t * u1 + Vector3.UP * y1,
			base + t * u0 + Vector3.UP * y1, n, colour, tex, false)


## An axis-aligned box, its sides and (if top) its top; no bottom, as nobody sees it.
func _box(buf: Buffer, lo: Vector3, hi: Vector3, colour: Color, tex: Tex, solid: bool, top := true) -> void:
	_quad(buf, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
			Vector3.BACK, colour, tex, solid)
	_quad(buf, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
			Vector3.FORWARD, colour, tex, solid)
	_quad(buf, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z),
			Vector3.LEFT, colour, tex, solid)
	_quad(buf, Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z),
			Vector3.RIGHT, colour, tex, solid)
	if top:
		_quad(buf, Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
				Vector3.UP, colour, tex, solid)


## A quad whose normal comes from its corners, turned to the side hint points to.
func _quad_out(buf: Buffer, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3, colour: Color, tex: Tex,
		solid: bool) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.dot(hint) < 0.0:
		n = -n
	_quad(buf, a, b, c, d, n, colour, tex, solid)


## One quad in the house's frame, with UV in metres across and up the face. solid quads go into
## the collision faces too.
func _quad(buf: Buffer, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, colour: Color, tex: Tex,
		solid: bool) -> void:
	var t := Vector3.RIGHT
	var s := Vector3.BACK
	if absf(n.y) < 0.99:
		t = Vector3(-n.z, 0.0, n.x).normalized()
		s = t.cross(n)
	var base := buf.verts.size()
	var wn := _basis * n
	var tinted := Color(colour.r, colour.g, colour.b, float(tex) / 8.0)
	var wa := _origin + _basis * a
	var wb := _origin + _basis * b
	var wc := _origin + _basis * c
	var wd := _origin + _basis * d
	buf.verts.append_array([wa, wb, wc, wd])
	buf.normals.append_array([wn, wn, wn, wn])
	buf.colours.append_array([tinted, tinted, tinted, tinted])
	buf.uvs.append_array([Vector2(a.dot(t), a.dot(s)), Vector2(b.dot(t), b.dot(s)), Vector2(c.dot(t), c.dot(s)),
			Vector2(d.dot(t), d.dot(s))])
	buf.index.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if solid:
		_faces.append_array([wa, wb, wc, wa, wc, wd])


func _tri(buf: Buffer, a: Vector3, b: Vector3, c: Vector3, n: Vector3, colour: Color, tex: Tex, solid: bool) -> void:
	var t := Vector3(-n.z, 0.0, n.x).normalized() if absf(n.y) < 0.99 else Vector3.RIGHT
	var s := t.cross(n) if absf(n.y) < 0.99 else Vector3.BACK
	var base := buf.verts.size()
	var wn := _basis * n
	var tinted := Color(colour.r, colour.g, colour.b, float(tex) / 8.0)
	var wa := _origin + _basis * a
	var wb := _origin + _basis * b
	var wc := _origin + _basis * c
	buf.verts.append_array([wa, wb, wc])
	buf.normals.append_array([wn, wn, wn])
	buf.colours.append_array([tinted, tinted, tinted])
	buf.uvs.append_array([Vector2(a.dot(t), a.dot(s)), Vector2(b.dot(t), b.dot(s)), Vector2(c.dot(t), c.dot(s))])
	buf.index.append_array([base, base + 1, base + 2])
	if solid:
		_faces.append_array([wa, wb, wc])
