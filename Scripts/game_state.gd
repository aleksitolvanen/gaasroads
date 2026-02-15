extends Node

var selected_level := "res://Levels/level1.txt"
var selected_group := 0
var selected_track := 0
var generated_content := ""
var is_generated := false
var is_endless := false
var endless_params := {}
var gen_params := {}
var elapsed_time := 0.0
var endless_best_dist := 0.0
var custom_idx := [2, 2, 1, 1, 0, 2, 1, 2]
var sfx_enabled := true
var classical_mode := false
var menu_group := 0
var menu_track := 0

const SAVE_PATH := "user://completed.cfg"
var _completed: Dictionary = {}
var _best_times: Dictionary = {}
var _status_label: Label

func _ready():
	_load()
	_build_status_overlay()

func _process(_delta):
	if _status_label:
		var music_str := "ON" if Music._enabled else "OFF"
		var sfx_str := "ON" if sfx_enabled else "OFF"
		var mode_str := "Classical" if classical_mode else "Normal"
		_status_label.text = "Music: %s | Sounds: %s | Mode: %s" % [music_str, sfx_str, mode_str]

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			sfx_enabled = not sfx_enabled
		elif event.keycode == KEY_B:
			classical_mode = not classical_mode

func _build_status_overlay():
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_status_label = Label.new()
	_status_label.anchor_left = 1
	_status_label.anchor_right = 1
	_status_label.anchor_top = 1
	_status_label.anchor_bottom = 1
	_status_label.offset_left = -320
	_status_label.offset_top = -24
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.7))
	_status_label.add_theme_font_size_override("font_size", 11)
	layer.add_child(_status_label)

func is_completed(group: int, track: int) -> bool:
	return _completed.get("%d_%d" % [group, track], false)

func get_best_time(group: int, track: int) -> float:
	return _best_times.get("%d_%d" % [group, track], 0.0)

func format_time(t: float) -> String:
	if t <= 0.0:
		return ""
	var mins := int(t) / 60
	var secs := int(t) % 60
	var ms := int(fmod(t, 1.0) * 100)
	return "%d:%02d.%02d" % [mins, secs, ms]

func encode_share_code(params: Dictionary) -> String:
	# Format: GAAS:length:max_height:tunnel_weight:narrow_weight:gap_weight:tunnel_lane_weight:sharpness:theme:seed
	return "GAAS:%d:%d:%d:%d:%d:%d:%.2f:%d:%d" % [
		params.get("length", 200),
		params.get("max_height", 4),
		params.get("tunnel_weight", 10),
		params.get("narrow_weight", 15),
		params.get("gap_weight", 10),
		params.get("tunnel_lane_weight", 8),
		params.get("sharpness", 0.12),
		params.get("theme", 0),
		params.get("seed", 0),
	]

func decode_share_code(code: String) -> Dictionary:
	var parts := code.strip_edges().split(":")
	if parts.size() < 10 or parts[0] != "GAAS":
		return {}
	return {
		"length": parts[1].to_int(),
		"max_height": parts[2].to_int(),
		"tunnel_weight": parts[3].to_int(),
		"narrow_weight": parts[4].to_int(),
		"gap_weight": parts[5].to_int(),
		"tunnel_lane_weight": parts[6].to_int(),
		"sharpness": parts[7].to_float(),
		"theme": parts[8].to_int(),
		"seed": parts[9].to_int(),
		"min_height": 1,
	}

func save_endless_best(dist: float):
	if dist > endless_best_dist:
		endless_best_dist = dist
		_save()

func mark_completed(group: int, track: int):
	var key := "%d_%d" % [group, track]
	_completed[key] = true
	if elapsed_time > 0.0:
		var prev: float = _best_times.get(key, 0.0)
		if prev <= 0.0 or elapsed_time < prev:
			_best_times[key] = elapsed_time
	_save()

func save_custom_idx():
	_save()

func _save():
	var config := ConfigFile.new()
	for key in _completed:
		config.set_value("completed", key, true)
	for key in _best_times:
		config.set_value("times", key, _best_times[key])
	for i in custom_idx.size():
		config.set_value("custom", str(i), custom_idx[i])
	if endless_best_dist > 0.0:
		config.set_value("endless", "best_dist", endless_best_dist)
	config.save(SAVE_PATH)

func _load():
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		if config.has_section("completed"):
			for key in config.get_section_keys("completed"):
				_completed[key] = true
		if config.has_section("times"):
			for key in config.get_section_keys("times"):
				_best_times[key] = config.get_value("times", key)
		if config.has_section("custom"):
			for i in custom_idx.size():
				if config.has_section_key("custom", str(i)):
					custom_idx[i] = config.get_value("custom", str(i))
		if config.has_section_key("endless", "best_dist"):
			endless_best_dist = config.get_value("endless", "best_dist")
