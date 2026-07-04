# Generates sample tracks to tests/samples/*.txt for eyeballing, for
# running solve_level.py against, and for analyze_levels.py texture
# comparison vs the SkyRoads reference set. Not a pass/fail test.
#
# Run:  godot --headless --path . -s tests/dump_tracks.gd
#       python analyze_levels.py "tests/samples/*.txt" --summary
#       python analyze_levels.py "tests/skyroads/road_*.txt" --summary
extends SceneTree

func _initialize():
	DirAccess.make_dir_recursive_absolute("res://tests/samples")
	var configs := []
	# grid: theme x difficulty x 2 seeds, mid-strength weights
	for theme in [1, 2, 3]:
		for d in [0.5, 0.75, 1.0, 1.2]:
			for s in 2:
				configs.append(["t%d_d%02d_s%d" % [theme, int(d * 100), s], {
					"seed": theme * 10000 + int(d * 100) * 10 + s,
					"difficulty": d, "length": 250, "min_height": 1,
					"max_height": 4 + theme, "tunnel_weight": 12,
					"narrow_weight": 15, "gap_weight": 14,
					"tunnel_lane_weight": 8, "sharpness": 0.1, "theme": theme,
				}])
	# a few lottery (no pinned difficulty) rolls, like endless mode gets
	for s in 4:
		configs.append(["lottery_s%d" % s, {
			"seed": 777 + s, "length": 250, "min_height": 1, "max_height": 6,
			"tunnel_weight": 12, "narrow_weight": 15, "gap_weight": 14,
			"tunnel_lane_weight": 8, "sharpness": 0.1, "theme": 1,
		}])
	for c in configs:
		var content: String = LevelGenerator.generate(c[1])
		var fa := FileAccess.open("res://tests/samples/%s.txt" % c[0], FileAccess.WRITE)
		fa.store_string(content)
		fa.close()
	print("dumped %d tracks to tests/samples/" % configs.size())
	quit()
