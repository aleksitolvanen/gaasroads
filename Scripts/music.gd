extends Node

const MIX_RATE := 44100.0

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback

var _enabled := false
var _current_group := -1

var _step := 0
var _step_time := 0.0
var _step_length := 0.12

var _mel_phase := 0.0
var _bass_phase := 0.0
var _arp_phase := 0.0

var _mel_freq := 0.0
var _bass_freq := 0.0
var _arp_freq := 0.0

var _mel_vol := 0.0
var _bass_vol := 0.0
var _arp_vol := 0.0

var _melody: Array = []
var _bass: Array = []
var _arp: Array = []

var _mel_type := 0
var _bass_type := 1
var _arp_type := 2

var _mel_decay := 0.99994
var _bass_decay := 0.99997
var _arp_decay := 0.99991

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
		_stop_playback()

func play_for_group(group: int):
	if group == _current_group:
		return
	_current_group = group
	if _enabled:
		_stop_playback()
		_start_playback()

func _start_playback():
	_step = 0
	_step_time = 0.0
	_mel_phase = 0.0
	_bass_phase = 0.0
	_arp_phase = 0.0
	_mel_vol = 0.0
	_bass_vol = 0.0
	_arp_vol = 0.0
	_load_group(_current_group)

	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.1
	_player.stream = gen
	_player.volume_db = -8
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()

func _stop_playback():
	if _player:
		_player.stop()
		_player.queue_free()
		_player = null
		_playback = null

func _process(_d):
	if _playback:
		_fill_buffer()

func _fill_buffer():
	var frames := _playback.get_frames_available()
	for i in frames:
		_step_time += 1.0 / MIX_RATE
		if _step_time >= _step_length:
			_step_time -= _step_length
			_advance()

		var s := 0.0

		if _mel_freq > 0.0 and _mel_vol > 0.005:
			_mel_phase = fmod(_mel_phase + _mel_freq / MIX_RATE, 1.0)
			s += _wave(_mel_type, _mel_phase) * _mel_vol * 0.22
			_mel_vol *= _mel_decay

		if _bass_freq > 0.0 and _bass_vol > 0.005:
			_bass_phase = fmod(_bass_phase + _bass_freq / MIX_RATE, 1.0)
			s += _wave(_bass_type, _bass_phase) * _bass_vol * 0.18
			_bass_vol *= _bass_decay

		if _arp_freq > 0.0 and _arp_vol > 0.005:
			_arp_phase = fmod(_arp_phase + _arp_freq / MIX_RATE, 1.0)
			s += _wave(_arp_type, _arp_phase) * _arp_vol * 0.13
			_arp_vol *= _arp_decay

		_playback.push_frame(Vector2(s, s))

func _wave(type: int, phase: float) -> float:
	if type == 0:
		return 1.0 if phase < 0.5 else -1.0
	elif type == 1:
		return 2.0 * phase - 1.0
	else:
		return 4.0 * absf(phase - 0.5) - 1.0

func _note_freq(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)

func _advance():
	if _melody.size() > 0:
		var n: int = _melody[_step % _melody.size()]
		if n > 0:
			_mel_freq = _note_freq(n)
			_mel_vol = 1.0
		elif n == 0:
			_mel_vol = 0.0

	if _bass.size() > 0:
		var n: int = _bass[_step % _bass.size()]
		if n > 0:
			_bass_freq = _note_freq(n)
			_bass_vol = 1.0
		elif n == 0:
			_bass_vol = 0.0

	if _arp.size() > 0:
		var n: int = _arp[_step % _arp.size()]
		if n > 0:
			_arp_freq = _note_freq(n)
			_arp_vol = 1.0
		elif n == 0:
			_arp_vol = 0.0

	_step += 1

func _load_group(group: int):
	match group:
		0: _load_cosmic()
		1: _load_nebula()
		2: _load_solar()
		3: _load_dark()
		_: _load_cosmic()

func _load_cosmic():
	# Eerie but adventurous - E minor, 115 BPM
	_step_length = 60.0 / 115.0 / 4.0
	_mel_type = 2   # triangle - soft, haunting
	_bass_type = 1  # saw - deep, rich
	_arp_type = 0   # square - pulsing atmosphere
	_mel_decay = 0.99996
	_bass_decay = 0.99998
	_arp_decay = 0.99993

	_melody = [
		# Phrase 1 - Eerie opening: E4 leap to B4, stepwise
		64, -1, 0, 0, 71, -1, -1, 0, 67, -1, 69, 0, 71, -1, -1, 0,
		# Phrase 2 - Descending mystery
		74, -1, 72, 0, 71, -1, 69, 0, 67, -1, -1, 0, 64, -1, -1, 0,
		# Phrase 3 - Building upward, adventurous
		64, -1, 0, 67, 71, -1, 0, 74, 76, -1, -1, 0, 74, -1, 71, 0,
		# Phrase 4 - Haunting resolution
		72, -1, 69, 0, 67, -1, 64, 0, 62, -1, -1, 0, 64, -1, -1, -1,
	]

	_bass = [
		40, -1, -1, -1, 47, -1, -1, -1, 43, -1, -1, -1, 47, -1, -1, -1,
		40, -1, -1, -1, 45, -1, -1, -1, 43, -1, -1, -1, 40, -1, -1, -1,
		40, -1, -1, -1, 47, -1, -1, -1, 43, -1, -1, -1, 50, -1, -1, -1,
		48, -1, -1, -1, 45, -1, -1, -1, 43, -1, -1, -1, 40, -1, -1, -1,
	]

	_arp = [
		52, 55, 59, 64, 59, 55, 52, 0,
		48, 52, 55, 60, 55, 52, 48, 0,
		45, 48, 52, 57, 52, 48, 45, 0,
		47, 50, 54, 59, 54, 50, 47, 0,
	]

func _load_nebula():
	# Mysterious, ethereal - A minor, 110 BPM
	_step_length = 60.0 / 110.0 / 4.0
	_mel_type = 2   # triangle
	_bass_type = 1  # saw
	_arp_type = 0   # square
	_mel_decay = 0.99996
	_bass_decay = 0.99998
	_arp_decay = 0.99993

	_melody = [
		69, 0, 0, 72, 0, 0, 76, 0, 0, 0, 81, 0, 79, 0, 0, 0,
		68, 0, 0, 71, 0, 0, 76, 0, 0, 0, 74, 0, 72, 0, 0, 0,
		69, 0, 0, 0, 76, 0, 0, 0, 81, 0, 79, 0, 76, 0, 72, 0,
		68, 0, 0, 0, 71, 0, 0, 0, 76, 0, 74, 0, 72, 0, 0, 0,
	]

	_bass = [
		45, -1, -1, -1, -1, -1, -1, -1, 52, -1, -1, -1, -1, -1, -1, -1,
		44, -1, -1, -1, -1, -1, -1, -1, 50, -1, -1, -1, -1, -1, -1, -1,
		45, -1, -1, -1, -1, -1, -1, -1, 52, -1, -1, -1, -1, -1, -1, -1,
		44, -1, -1, -1, -1, -1, -1, -1, 50, -1, -1, -1, -1, -1, -1, -1,
	]

	_arp = [
		57, 0, 60, 0, 64, 0, 69, 0,
		56, 0, 59, 0, 64, 0, 68, 0,
	]

func _load_solar():
	# Intense, driving - D minor, 160 BPM
	_step_length = 60.0 / 160.0 / 4.0
	_mel_type = 1   # saw
	_bass_type = 0  # square
	_arp_type = 2   # triangle
	_mel_decay = 0.99993
	_bass_decay = 0.99996
	_arp_decay = 0.99991

	_melody = [
		74, 0, 74, 0, 77, 0, 77, 0, 81, 0, 81, 0, 86, 0, 84, 0,
		82, 0, 81, 0, 79, 0, 77, 0, 74, 0, 72, 0, 74, 0, 0, 0,
		86, 0, 84, 0, 82, 0, 81, 0, 79, 0, 77, 0, 74, 0, 72, 0,
		74, 0, 77, 0, 81, 0, 84, 0, 86, 0, 0, 0, 86, 0, 0, 0,
	]

	_bass = [
		50, -1, 0, 50, -1, 0, 50, -1, 46, -1, 0, 46, -1, 0, 45, -1,
		50, -1, 0, 50, -1, 0, 50, -1, 46, -1, 0, 46, -1, 0, 45, -1,
		50, -1, 0, 50, -1, 0, 50, -1, 46, -1, 0, 46, -1, 0, 45, -1,
		50, -1, 0, 50, -1, 0, 50, -1, 48, -1, 0, 48, -1, 0, 50, -1,
	]

	_arp = [
		62, 65, 69, 74, 62, 65, 69, 74,
		58, 62, 65, 70, 57, 62, 65, 69,
	]

func _load_dark():
	# Ominous, creepy - chromatic, 90 BPM
	_step_length = 60.0 / 90.0 / 4.0
	_mel_type = 0   # square
	_bass_type = 1  # saw
	_arp_type = 2   # triangle
	_mel_decay = 0.99995
	_bass_decay = 0.99998
	_arp_decay = 0.99994

	_melody = [
		64, 0, 0, 0, 65, 0, 0, 64, 0, 0, 63, 0, 0, 0, 0, 0,
		62, 0, 0, 0, 63, 0, 0, 62, 0, 0, 60, 0, 0, 0, 0, 0,
		59, 0, 0, 0, 60, 0, 0, 59, 0, 0, 58, 0, 0, 0, 0, 0,
		57, 0, 0, 0, 58, 0, 0, 57, 0, 0, 55, 0, 0, 0, 0, 0,
	]

	_bass = [
		40, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 40, -1, -1, -1,
		39, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 38, -1, -1, -1,
		40, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 40, -1, -1, -1,
		37, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 36, -1, -1, -1,
	]

	_arp = [
		52, 0, 0, 0, 55, 0, 0, 0,
		51, 0, 0, 0, 54, 0, 0, 0,
	]
