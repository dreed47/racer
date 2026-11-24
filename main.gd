class_name Main
extends Node3D
## Puts the car on the track's spawn point. On reset (Y) or after a fall, the track says where
## the car goes: the start on short tracks, the nearest bit of road on long ones.
## The game mode (time trial now) is its own node and only watches the car.

## Below this height the car has fallen off the world, so it is put back.
const FALL_LIMIT := -20.0
const DEFAULT_TRACK := "res://track/ridge/ridge.tscn"

## The track to drive. The track menu sets it before it makes this scene. Empty means the
## practice track.
static var track_scene: PackedScene

@onready var _car: Car = $Car
@onready var _spawn: Node3D = $Track/Spawn
@onready var _track: Track = $Track
@onready var _camera = $ChaseCamera


func _init() -> void:
	# The track is made here, before the scene's other nodes, so it is the first child: it is
	# ready before anything that asks it about the road, and "../Track" paths find it.
	var scene := track_scene if track_scene != null else load(DEFAULT_TRACK) as PackedScene
	var track := scene.instantiate()
	track.name = "Track"
	add_child(track)


func _ready() -> void:
	_car.placed.connect(_snap_camera)
	_car.global_transform = _spawn.global_transform
	_car.reset_physics_interpolation()
	_snap_camera()


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset_car") or _car.global_position.y < FALL_LIMIT:
		_car.place_at(_track.reset_transform(_car.global_position))


func _snap_camera() -> void:
	_camera.global_position = _camera._wanted_position()
	_camera.reset_physics_interpolation()
