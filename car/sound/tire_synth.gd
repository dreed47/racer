class_name TireSynth
extends RefCounted
## Makes the tire sound:
## - Road: a soft low rumble from rolling on the road, made in code, growing with speed.
## - Skid: a recorded tire skid (car/sound/tire_skid.wav) played in a loop. It fades in when
##   a tire nears its grip limit (yellow in the grip display) and is loudest when it slides
##   (red). Its pitch rises a little with how hard the tire slides.
## No skid sound on grass or gravel.

## The recorded skid. Imported as plain PCM so its samples can be read.
const SKID_PATH := "res://car/sound/tire_skid.wav"
## Slip level where the skid starts (grip display yellow), and where it's at full volume.
const START := 0.8
const FULL := 1.6
## Below this grip the ground is soft (grass, gravel) and doesn't squeal.
const MIN_SURFACE_GRIP := 0.85
## Below this speed in m/s there's no squeal.
const MIN_SPEED := 2.0
## Speed in m/s where road rumble is at full volume.
const ROAD_FULL_SPEED := 40.0
const FOLLOW := 12.0

## Skid loudness at a full slide, 0 to 1. Kept below the engine so it doesn't take over.
var skid_level := 0.5
## How fast the skid loudness grows: above 1 keeps light slides quiet.
var skid_curve := 1.6
## Skid pitch at the start of a slide and at a full slide (1 is as recorded).
var skid_pitch_low := 0.94
var skid_pitch_high := 1.06
## Road rumble: centre in Hz, how narrow (higher is narrower), and level.
var road_hz := 140.0
var road_q := 0.8
var road_level := 0.25

var mix_rate: float
var _skid := PackedFloat32Array()
var _skid_step := 1.0
var _pos := 0.0
var _amount := 0.0
var _speed := 0.0
var _road := _Band.new()
var _rng := RandomNumberGenerator.new()


## A resonant band-pass filter (state-variable type).
class _Band:
	var low := 0.0
	var band := 0.0

	func step(x: float, hz: float, q: float, rate: float) -> float:
		var f := 2.0 * sin(PI * minf(hz, rate / 6.0) / rate)
		var high := x - low - band / q
		band += f * high
		low += f * band
		return band


## `skid` is the recorded loop as mono samples from -1 to 1, recorded at `skid_rate` Hz.
## Leave it empty for road rumble only.
func _init(rate: float, seed_value := 0, skid := PackedFloat32Array(), skid_rate := 22050.0) -> void:
	mix_rate = rate
	_rng.seed = seed_value
	_skid = skid
	_skid_step = skid_rate / rate


## Reads a 16-bit PCM WAV resource into mono samples from -1 to 1. Empty if it can't.
static func load_samples(path := SKID_PATH) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var wav := load(path) as AudioStreamWAV
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS:
		push_warning("TireSynth: %s missing or not 16-bit PCM" % path)
		return out
	var data := wav.data
	var channels := 2 if wav.stereo else 1
	var count := data.size() / (2 * channels)
	out.resize(count)
	for i in count:
		out[i] = data.decode_s16(i * 2 * channels) / 32768.0
	return out


## How much one tire slides, 0 to 1.
static func squeal_for(slip_level: float, surface_grip: float, speed: float, on_ground: bool) -> float:
	if not on_ground or surface_grip < MIN_SURFACE_GRIP or speed < MIN_SPEED:
		return 0.0
	return clampf((slip_level - START) / (FULL - START), 0.0, 1.0)


## How much the whole car slides: the loudest tire.
static func squeal_for_car(car: Car) -> float:
	var speed := car.linear_velocity.length()
	var most := 0.0
	for wheel in car.wheels:
		most = maxf(most, squeal_for(wheel.slip_level, wheel.surface_grip, speed, wheel.on_ground))
	return most


## Returns `frames` stereo samples for a slide amount from 0 to 1 and a speed in m/s.
func fill(frames: int, amount: float, speed := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	var follow := 1.0 - exp(-TAU * FOLLOW / mix_rate)
	var size := _skid.size()
	for i in frames:
		_amount += (clampf(amount, 0.0, 1.0) - _amount) * follow
		_speed += (absf(speed) - _speed) * follow
		var rolling := clampf(_speed / ROAD_FULL_SPEED, 0.0, 1.0)
		if _amount < 0.0005 and rolling < 0.01:
			out[i] = Vector2.ZERO
			continue
		var white := _rng.randf_range(-1.0, 1.0)
		var s := _road.step(white, road_hz * (0.7 + 0.6 * rolling), road_q, mix_rate) * road_level * rolling
		if size > 1 and _amount >= 0.0005:
			# Play the loop with linear interpolation, sped up a little as the slide grows.
			var k := int(_pos)
			var t := _pos - k
			var sample := lerpf(_skid[k], _skid[(k + 1) % size], t)
			s += sample * skid_level * pow(_amount, skid_curve)
			_pos = fmod(_pos + _skid_step * lerpf(skid_pitch_low, skid_pitch_high, _amount), size)
		s = clampf(s, -1.0, 1.0)
		out[i] = Vector2(s, s)
	return out
