class_name CarLook
extends Node3D
## Puts the car's 3D model on the physics car: wheels on the wheel nodes, a turning steering
## wheel and brake lights. Looks only; the physics never reads anything here.
## The model is a child named "Model" (an imported .glb, made by tools/blender/build_roadster.py)
## holding meshes named wheel, caliper, steering_wheel and brake_lights.

## Steering wheel turns per road wheel turn.
const STEERING_RATIO := 8.0
## Brake light glow at full brake.
const BRAKE_GLOW := 4.0
## Wheel radius the model was made for, in metres.
const MODEL_WHEEL_RADIUS := 0.29

@export var car: Car

var _steering_wheel: Node3D
var _steering_rest := Basis.IDENTITY
var _brake_material: StandardMaterial3D
var _visuals: Array[Node3D] = []


func _ready() -> void:
	var model := $Model
	var wheel := model.find_child("wheel", true, false) as MeshInstance3D
	var caliper := model.find_child("caliper", true, false) as MeshInstance3D
	# Runs before the car's own _ready, so go by node name: WheelFR and WheelRR are on the right.
	for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var visual := car.get_node(wheel_name + "/Visual") as Node3D
		var spin := visual.get_node("Spin") as Node3D
		var right: bool = wheel_name.ends_with("R")
		var turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) if right else Transform3D.IDENTITY
		var copy := wheel.duplicate() as MeshInstance3D
		copy.transform = turn
		spin.add_child(copy)
		var brake := caliper.duplicate() as MeshInstance3D
		brake.transform = turn
		visual.add_child(brake)
		_visuals.append(visual)
	wheel.visible = false
	caliper.visible = false

	_steering_wheel = model.find_child("steering_wheel", true, false)
	_steering_rest = _steering_wheel.basis

	var lights := model.find_child("brake_lights", true, false) as MeshInstance3D
	_brake_material = lights.mesh.surface_get_material(0).duplicate()
	_brake_material.emission_enabled = true
	_brake_material.emission = _brake_material.albedo_color
	_brake_material.emission_energy_multiplier = 0.0
	lights.material_override = _brake_material


func _process(_delta: float) -> void:
	var size := car.setup.wheel_radius / MODEL_WHEEL_RADIUS
	for visual in _visuals:
		visual.scale = Vector3.ONE * size
	var steer: float = car.wheels[0].steer_angle
	_steering_wheel.basis = _steering_rest * Basis(Vector3.BACK, steer * STEERING_RATIO)
	_brake_material.emission_energy_multiplier = car.brake * BRAKE_GLOW
