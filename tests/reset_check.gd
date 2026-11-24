extends SceneTree
## Headless check for the reset button on the Clarion loop: a tap of Y puts the car back on the
## road where it is, and holding Y for a second takes it back to the start.
## Touches no files.
## Run: godot --headless --path . -s tests/reset_check.gd

const AWAY := 8000.0  # Loop distance where the car is put before each reset.

var _failed := false
var _ticks := 0
var _main: Main
var _car: Car
var _track: RoadTrack
var _start: Vector3


func _initialize() -> void:
	Main.track_scene = load("res://track/clarion/clarion.tscn")
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	(_main.get_node("PlayerDriver") as Node).process_mode = Node.PROCESS_MODE_DISABLED


func _physics_process(_delta: float) -> bool:
	_ticks += 1
	if _ticks == 3:
		_car = _main.get_node("Car")
		_track = _main.get_node("Track")
		_start = (_track.get_node("Spawn") as Node3D).global_position
		_away()
	# A tap: press for 2 ticks, then let go.
	if _ticks == 10:
		Input.action_press("reset_car")
	if _ticks == 12:
		Input.action_release("reset_car")
	if _ticks == 60:
		var road := _track.point_at(AWAY)
		_check(_flat(_car.global_position - road) < 5.0,
				"a tap puts the car back on the road where it is (%.1f m from there)" % _flat(_car.global_position - road))
		_check(_flat(_car.global_position - _start) > 1000.0, "a tap does not go to the start")
		_away()
	# A hold: press for 1.5 s.
	if _ticks == 70:
		Input.action_press("reset_car")
	if _ticks == 70 + int(Engine.physics_ticks_per_second * 0.5):
		_check(_flat(_car.global_position - _start) > 1000.0, "half a second of holding is still a tap")
	if _ticks == 70 + int(Engine.physics_ticks_per_second * 1.5):
		Input.action_release("reset_car")
		_check(_flat(_car.global_position - _start) < 5.0,
				"holding Y takes the car back to the start (%.1f m from it)" % _flat(_car.global_position - _start))
	if _ticks < 70 + int(Engine.physics_ticks_per_second * 2.0):
		return false
	_main.free()
	Main.track_scene = null
	print("RESET CHECK " + ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)
	return true


# Puts the car off the road, far from the start.
func _away() -> void:
	var side := _track.direction_at(AWAY).cross(Vector3.UP).normalized()
	_car.place_at(Transform3D(Basis(), _track.point_at(AWAY) + side * 12.0 + Vector3.UP * 3.0))


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	_failed = _failed or not ok
