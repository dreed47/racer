class_name EngineSynth
extends RefCounted
## Makes engine sound in code for a four-cylinder, four-stroke engine: two firings per turn.
## Each firing is a short pressure pulse. The four cylinders differ a little, which gives the
## uneven burble under the main note. More throttle makes it louder, brighter and rougher.

const CYLINDERS := 4
## Pulse strength of each cylinder, in firing order.
const CYLINDER_MIX: Array[float] = [1.0, 0.9, 0.97, 0.86]
## How fast each pulse dies away. Higher sounds sharper.
const PULSE_DECAY := 6.0
## Mean of exp(-PULSE_DECAY * p) over one pulse, taken off to keep the wave centred.
const PULSE_MEAN := (1.0 - 0.0024787522) / PULSE_DECAY
## Tone filter in Hz, throttle shut and wide open.
const TONE_CLOSED := 500.0
const TONE_OPEN := 2600.0
## How fast rpm and throttle follow the car, in Hz. Stops clicks when they jump.
const FOLLOW := 25.0

var mix_rate: float
var _rpm := 900.0
var _throttle := 0.0
var _phase := 0.0
var _cylinder := 0
var _low := 0.0
var _dc := 0.0
var _rng := RandomNumberGenerator.new()


func _init(rate: float, seed_value := 0) -> void:
	mix_rate = rate
	_rng.seed = seed_value


## Firing pulses per second at this rpm: the main note.
static func firing_hz(rpm: float) -> float:
	return rpm / 60.0 * CYLINDERS / 2.0


## Returns `frames` stereo samples for the given engine speed and throttle (0 to 1).
func fill(frames: int, rpm: float, throttle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	var follow := 1.0 - exp(-TAU * FOLLOW / mix_rate)
	var dc_follow := 1.0 - exp(-TAU * 20.0 / mix_rate)
	for i in frames:
		_rpm += (maxf(rpm, 0.0) - _rpm) * follow
		_throttle += (clampf(throttle, 0.0, 1.0) - _throttle) * follow
		_phase += firing_hz(_rpm) / mix_rate
		if _phase >= 1.0:
			_phase -= 1.0
			_cylinder = (_cylinder + 1) % CYLINDERS
		var pulse := exp(-PULSE_DECAY * _phase)
		var x := (pulse - PULSE_MEAN) * CYLINDER_MIX[_cylinder]
		x += _rng.randf_range(-1.0, 1.0) * pulse * (0.1 + 0.35 * _throttle)  # Combustion roar.
		var tone := lerpf(TONE_CLOSED, TONE_OPEN, _throttle) * (0.7 + _rpm / 10000.0)
		_low += (x - _low) * (1.0 - exp(-TAU * tone / mix_rate))
		_dc += (_low - _dc) * dc_follow
		var drive := 1.5 + 2.5 * _throttle
		var s := tanh((_low - _dc) * drive) * (0.45 + 0.55 * _throttle)
		out[i] = Vector2(s, s)
	return out
