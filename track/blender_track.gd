class_name BlenderTrack
extends Track
## A track made in Blender and exported as a .glb (see README.md, "Making tracks in Blender").
## The model holds everything, found by name:
## - Meshes named by surface: the start of the name picks a row in SURFACES.
##   Names starting with "deco" are looks only, with no collision.
## - Empties Gate0, Gate1, ...: the start line, then checkpoints in driving order.
## - Empty Spawn: where the car starts.
## - Centreline: an edge loop along the middle of the road, for distances along the lap.

## Grip and rolling resistance for each surface. Longer names are tried first.
const SURFACES := {
	"road": {"grip": 1.0, "rolling_resistance": 0.0},
	"kerb": {"grip": 0.9, "rolling_resistance": 0.01},
	"grass": {"grip": 0.6, "rolling_resistance": 0.06},
	"gravel": {"grip": 0.45, "rolling_resistance": 0.3},
	"wall": {"grip": 0.6, "rolling_resistance": 0.0},
	"stand": {"grip": 0.6, "rolling_resistance": 0.0},
	"tree": {"grip": 0.6, "rolling_resistance": 0.0},
}

## The imported .glb scene.
@export var model: Node3D
## Half the road width, in metres. Gates reach a little past it.
@export var road_half_width := 5.0
## Replaces the material on "grass" meshes, so the ground shows speed.
@export var grass_material: Material

var _gates: Array[Transform3D] = []
var _points := PackedVector3Array()  # Centreline, starting at the start line. The last point joins the first.
var _distances := PackedFloat64Array()
var _length := 0.0


func _ready() -> void:
	_add_collision(model)
	var gate_nodes := {}
	for node in model.find_children("Gate*", "Node3D", true, false):
		var number := node.name.trim_prefix("Gate")
		if number.is_valid_int():
			gate_nodes[number.to_int()] = node
	for i in gate_nodes.size():
		if not gate_nodes.has(i):
			push_error("%s: gates must be numbered Gate0 to Gate%d" % [track_id, gate_nodes.size() - 1])
			return
		_gates.append(_level(gate_nodes[i].global_transform))

	var marker := model.find_child("Spawn", true, false) as Node3D
	var spawn := Marker3D.new()
	spawn.name = "Spawn"
	add_child(spawn)
	if marker:
		spawn.global_transform = _level(marker.global_transform)
	else:
		push_error("%s: no Spawn empty in the model" % track_id)

	var centreline := model.find_child("Centreline", true, false) as MeshInstance3D
	if centreline:
		centreline.visible = false
		_read_centreline(centreline)
	else:
		push_error("%s: no Centreline in the model" % track_id)


func lap_length() -> float:
	return _length


func point_at(distance: float) -> Vector3:
	if _points.is_empty():
		return global_position
	var d := fposmod(distance, _length)
	var i := clampi(_distances.bsearch(d, false) - 1, 0, _points.size() - 1)
	var j := (i + 1) % _points.size()
	var d_next := _distances[j] if j > 0 else _length
	var t := (d - _distances[i]) / (d_next - _distances[i])
	return _points[i].lerp(_points[j], t)


func direction_at(distance: float) -> Vector3:
	return (point_at(distance + 1.0) - point_at(distance - 1.0)).normalized()


func gate_count() -> int:
	return _gates.size()


func gate(index: int) -> Transform3D:
	return _gates[index]


func gate_half_width() -> float:
	return road_half_width


## Gives each surface mesh a static body with its grip, and the grass its material.
func _add_collision(root: Node) -> void:
	var prefixes := SURFACES.keys()
	prefixes.sort_custom(func(a, b): return a.length() > b.length())
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var name_lower := String(mesh_node.name).to_lower()
		if name_lower.begins_with("deco") or name_lower == "centreline":
			continue
		var surface: Dictionary = {}
		for prefix in prefixes:
			if name_lower.begins_with(prefix):
				surface = SURFACES[prefix]
				break
		if surface.is_empty():
			push_warning("%s: mesh %s has no surface; treating it as road" % [track_id, mesh_node.name])
			surface = SURFACES.road
		if name_lower.begins_with("grass") and grass_material:
			mesh_node.material_override = grass_material
		var shape := mesh_node.mesh.create_trimesh_shape()
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var body := StaticBody3D.new()
		body.name = "Body"
		body.set_meta("grip", surface.grip)
		body.set_meta("rolling_resistance", surface.rolling_resistance)
		body.add_child(collision)
		mesh_node.add_child(body)


## Chains the edge loop into points in driving order, starting nearest the start line.
func _read_centreline(mesh_node: MeshInstance3D) -> void:
	var arrays := mesh_node.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if mesh_node.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_LINES or indices.is_empty():
		push_error("%s: Centreline must be an edge loop" % track_id)
		return
	var links := {}
	for k in range(0, indices.size(), 2):
		links.get_or_add(indices[k], []).append(indices[k + 1])
		links.get_or_add(indices[k + 1], []).append(indices[k])
	var world := mesh_node.global_transform
	var start: Vector3 = _gates[0].origin if not _gates.is_empty() else world.origin
	var first := -1
	for v in links:
		if first < 0 or (world * verts[v]).distance_to(start) < (world * verts[first]).distance_to(start):
			first = v
	# Step the way the start line faces.
	var forward: Vector3 = -_gates[0].basis.z if not _gates.is_empty() else Vector3.FORWARD
	var next: int = links[first][0]
	if links[first].size() > 1 and (world * verts[links[first][1]] - world * verts[first]).dot(forward) > \
			(world * verts[next] - world * verts[first]).dot(forward):
		next = links[first][1]
	var previous := first
	var here := next
	_points.append(world * verts[first])
	while here != first and _points.size() <= verts.size():
		_points.append(world * verts[here])
		var options: Array = links[here]
		var after: int = options[0] if options[0] != previous else (options[1] if options.size() > 1 else -1)
		if after < 0:
			push_error("%s: Centreline is not a closed loop" % track_id)
			break
		previous = here
		here = after
	_distances.resize(_points.size())
	var total := 0.0
	for k in _points.size():
		_distances[k] = total
		total += _points[k].distance_to(_points[(k + 1) % _points.size()])
	_length = total


## Same place, turned to face the same way but upright, with -Z forward.
static func _level(where: Transform3D) -> Transform3D:
	var forward := -where.basis.z
	forward.y = 0.0
	return Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), where.origin)
