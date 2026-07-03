# Static completability check for GENERATED tracks: builds 320 tracks
# (80 per theme) with maxed-out difficulty params and asserts the invariants
# the generator constraints guarantee: every row transition has a climbable
# column path, gaps fit the run-up/air-time budget, gap landings are at or
# below takeoff height.
#
# The limit formulas here MIRROR LevelGenerator.chunk_begin() - keep in sync.
#
# Run:  godot --headless --path . -s tests/gen_constraints.gd
# Pass: "checked 320 tracks, 0 violations", exit code 0.
extends SceneTree

func _initialize():
	var failures := 0
	var tracks := 0
	for theme in 4:
		var grav: float = LevelGenerator.GROUP_GRAVITY[theme]
		var jv: float = LevelGenerator.GROUP_JUMP_VELOCITY[theme]
		var max_step := maxi(1, int(jv * jv / (2.0 * grav) * 0.85 / 0.5))
		var air_time := 2.0 * jv / grav
		for trial in 80:
			var p := {
				"seed": theme * 1000 + trial, "length": 400,
				"min_height": 1, "max_height": 8,
				"tunnel_weight": 25, "narrow_weight": 25,
				"gap_weight": 25, "tunnel_lane_weight": 25,
				"sharpness": [0.05, 0.1, 0.2][trial % 3],
				"theme": theme,
			}
			tracks += 1
			failures += _check(LevelGenerator.generate(p), max_step, air_time, theme, trial)
	print("checked %d tracks, %d violations" % [tracks, failures])
	quit(1 if failures > 0 else 0)

func _check(content: String, max_step: int, air_time: float, theme: int, trial: int) -> int:
	var grid: Array = []
	for line in content.split("\n"):
		if line.strip_edges() == "":
			continue
		var row: Array[int] = []
		row.resize(10)
		row.fill(0)
		for ci in range(0, mini(line.length(), 20), 2):
			var ch := line[ci]
			if ch >= "1" and ch <= "9":
				row[ci / 2] = ch.unicode_at(0) - "0".unicode_at(0)
		grid.append(row)

	var bad := 0
	var rows := grid.size()
	var r := 0
	while r < rows - 1:
		var cur: Array = grid[r]
		if _empty(cur):
			r += 1
			continue
		var nxt: Array = grid[r + 1]
		if _empty(nxt):
			var runup := 0
			var rr := r
			while rr >= 0 and not _empty(grid[rr]):
				runup += 1
				rr -= 1
			var gl := 0
			var gr := r + 1
			while gr < rows and _empty(grid[gr]):
				gl += 1
				gr += 1
			var v := minf(30.0, sqrt(2.0 * 12.0 * float(runup) * 2.0))
			var max_gap := maxi(1, int(v * air_time / 2.0) - 1)
			if gl > max_gap:
				print("  theme %d trial %d row %d: gap %d > max %d (runup %d)" % [theme, trial, r, gl, max_gap, runup])
				bad += 1
			if gr < rows and not _landable(cur, grid[gr]):
				print("  theme %d trial %d row %d: no landing at/below takeoff height" % [theme, trial, r])
				bad += 1
			r = gr
			continue
		if not _passable(cur, nxt, max_step):
			print("  theme %d trial %d row %d: wall with no climbable column (step > %d)" % [theme, trial, r, max_step])
			bad += 1
		r += 1
	return bad

func _empty(row: Array) -> bool:
	for v in row:
		if v > 0:
			return false
	return true

func _passable(a: Array, b: Array, max_step: int) -> bool:
	for c1 in 10:
		if a[c1] == 0:
			continue
		for c2 in range(maxi(0, c1 - 1), mini(10, c1 + 2)):
			if b[c2] > 0 and b[c2] - a[c1] <= max_step:
				return true
	return false

func _landable(takeoff: Array, land: Array) -> bool:
	for c1 in 10:
		if takeoff[c1] == 0:
			continue
		for c2 in range(maxi(0, c1 - 3), mini(10, c1 + 4)):
			if land[c2] > 0 and land[c2] <= takeoff[c1]:
				return true
	return false
