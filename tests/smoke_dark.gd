# Dark Matter theme smoke test: loads dark_1, checks the ship stays frozen
# behind GET READY while the build queue drains, then that fighters exist
# and the ship actually flies.
#
# Run:  godot --headless --path . -s tests/smoke_dark.gd
# Pass: "DARK SMOKE OK".
extends SceneTree

var _phase := 0
var _deadline := 0
var _t_ready := 0

func _process(_delta) -> bool:
	if _phase == 0:
		_phase = 1
		_deadline = Time.get_ticks_msec() + 10000
		var gs = root.get_node("GameState")
		gs.selected_level = "res://Levels/dark_1.txt"
		gs.selected_group = 3
		change_scene_to_file("res://Scenes/Game.tscn")
		return false
	if Time.get_ticks_msec() > _deadline:
		printerr("FAIL: timeout in phase %d" % _phase)
		quit(1)
		return true
	var game = current_scene
	if game == null or game.get_class() != "Node3D":
		return false
	if _phase == 1:
		if not game._level_ready:
			assert(game._ship.frozen, "ship must be frozen while building")
			return false
		print("ready: level nodes=%d, queue drained=%s" % [game.get_node("Level").get_child_count(), str(game._build_queue.is_empty())])
		assert(game.get_node("Level").get_child_count() > 0, "no level nodes built")
		assert(not game._ship.frozen, "ship still frozen after ready")
		_t_ready = Time.get_ticks_msec()
		_deadline = _t_ready + 10000
		_phase = 2
		return false
	if _phase == 2 and Time.get_ticks_msec() >= _t_ready + 2500:
		print("fighters: %d" % game._fighters.size())
		print("ship z after 2.5s: %.1f" % game._ship.global_position.z)
		assert(game._fighters.size() == 8, "fighters missing")
		assert(game._ship.global_position.z < -20.0, "ship did not move")
		print("DARK SMOKE OK")
		return true
	return false
