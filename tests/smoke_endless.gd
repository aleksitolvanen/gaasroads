# Endless mode smoke test: tunnel arches built through the job queue,
# a chunk generated incrementally mid-run, passed track freed behind the
# ship, and a forced explosion cycling through fresh-track + GET READY.
#
# Run:  godot --headless --path . -s tests/smoke_endless.gd
# Pass: "ENDLESS SMOKE OK". (Autopilot crashes mid-test are fine - the
# death/reset path is part of what's being exercised.)
extends SceneTree

var _phase := 0
var _deadline := 0
var _grid_after_ready := 0

func _tunnel_count(game) -> int:
	var n := 0
	for row in game._tunnels:
		for v in row:
			if v:
				n += 1
	return n

func _process(_delta) -> bool:
	if _phase == 0:
		_phase = 1
		_deadline = Time.get_ticks_msec() + 15000
		var gs = root.get_node("GameState")
		gs.selected_group = 0
		gs.is_generated = true
		gs.is_endless = true
		gs.endless_params = {"length": 300, "min_height": 1, "max_height": 1, "tunnel_weight": 30, "narrow_weight": 0, "gap_weight": 0, "tunnel_lane_weight": 20, "sharpness": 0.1, "theme": 0, "seed": 4242}
		# find a seed whose track has tunnels, so arch jobs get exercised
		while true:
			gs.generated_content = LevelGenerator.generate(gs.endless_params)
			if "T" in gs.generated_content:
				break
			gs.endless_params["seed"] += 1
		gs.autopilot = true
		change_scene_to_file("res://Scenes/Game.tscn")
		return false
	if Time.get_ticks_msec() > _deadline:
		printerr("FAIL: timeout in phase %d" % _phase)
		quit(1)
		return true
	var game = current_scene
	if game == null or game.get_class() != "Node3D":
		return false
	match _phase:
		1:
			if game._level_ready:
				_grid_after_ready = game._grid.size()
				var tn := _tunnel_count(game)
				print("ready: grid=%d rows, tunnels=%d tiles, tracked=%d, nodes=%d" % [_grid_after_ready, tn, game._spawned_track.size(), game.get_node("Level").get_child_count()])
				assert(tn > 0, "expected tunnel tiles so arch jobs get exercised")
				assert(game._spawned_track.size() > 0, "endless must track spawned nodes")
				_deadline = Time.get_ticks_msec() + 30000
				_phase = 2
		2:
			if game._grid.size() > _grid_after_ready and game._ship.global_position.z < -90.0:
				print("chunk appended: grid=%d, ship z=%.0f, tracked=%d, nodes=%d" % [game._grid.size(), game._ship.global_position.z, game._spawned_track.size(), game.get_node("Level").get_child_count()])
				game._ship.start_explosion()
				_deadline = Time.get_ticks_msec() + 10000
				_phase = 3
		3:
			if not game._level_ready:
				print("rebuild started (GET READY): grid=%d chunk_state_empty=%s queue=%d" % [game._grid.size(), str(game._chunk_state.is_empty()), game._build_queue.size()])
				_phase = 4
		4:
			if not game._level_ready:
				return false
			if true:
				print("fresh track: grid=%d, ship z=%.1f, end_z=%.0f, tracked=%d, nodes=%d, chunk_empty=%s" % [game._grid.size(), game._ship.global_position.z, game._level_end_z, game._spawned_track.size(), game.get_node("Level").get_child_count(), str(game._chunk_state.is_empty())])
				assert(game._grid.size() < _grid_after_ready + 100, "grid should be fresh after endless reset")
				assert(absf(game._ship.global_position.z) < 30.0, "ship not back at start")
				assert(not game._ship.frozen, "ship still frozen")
				print("ENDLESS SMOKE OK")
				return true
	return false
