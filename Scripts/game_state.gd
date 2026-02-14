extends Node

var selected_level := "res://Levels/level1.txt"
var selected_group := 0
var selected_track := 0

const SAVE_PATH := "user://completed.cfg"
var _completed: Dictionary = {}

func _ready():
	_load_completed()

func is_completed(group: int, track: int) -> bool:
	return _completed.get("%d_%d" % [group, track], false)

func mark_completed(group: int, track: int):
	_completed["%d_%d" % [group, track]] = true
	_save_completed()

func _save_completed():
	var config := ConfigFile.new()
	for key in _completed:
		config.set_value("completed", key, true)
	config.save(SAVE_PATH)

func _load_completed():
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		for key in config.get_section_keys("completed"):
			_completed[key] = true
