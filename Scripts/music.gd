extends Node

# Tracks are baked by bake_music.py (offline port of the original synth).
const TRACKS: Array[AudioStream] = [
	preload("res://Music/cosmic.ogg"),
	preload("res://Music/nebula.ogg"),
	preload("res://Music/solar.ogg"),
	preload("res://Music/dark.ogg"),
]

var _player: AudioStreamPlayer
var _enabled := false
var _current_group := -1

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
	_enabled = not _enabled
	if _enabled:
		if _current_group >= 0:
			_start_playback()
	else:
		_player.stop()

func play_for_group(group: int):
	if group == _current_group:
		return
	_current_group = group
	if _enabled:
		_start_playback()

func _start_playback():
	_player.stream = TRACKS[clampi(_current_group, 0, TRACKS.size() - 1)]
	_player.play()
