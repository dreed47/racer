extends Node3D
## Puts the car on the track's spawn point, and back there on reset (Y) or after a fall.
## The game mode (time trial now) is its own node and only watches the car.

## Below this height the car has fallen off the world, so it goes back to the start.
const FALL_LIMIT := -20.0

@onready var _car: Car = $Car
@onready var _spawn: Node3D = $Track/Spawn
@onready var _camera = $ChaseCamera


func _ready() -> void:
	_car.placed.connect(_snap_camera)
	_car.global_transform = _spawn.global_transform
	_car.reset_physics_interpolation()
	_snap_camera()


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset_car") or _car.global_position.y < FALL_LIMIT:
		_car.place_at(_spawn.global_transform)


func _snap_camera() -> void:
	_camera.global_position = _camera._wanted_position()
	_camera.reset_physics_interpolation()
