extends Node

# Held here so the textures stay cached for the whole session instead of
# being re-decoded on every scene change.
var cockpit_texture: Texture2D = preload("res://cockpit.png")
var background_texture: Texture2D = preload("res://background.png")

var selected_level := "res://Levels/nebula_1.txt"
var selected_group := 1
var generated_content := ""
var is_endless := false
var endless_params := {}
var gen_params := {}
var elapsed_time := 0.0
var endless_best_dist := 0.0
var custom_idx := [2, 2, 1, 1, 0, 2, 1, 2]
var sfx_enabled := true
var classical_mode := true
var autopilot := false
var menu_group := 1
var menu_track := 0
var ship_style := 0
# Only menu-launched tracks may record completions/best times; imported or
# file-loaded tracks have no menu identity to record against.
var run_records := false

var save_path := "user://completed.cfg"
var _completed: Dictionary = {}
var _best_times: Dictionary = {}

func _ready():
	_load()

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
	# Share codes are pasted clipboard text: clamp every field to the ranges
	# the settings screen offers, or a hostile length hangs the generator.
	return {
		"length": clampi(parts[1].to_int(), 1, 2000),
		"max_height": clampi(parts[2].to_int(), 2, 8),
		"tunnel_weight": clampi(parts[3].to_int(), 0, 50),
		"narrow_weight": clampi(parts[4].to_int(), 0, 50),
		"gap_weight": clampi(parts[5].to_int(), 0, 50),
		"tunnel_lane_weight": clampi(parts[6].to_int(), 0, 50),
		"sharpness": clampf(parts[7].to_float(), 0.01, 0.5),
		"theme": clampi(parts[8].to_int(), 0, LevelGenerator.GROUP_GRAVITY.size() - 1),
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
	config.save(save_path)

func _load():
	var config := ConfigFile.new()
	if config.load(save_path) == OK:
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
