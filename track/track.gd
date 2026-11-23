class_name Track
extends Node3D
## A place to drive with a start line and checkpoints. Knows nothing about game modes.
## Every track has a "Spawn" child (Node3D) where the car starts, -Z forward.
## Surfaces tell the wheels how grippy they are through "grip" and "rolling_resistance"
## metadata on their bodies.

## Name that keeps each track's best laps apart.
@export var track_id := ""


## Lap length in metres, along the centreline.
func lap_length() -> float:
	return 0.0


## Where the start line is, as a distance along the lap. Distances wrap round the lap.
func start_line_distance() -> float:
	return 0.0


## Centreline point at a distance along the lap, in world space.
func point_at(_distance: float) -> Vector3:
	return Vector3.ZERO


## Driving direction at a distance along the lap, in world space.
func direction_at(_distance: float) -> Vector3:
	return Vector3.FORWARD


## Start/finish line is gate 0. Checkpoints follow, in driving order.
func gate_count() -> int:
	return 0


## Gate position, facing the driving direction (-Z forward), in world space.
func gate(_index: int) -> Transform3D:
	return Transform3D.IDENTITY


## Half the width a gate covers, measured from the centreline.
func gate_half_width() -> float:
	return 5.0
