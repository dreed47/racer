extends Camera3D
## Follows a target from behind, with smoothing.

@export var target: Node3D
@export var distance := 6.0
@export var height := 2.0
## Point on the target the camera looks at, above its origin.
@export var look_height := 0.8
## Higher values follow more tightly.
@export var stiffness := 6.0


func _ready() -> void:
	if target:
		global_position = _wanted_position()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(_wanted_position(), 1.0 - exp(-stiffness * delta))
	look_at(target.global_position + Vector3.UP * look_height)


func _wanted_position() -> Vector3:
	var facing := -target.global_basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.001:
		facing = Vector3.FORWARD
	return target.global_position - facing.normalized() * distance + Vector3.UP * height
