extends Node

# Tracks are baked by bake_music.py (offline port of the original synth).
const TRACKS: Array[AudioStream] = [
	preload("res://Music/cosmic.ogg"),
	preload("res://Music/nebula.ogg"),
	preload("res://Music/solar.ogg"),
	preload("res://Music/dark.ogg"),
]

var enabled := false
var current_group := -1
var _player: AudioStreamPlayer

func _ready():
	for track in TRACKS:
		track.loop = true
	_player = AudioStreamPlayer.new()
	_player.volume_db = -8
	add_child(_player)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			toggle()

func toggle():
	enabled = not enabled
	if enabled:
		if current_group >= 0:
			_start_playback()
	else:
		_player.stop()

func play_for_group(group: int):
	if group == current_group:
		return
	current_group = group
	if enabled:
		_start_playback()

func _start_playback():
	_player.stream = TRACKS[clampi(current_group, 0, TRACKS.size() - 1)]
	_player.play()
