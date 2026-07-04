# Generates sample tracks to tests/samples/*.txt for eyeballing and for
# running solve_level.py against. Not a pass/fail test.
#
# Run:  godot --headless --path . -s tests/dump_tracks.gd
extends SceneTree

func _initialize():
	DirAccess.make_dir_recursive_absolute("res://tests/samples")
	var configs := [
		["basic_gen", {"seed": 11, "length": 200, "max_height": 4, "tunnel_weight": 10, "narrow_weight": 15, "gap_weight": 10, "tunnel_lane_weight": 8, "sharpness": 0.12, "theme": 1}],
		["nebula_gen", {"seed": 22, "length": 250, "max_height": 5, "tunnel_weight": 10, "narrow_weight": 20, "gap_weight": 12, "tunnel_lane_weight": 8, "sharpness": 0.10, "theme": 1}],
		["solar_gen", {"seed": 33, "length": 300, "max_height": 5, "tunnel_weight": 20, "narrow_weight": 10, "gap_weight": 15, "tunnel_lane_weight": 15, "sharpness": 0.10, "theme": 2}],
		["dark_gen", {"seed": 44, "length": 300, "max_height": 6, "tunnel_weight": 15, "narrow_weight": 25, "gap_weight": 15, "tunnel_lane_weight": 10, "sharpness": 0.08, "theme": 3}],
		["hard_gen", {"seed": 55, "length": 400, "max_height": 8, "tunnel_weight": 25, "narrow_weight": 30, "gap_weight": 20, "tunnel_lane_weight": 20, "sharpness": 0.05, "theme": 1}],
	]
	for c in configs:
		var content: String = LevelGenerator.generate(c[1])
		var fa := FileAccess.open("res://tests/samples/%s.txt" % c[0], FileAccess.WRITE)
		fa.store_string(content)
		fa.close()
		print("%s: %d rows" % [c[0], content.split("\n").size()])
	quit()
