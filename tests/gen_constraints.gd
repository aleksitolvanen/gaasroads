# Static completability check for GENERATED tracks: builds 320 tracks
# (80 per theme) with maxed-out difficulty params and asserts the invariants
# the generator guarantees: every row transition has a climbable column path,
# gaps fit the run-up/air-time budget, gap landings are at or below takeoff
# height, and tunnel bores are flat, gap-free and enterable without a jump.
#
# Limits come from LevelGenerator.jump_limits() / _max_gap_rows() - the same
# formulas the generator itself uses - and the ship performance constants are
# asserted against ship.gd's export defaults, so drift fails loudly here.
#
# Run:  godot --headless --path . -s tests/gen_constraints.gd
# Pass: "checked 320 tracks, 0 violations", exit code 0.
extends SceneTree

func _initialize():
	var failures := _check_ship_constants()
	var tracks := 0
	for theme in 4:
		var lim: Dictionary = LevelGenerator.jump_limits(theme)
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
			failures += _check(LevelGenerator.generate(p), lim, theme, trial)
	print("checked %d tracks, %d violations" % [tracks, failures])
	quit(1 if failures > 0 else 0)

func _check_ship_constants() -> int:
	var script: GDScript = load("res://Scripts/ship.gd")
	if script == null or not script.can_instantiate():
		printerr("ship.gd failed to load/parse - cannot verify ship constants")
		return 1
	var ship = script.new()
	var bad := 0
	if ship.acceleration != LevelGenerator.SHIP_ACCEL:
		printerr("ship.gd acceleration %s != LevelGenerator.SHIP_ACCEL %s" % [ship.acceleration, LevelGenerator.SHIP_ACCEL])
		bad += 1
	if ship.max_speed != LevelGenerator.SHIP_MAX_SPEED:
		printerr("ship.gd max_speed %s != LevelGenerator.SHIP_MAX_SPEED %s" % [ship.max_speed, LevelGenerator.SHIP_MAX_SPEED])
		bad += 1
	if ship.lateral_speed != LevelGenerator.SHIP_LATERAL_SPEED:
		printerr("ship.gd lateral_speed %s != LevelGenerator.SHIP_LATERAL_SPEED %s" % [ship.lateral_speed, LevelGenerator.SHIP_LATERAL_SPEED])
		bad += 1
	ship.free()
	return bad

func _check(content: String, lim: Dictionary, theme: int, trial: int) -> int:
	var grid: Array = []
	var tun: Array = []
	for line in content.split("\n"):
		if line.strip_edges() == "":
			continue
		var row: Array[int] = []
		row.resize(10)
		row.fill(0)
		var trow: Array[bool] = []
		trow.resize(10)
		trow.fill(false)
		for ci in range(0, mini(line.length(), 20), 2):
			var ch := line[ci]
			if ch >= "1" and ch <= "9":
				row[ci / 2] = ch.unicode_at(0) - "0".unicode_at(0)
			if ci + 1 < line.length() and (line[ci + 1] == "T" or line[ci + 1] == "t"):
				trow[ci / 2] = true
		grid.append(row)
		tun.append(trow)

	var max_step: int = lim.max_step
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
			var max_gap: int = LevelGenerator._max_gap_rows(runup, lim)
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

	# Tunnel invariants: no jumping under the roof, so a bore must be flat,
	# gap-free and entered at floor level
	for tr in rows:
		for c in 10:
			if not tun[tr][c]:
				continue
			if grid[tr][c] == 0:
				print("  theme %d trial %d row %d col %d: gap inside tunnel" % [theme, trial, tr, c])
				bad += 1
			elif tr + 1 < rows and tun[tr + 1][c] and grid[tr + 1][c] != grid[tr][c]:
				print("  theme %d trial %d row %d col %d: height step inside tunnel" % [theme, trial, tr, c])
				bad += 1
			elif tr > 0 and not tun[tr - 1][c] and grid[tr - 1][c] != grid[tr][c]:
				print("  theme %d trial %d row %d col %d: tunnel entry needs a jump" % [theme, trial, tr, c])
				bad += 1
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
