class_name GhostRecording
extends RefCounted
## One lap of a car's movement, for the ghost car: where the body was, how far each wheel
## hung down and how far the front wheels were steered, about 60 times a second.
## Plain data, no nodes, so tests can build and read one. Saves to a small file.

## Bump when the file layout changes; older files are then ignored.
const VERSION := 1
## Shortest gap between samples, in seconds.
const SAMPLE_GAP := 1.0 / 60.0
## Wheel order for wheel drops: front left, front right, rear left, rear right.
const WHEEL_NAMES: Array[String] = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]

var track_id := ""
## Lap time in seconds. 0 while still recording.
var lap_time := 0.0
## Time in the lap of each sample, in seconds, rising.
var times := PackedFloat32Array()
var positions := PackedVector3Array()
## Body rotation of each sample, as a quaternion (x, y, z, w).
var rotations := PackedVector4Array()
## Front wheel steer angle of each sample, in radians.
var steers := PackedFloat32Array()
## How far each wheel's visual sits below its mount, in metres (FL, FR, RL, RR).
var drops := PackedVector4Array()


func _init(track := "") -> void:
	track_id = track


func size() -> int:
	return times.size()


## Adds a sample. Skipped if it comes sooner than SAMPLE_GAP after the last one.
func add(t: float, body: Transform3D, steer: float, wheel_drops: Vector4) -> void:
	if size() > 0 and t - times[size() - 1] < SAMPLE_GAP - 0.0001:
		return
	var q := body.basis.get_rotation_quaternion()
	times.append(t)
	positions.append(body.origin)
	rotations.append(Vector4(q.x, q.y, q.z, q.w))
	steers.append(steer)
	drops.append(wheel_drops)


## Adds a sample from a car as it is now.
func add_car(t: float, car: Car) -> void:
	var d := Vector4.ZERO
	for i in 4:
		d[i] = (car.get_node(WHEEL_NAMES[i] + "/Visual") as Node3D).position.y
	add(t, car.global_transform, car.wheels[0].steer_angle, d)


## Body place at a time in the lap, blended between the two nearest samples.
func transform_at(t: float) -> Transform3D:
	var k := _index_before(t)
	var f := _fraction(k, t)
	var a := _quat(k)
	var b := _quat(mini(k + 1, size() - 1))
	return Transform3D(Basis(a.slerp(b, f)), positions[k].lerp(positions[mini(k + 1, size() - 1)], f))


func steer_at(t: float) -> float:
	var k := _index_before(t)
	return lerpf(steers[k], steers[mini(k + 1, size() - 1)], _fraction(k, t))


func drops_at(t: float) -> Vector4:
	var k := _index_before(t)
	return drops[k].lerp(drops[mini(k + 1, size() - 1)], _fraction(k, t))


## Writes the lap to a file, through a temporary file so a crash can't leave half a file.
func save(path: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		return err
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var({
		"version": VERSION, "track_id": track_id, "lap_time": lap_time, "times": times,
		"positions": positions, "rotations": rotations, "steers": steers, "drops": drops,
	})
	file.close()
	return DirAccess.rename_absolute(temp, path)


## Reads a lap from a file. Null if it's missing, from another version, or damaged.
static func load_file(path: String) -> GhostRecording:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data = file.get_var(false)  # false: never build objects from the file.
	if not data is Dictionary or data.get("version") != VERSION:
		return null
	var rec := GhostRecording.new()
	if not (data.get("times") is PackedFloat32Array and data.get("positions") is PackedVector3Array
			and data.get("rotations") is PackedVector4Array and data.get("steers") is PackedFloat32Array
			and data.get("drops") is PackedVector4Array):
		return null
	rec.track_id = str(data.get("track_id", ""))
	rec.lap_time = float(data.get("lap_time", 0.0))
	rec.times = data["times"]
	rec.positions = data["positions"]
	rec.rotations = data["rotations"]
	rec.steers = data["steers"]
	rec.drops = data["drops"]
	var n := rec.size()
	if n < 2 or rec.lap_time <= 0.0 or rec.positions.size() != n or rec.rotations.size() != n \
			or rec.steers.size() != n or rec.drops.size() != n:
		return null
	return rec


## Last sample at or before t (0 if t is before the first).
func _index_before(t: float) -> int:
	var k := times.bsearch(t, false) - 1
	return clampi(k, 0, size() - 1)


func _fraction(k: int, t: float) -> float:
	if k + 1 >= size():
		return 0.0
	return clampf((t - times[k]) / (times[k + 1] - times[k]), 0.0, 1.0)


func _quat(k: int) -> Quaternion:
	var v := rotations[k]
	return Quaternion(v.x, v.y, v.z, v.w).normalized()
