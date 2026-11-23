class_name CarSound
extends Node
## Plays the car's engine, tire squeal and wind, mixed in code each frame
## (EngineSynth, TireSynth, WindSynth). Only the skid is a recording (car/sound/tire_skid.wav).
## Fixed mix, as heard from behind the car. M or D-pad down mutes all sound.

## Lower rate keeps the work small. Plenty for engine, squeal and wind.
const MIX_RATE := 22050.0
## Sound made ahead of time, in seconds. Shorter reacts faster but may crackle.
const BUFFER_SECONDS := 0.07

@export var car: Car
## Volume for all game sound, in dB. 0 is full, -6 is about half as loud.
@export_range(-40, 6, 0.5) var volume_db := -6.0
@export_range(-40, 6, 0.5) var engine_db := 0.0
@export_range(-40, 6, 0.5) var tire_db := -3.0
@export_range(-40, 6, 0.5) var wind_db := -6.0

var muted := false

var _engine := EngineSynth.new(MIX_RATE, 1)
var _tire := TireSynth.new(MIX_RATE, 2, TireSynth.load_samples())
var _wind := WindSynth.new(MIX_RATE, 3)
var _engine_player: AudioStreamPlayer
var _tire_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer


func _ready() -> void:
	AudioServer.set_bus_volume_db(0, volume_db)
	_engine_player = _make_player("Engine", engine_db)
	_tire_player = _make_player("Tires", tire_db)
	_wind_player = _make_player("Wind", wind_db)


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)


func _process(_delta: float) -> void:
	# Skip while a menu (the tuning panel) has focus: the D-pad moves through it then.
	if Input.is_action_just_pressed("mute_sound") and get_viewport().gui_get_focus_owner() == null:
		toggle_mute()
	if car == null or car.drivetrain == null:
		return
	var rpm := car.drivetrain.rpm()
	var speed := car.linear_velocity.length()
	var squeal := TireSynth.squeal_for_car(car)
	var n := _frames_needed(_engine_player)
	if n > 0:
		_push(_engine_player, _engine.fill(n, rpm, car.throttle))
	n = _frames_needed(_tire_player)
	if n > 0:
		_push(_tire_player, _tire.fill(n, squeal, speed))
	n = _frames_needed(_wind_player)
	if n > 0:
		_push(_wind_player, _wind.fill(n, speed))


func _make_player(player_name: String, db: float) -> AudioStreamPlayer:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = BUFFER_SECONDS
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = db
	add_child(player)
	player.play()
	return player


func _frames_needed(player: AudioStreamPlayer) -> int:
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	return playback.get_frames_available() if playback != null else 0


func _push(player: AudioStreamPlayer, frames: PackedVector2Array) -> void:
	(player.get_stream_playback() as AudioStreamGeneratorPlayback).push_buffer(frames)
