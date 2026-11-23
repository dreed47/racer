extends Node3D
## Test drive: puts the car on the track's spawn point.
## Game modes (time trial, race, cruise) will replace this later.


func _ready() -> void:
	$Car.global_transform = $Track/Spawn.global_transform
	$Car.reset_physics_interpolation()
	$ChaseCamera.global_position = $ChaseCamera._wanted_position()
