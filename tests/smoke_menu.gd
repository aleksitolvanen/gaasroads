# Menu smoke test: home screen builds with 5 groups, every sub-screen opens
# and closes, settings rows adjust, and launching a track loads the game
# scene with the right group/level selected.
#
# Run:  godot --headless --path . -s tests/smoke_menu.gd
# Pass: "MENU SMOKE OK".
extends SceneTree

var _phase := 0
var _deadline := 0

func _process(_delta) -> bool:
	if _phase == 0:
		_phase = 1
		_deadline = Time.get_ticks_msec() + 15000
		change_scene_to_file("res://Scenes/MainMenu.tscn")
		return false
	if Time.get_ticks_msec() > _deadline:
		printerr("FAIL: timeout in phase %d" % _phase)
		quit(1)
		return true
	var scene = current_scene
	if scene == null:
		return false
	if _phase == 1 and scene is Control:
		assert(scene._home_names.size() == 5, "expected 5 home entries")
		for g in 4:
			scene._open_group(g)
			assert(scene._sub_labels.size() > 0, "no rows for group %d" % g)
			scene._close_sub()
		scene._open_group(4)
		assert(scene._sub_labels.size() == 8, "expected 8 settings rows")
		scene._adjust_custom(1)
		scene._adjust_custom(-1)
		scene._close_sub()
		print("home + sub screens OK")
		scene._open_group(0)
		scene._track = 1
		scene._start_game()
		_phase = 2
		return false
	if _phase == 2 and scene is Node3D:
		var gs = root.get_node("GameState")
		assert(gs.selected_group == 1, "nebula group expected, got %d" % gs.selected_group)
		assert(gs.selected_level == "res://Levels/nebula_2.txt", "wrong level: %s" % gs.selected_level)
		assert(gs.menu_group == 1 and gs.menu_track == 1, "save ids wrong")
		print("launched %s (group %d)" % [gs.selected_level, gs.selected_group])
		print("MENU SMOKE OK")
		return true
	return false
