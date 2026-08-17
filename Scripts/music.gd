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

# Themes beyond the four baked tracks reuse the closest-fitting one
const GROUP_TRACK := [0, 1, 2, 3, 0, 3, 1]

func _start_playback():
	var idx: int = GROUP_TRACK[clampi(current_group, 0, GROUP_TRACK.size() - 1)]
	_player.stream = TRACKS[idx]
	_player.play()
