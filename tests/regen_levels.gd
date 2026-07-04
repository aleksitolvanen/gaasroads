# Regenerates authored level files from the current generator with fixed
# seeds, so the shipped set is reproducible. Originals are archived in
# raw/levels_original/. After changing seeds or params, re-run and verify:
#   godot --headless --path . -s tests/regen_levels.gd
#   python solve_level.py Levels/nebula_1.txt ... (all must be COMPLETABLE)
extends SceneTree

const SETS := {
	"nebula": [
		{"seed": 1101, "difficulty": 0.45, "length": 120, "max_height": 3, "tunnel_weight": 5, "narrow_weight": 10, "gap_weight": 8, "tunnel_lane_weight": 4, "sharpness": 0.12, "theme": 1},
		{"seed": 1202, "difficulty": 0.6, "length": 180, "max_height": 4, "tunnel_weight": 8, "narrow_weight": 20, "gap_weight": 8, "tunnel_lane_weight": 6, "sharpness": 0.10, "theme": 1},
		{"seed": 1303, "finale": 0, "difficulty": 0.72, "length": 240, "max_height": 4, "tunnel_weight": 8, "narrow_weight": 12, "gap_weight": 20, "tunnel_lane_weight": 8, "sharpness": 0.10, "theme": 1},
		{"seed": 1404, "finale": 0, "difficulty": 0.85, "length": 300, "max_height": 5, "tunnel_weight": 22, "narrow_weight": 14, "gap_weight": 12, "tunnel_lane_weight": 16, "sharpness": 0.08, "theme": 1},
		{"seed": 1505, "finale": 0, "difficulty": 1.0, "length": 380, "max_height": 6, "tunnel_weight": 18, "narrow_weight": 24, "gap_weight": 18, "tunnel_lane_weight": 14, "sharpness": 0.08, "theme": 1},
	],
	"solar": [
		{"seed": 2101, "difficulty": 0.45, "length": 130, "max_height": 4, "tunnel_weight": 5, "narrow_weight": 8, "gap_weight": 10, "tunnel_lane_weight": 4, "sharpness": 0.12, "theme": 2},
		{"seed": 2202, "difficulty": 0.6, "length": 190, "max_height": 5, "tunnel_weight": 6, "narrow_weight": 10, "gap_weight": 18, "tunnel_lane_weight": 6, "sharpness": 0.10, "theme": 2},
		{"seed": 2303, "finale": 0, "difficulty": 0.72, "length": 250, "max_height": 6, "tunnel_weight": 8, "narrow_weight": 16, "gap_weight": 14, "tunnel_lane_weight": 8, "sharpness": 0.10, "theme": 2},
		{"seed": 2404, "finale": 0, "difficulty": 0.85, "length": 310, "max_height": 6, "tunnel_weight": 20, "narrow_weight": 12, "gap_weight": 14, "tunnel_lane_weight": 14, "sharpness": 0.08, "theme": 2},
		{"seed": 2505, "finale": 0, "difficulty": 1.0, "length": 390, "max_height": 8, "tunnel_weight": 16, "narrow_weight": 22, "gap_weight": 20, "tunnel_lane_weight": 12, "sharpness": 0.08, "theme": 2},
	],
}

func _initialize():
	for prefix in SETS:
		var configs: Array = SETS[prefix]
		for i in configs.size():
			var p: Dictionary = configs[i].duplicate()
			p["min_height"] = 1
			var content: String = LevelGenerator.generate(p)
			var path := "res://Levels/%s_%d.txt" % [prefix, i + 1]
			var fa := FileAccess.open(path, FileAccess.WRITE)
			fa.store_string(content)
			fa.close()
			print("%s: %d rows (seed %d)" % [path, content.split("\n").size(), p["seed"]])
	quit()
