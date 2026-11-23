class_name GhostCar
extends Node3D
## See-through copy of the roadster that replays the fastest lap (TimeTrial.ghost) in step
## with your current lap. Looks only: no collision, so you drive through it.
## Shows only while a lap is running and a ghost lap exists. G or D-pad up turns it on and off.

## Sent when the ghost is turned on or off. has_lap is false if there's no lap to show yet.
signal toggled(shown: bool, has_lap: bool)

const MODEL := preload("res://car/roadster/roadster.glb")
## Wheel radius the model was made for, in metres (as in CarLook).
const MODEL_WHEEL_RADIUS := 0.29
const COLOUR := Color(0.55, 0.75, 1.0, 0.35)

@export var time_trial: TimeTrial
var shown := true

var _wheels: Array[Node3D] = []
var _visuals: Array[Node3D] = []
var _spins: Array[Node3D] = []
var _angle := 0.0
var _last_time := -1.0
var _last_position := Vector3.ZERO
var _was_visible := false


func _ready() -> void:
	visible = false
	var model := MODEL.instantiate() as Node3D
	add_child(model)
	var wheel := model.find_child("wheel", true, false) as MeshInstance3D
	var caliper := model.find_child("caliper", true, false) as MeshInstance3D
	var setup := time_trial.car.setup
	var x := setup.track_width / 2.0
	var z := setup.wheelbase / 2.0
	var size := setup.wheel_radius / MODEL_WHEEL_RADIUS
	for i in 4:
		var right := i % 2 == 1
		var mount := Node3D.new()
		mount.position = Vector3(x if right else -x, setup.mount_height, -z if i < 2 else z)
		add_child(mount)
		var visual := Node3D.new()
		visual.scale = Vector3.ONE * size
		mount.add_child(visual)
		var spin := Node3D.new()
		visual.add_child(spin)
		var turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) if right else Transform3D.IDENTITY
		var copy := wheel.duplicate() as MeshInstance3D
		copy.transform = turn
		spin.add_child(copy)
		var brake := caliper.duplicate() as MeshInstance3D
		brake.transform = turn
		visual.add_child(brake)
		_wheels.append(mount)
		_visuals.append(visual)
		_spins.append(spin)
	wheel.visible = false
	caliper.visible = false
	_make_see_through(self)


func toggle() -> void:
	shown = not shown
	toggled.emit(shown, time_trial.ghost != null)


func _process(_delta: float) -> void:
	# Skip while a menu (the tuning panel) has focus: the D-pad moves through it then.
	if Input.is_action_just_pressed("toggle_ghost") and get_viewport().gui_get_focus_owner() == null:
		toggle()


func _physics_process(delta: float) -> void:
	var ghost := time_trial.ghost
	var timer := time_trial.timer
	var show_now := shown and ghost != null and timer.running and timer.lap_time <= ghost.lap_time
	visible = show_now
	if not show_now:
		_was_visible = false
		return
	var t := timer.lap_time
	global_transform = ghost.transform_at(t)
	var jumped := not _was_visible or t < _last_time
	if jumped:
		# New lap or just turned on: don't slide in from the old place.
		reset_physics_interpolation()
		_last_position = global_position
	var steer := ghost.steer_at(t)
	var d := ghost.drops_at(t)
	for i in 4:
		_wheels[i].rotation.y = steer if i < 2 else 0.0
		_visuals[i].position.y = d[i]
	# Roll the wheels at the ghost's ground speed.
	var forward_move := (global_position - _last_position).dot(-global_basis.z)
	_angle = wrapf(_angle + forward_move / time_trial.car.setup.wheel_radius, 0.0, TAU)
	for spin in _spins:
		spin.rotation.x = -_angle
	_last_position = global_position
	_last_time = t
	_was_visible = true


## Gives every mesh under node the pale see-through look, with no shadow.
func _make_see_through(node: Node) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOUR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.emission_enabled = true
	material.emission = Color(COLOUR, 1.0) * 0.3
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
