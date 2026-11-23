class_name WindSynth
extends RefCounted
## Makes wind noise in code: filtered noise that gets louder and brighter with speed,
## with slow gusts.

## Speed in m/s where the wind reaches full volume (about 216 km/h).
const FULL_SPEED := 60.0
const FOLLOW := 5.0

var mix_rate: float
var _speed := 0.0
var _low := 0.0
var _gust := 0.0
var _rng := RandomNumberGenerator.new()


func _init(rate: float, seed_value := 0) -> void:
	mix_rate = rate
	_rng.seed = seed_value


## Returns `frames` stereo samples for a car speed in m/s.
func fill(frames: int, speed: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	var follow := 1.0 - exp(-TAU * FOLLOW / mix_rate)
	for i in frames:
		_speed += (absf(speed) - _speed) * follow
		var level := clampf(_speed / FULL_SPEED, 0.0, 1.0)
		if level < 0.01:
			out[i] = Vector2.ZERO
			continue
		var cutoff := 150.0 + 1200.0 * level
		_low += (_rng.randf_range(-1.0, 1.0) - _low) * (1.0 - exp(-TAU * cutoff / mix_rate))
		_gust = clampf(_gust + _rng.randf_range(-1.0, 1.0) * 0.0004, -1.0, 1.0)
		var s := _low * level * level * (2.0 + 0.4 * _gust)
		out[i] = Vector2(s, s)
	return out
