extends Node

# Frame-spike profiler. F3 toggles the overlay; spikes are always printed to
# the console (visible in the browser devtools) with the game events that
# preceded them, so hiccups can be attributed.

const SPIKE_MSEC := 40.0
const MARK_WINDOW_MSEC := 500

var _overlay: Label
var _marks: Array = []
var _spikes: Array = []
var _frames := 0
var _accum := 0.0
var _fps := 0.0

func _ready():
	var layer := CanvasLayer.new()
	layer.layer = 101
	add_child(layer)
	_overlay = Label.new()
	_overlay.visible = false
	_overlay.offset_left = 10
	_overlay.offset_top = 30
	_overlay.add_theme_font_size_override("font_size", 11)
	_overlay.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 0.9))
	layer.add_child(_overlay)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_overlay.visible = not _overlay.visible

func mark(tag: String):
	_marks.append([Time.get_ticks_msec(), tag])
	if _marks.size() > 20:
		_marks.pop_front()

func _process(delta: float):
	var ms := delta * 1000.0
	_frames += 1
	_accum += delta
	if _accum >= 0.5:
		_fps = _frames / _accum
		_frames = 0
		_accum = 0.0

	if ms > SPIKE_MSEC:
		var now := Time.get_ticks_msec()
		var recent := ""
		for m in _marks:
			if now - m[0] < MARK_WINDOW_MSEC:
				recent += m[1] + " "
		if recent == "":
			recent = "(no game events - likely browser GC / shader compile / heap growth)"
		var line := "t=%.1fs spike %dms | %s" % [now / 1000.0, int(ms), recent]
		print("[PERF] " + line)
		_spikes.append(line)
		if _spikes.size() > 6:
			_spikes.pop_front()

	if _overlay.visible:
		_overlay.text = "FPS %.0f  (F3 to hide)\n%s" % [_fps, "\n".join(PackedStringArray(_spikes))]
