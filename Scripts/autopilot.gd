class_name Autopilot

# Shared driving heuristic for the in-game autopilot (ship.gd, P key) and the
# headless regression sim (tests/test_autopilot.gd). Pure function over the
# parsed grid state - keep it engine-free so both callers run identical code.
# air_time = 2 * jump_velocity / gravity for the active group.

const TILE_SIZE := 2.0
const TILE_HEIGHT := 0.5

static func compute(grid: Array, tunnels: Array, cols: int, pos: Vector3,
		speed: float, max_speed: float, lateral_speed: float, on_floor: bool,
		can_jump: bool, vert_vel: float, air_time: float) -> Dictionary:
	if grid.is_empty():
		return {"dir": 0.0, "target_speed": max_speed, "jump": false}
	var current_row := int(-pos.z / TILE_SIZE)
	var col_f := pos.x / TILE_SIZE
	var current_col := clampi(roundi(col_f), 0, cols - 1)
	if current_row < 0 or current_row >= grid.size():
		return {"dir": 0.0, "target_speed": max_speed, "jump": false}

	var airborne := not on_floor
	var jump_look := maxi(6, int(speed / 3.0))
	var jump_rows := speed * air_time / TILE_SIZE
	var current_h: int = grid[current_row][current_col]

	# Fix current_h when ship is between tiles
	if current_h == 0:
		for dc in [-1, 1]:
			var adj: int = current_col + dc
			if adj >= 0 and adj < cols and adj < grid[current_row].size():
				if grid[current_row][adj] > 0:
					current_h = grid[current_row][adj]
					break

	# Tunnel detection
	var in_tunnel := false
	var tunnel_col_now := -1
	if current_row < tunnels.size():
		for c in cols:
			if c < tunnels[current_row].size() and tunnels[current_row][c]:
				in_tunnel = true
				if tunnel_col_now < 0 or absf(float(c) - col_f) < absf(float(tunnel_col_now) - col_f):
					tunnel_col_now = c
	var tunnel_ahead_col := -1
	var tunnel_ahead_dist := 999
	if not in_tunnel:
		for dr in range(1, 20):
			var r := current_row + dr
			if r >= tunnels.size():
				break
			for c in cols:
				if c < tunnels[r].size() and tunnels[r][c]:
					if tunnel_ahead_col < 0 or absf(float(c) - col_f) < absf(float(tunnel_ahead_col) - col_f):
						tunnel_ahead_col = c
					tunnel_ahead_dist = dr
					break
			if tunnel_ahead_col >= 0:
				break

	# Score columns
	var look_ahead := 25
	var best_col := current_col
	var best_score := -9999.0
	for c in cols:
		var score := 0.0
		var prev_h := current_h
		var in_gap := false
		var gap_start := -1
		for dr in range(1, look_ahead + 1):
			var r := current_row + dr
			if r >= grid.size():
				break
			if c < grid[r].size() and grid[r][c] > 0:
				var h: int = grid[r][c]
				var was_gap := in_gap
				if in_gap:
					var gw := dr - gap_start
					if float(gw) > jump_rows * 0.7:
						score -= 40.0
					else:
						score -= float(gw) * 1.5
					in_gap = false
				if prev_h > 0 and h > prev_h:
					var hdiff := float(h - prev_h)
					var post_gap_penalty := 10.0 if was_gap else 0.0
					if dr <= 4:
						score -= 10.0 * hdiff + post_gap_penalty
					elif dr <= 8:
						score -= 4.0 * hdiff + post_gap_penalty
					else:
						score -= 1.5 * hdiff
				else:
					score += 1.0 / (1.0 + float(dr) * 0.05)
				prev_h = h
			else:
				if not in_gap:
					in_gap = true
					gap_start = dr
				if dr <= 2:
					score -= 15.0
				elif dr <= 4:
					score -= 6.0
				else:
					score -= 0.5
		if in_gap:
			score -= 25.0
		# Floor continuity bonus - prefer columns with unbroken floor
		var continuous := 0
		for dr in range(1, 12):
			var r := current_row + dr
			if r >= grid.size() or c >= grid[r].size():
				break
			if grid[r][c] > 0:
				continuous += 1
			else:
				break
		score += float(continuous) * 0.8
		score -= absf(float(c) - col_f) * 1.2
		if airborne:
			for dr in range(0, 5):
				var r := current_row + dr
				if r >= 0 and r < grid.size() and c < grid[r].size() and grid[r][c] > 0:
					var top := float(grid[r][c]) * TILE_HEIGHT
					if top > pos.y - 0.3:
						var penalty := 30.0 if vert_vel < 0 else 20.0
						score -= penalty
						break
		# Penalize columns that require crossing empty tiles
		if not airborne and current_row < grid.size():
			var from_c := clampi(roundi(col_f), 0, cols - 1)
			if c != from_c:
				var step := 1 if c > from_c else -1
				for cross_c in range(from_c, c, step):
					if cross_c >= 0 and cross_c < cols and cross_c < grid[current_row].size():
						if grid[current_row][cross_c] == 0:
							score -= 15.0
							break
		if score > best_score:
			best_score = score
			best_col = c

	# Look ahead for very narrow sections - pre-align
	var narrowest_width := cols
	var narrowest_center := col_f
	for dr in range(0, 5):
		var r := current_row + dr
		if r >= grid.size():
			break
		var fmin := cols
		var fmax := -1
		var fcnt := 0
		for c in cols:
			if c < grid[r].size() and grid[r][c] > 0:
				fcnt += 1
				if c < fmin:
					fmin = c
				if c > fmax:
					fmax = c
		if fcnt > 0 and fcnt < narrowest_width:
			narrowest_width = fcnt
			narrowest_center = float(fmin + fmax) / 2.0

	# Steer
	var target_x := float(best_col) * TILE_SIZE
	# Narrow path override: center on very narrow paths
	if narrowest_width <= 2 and not airborne:
		target_x = narrowest_center * TILE_SIZE
	var diff := target_x - pos.x
	var steer := 0.0
	if absf(diff) > 0.15:
		steer = clampf(diff * 1.5, -1.0, 1.0)
	if airborne:
		steer *= 0.4

	# Jump - gaps: jump early. Walls: jump LATE (peak near wall for best clearance)
	var need_jump := false
	var check_col := clampi(roundi(col_f), 0, cols - 1)
	if on_floor or can_jump:
		need_jump = _check_col_jump(grid, current_row, check_col, current_h, jump_look, speed, pos.y, air_time)
		if not need_jump and best_col != check_col:
			need_jump = _check_col_jump(grid, current_row, best_col, current_h, jump_look, speed, pos.y, air_time)

	# Speed - go fast, only brake for narrow paths and big lateral moves
	# (classical steering is throttle-scaled and weak, so brake earlier)
	var target_speed := max_speed
	var narrow_count := 0
	for dr in [3, 5, 8]:
		var cr: int = current_row + dr
		if cr >= 0 and cr < grid.size():
			var floor_count := 0
			for c in cols:
				if c < grid[cr].size() and grid[cr][c] > 0:
					floor_count += 1
			if floor_count <= 1:
				narrow_count += 2
			elif floor_count <= 2:
				narrow_count += 1
	if narrow_count >= 4:
		target_speed = 16.0
	elif narrow_count >= 2:
		target_speed = 22.0
	if absf(diff) > TILE_SIZE * 1.5:
		target_speed = minf(target_speed, 16.0)

	# Classical: steering locks at takeoff, so a jump commits to its drift.
	# Aim the locked lateral to land on the target column instead of
	# carrying whatever steer happened to be held.
	if need_jump:
		var lv_scale := 0.25 + 0.35 * speed / max_speed
		if absf(diff) < 0.3:
			steer = 0.0
		else:
			steer = clampf(diff / air_time / (lateral_speed * lv_scale), -1.0, 1.0)

	# Tunnel overrides
	if in_tunnel and tunnel_col_now >= 0:
		var t_target := float(tunnel_col_now) * TILE_SIZE
		var t_diff := t_target - pos.x
		steer = clampf(t_diff * 3.0, -1.0, 1.0)
		need_jump = false
		target_speed = minf(target_speed, 15.0)
	elif tunnel_ahead_col >= 0 and tunnel_ahead_dist <= 12:
		var t_target := float(tunnel_ahead_col) * TILE_SIZE
		var t_diff := t_target - pos.x
		steer = clampf(t_diff * 2.0, -1.0, 1.0)
		if tunnel_ahead_dist <= 5:
			target_speed = minf(target_speed, 14.0)
		else:
			target_speed = minf(target_speed, 20.0)

	return {"dir": steer, "target_speed": target_speed, "jump": need_jump}

static func _check_col_jump(grid: Array, current_row: int, col: int, current_h: int, jump_look: int, spd: float, ship_y: float, air_time: float) -> bool:
	# Wall jump: peak at air_time/2, so ideal distance = speed * air_time/2
	var wall_trigger := maxi(3, int(spd * air_time * 0.5 / TILE_SIZE))
	for dr in range(1, jump_look + 1):
		var r := current_row + dr
		if r >= grid.size() or col >= grid[r].size():
			break
		var ahead_h: int = grid[r][col]
		if ahead_h == 0:
			# Gap: jump as soon as detected if there's a landing
			var found_landing := false
			for dr2 in range(dr + 1, dr + 12):
				var r2 := current_row + dr2
				if r2 >= grid.size() or col >= grid[r2].size():
					break
				if grid[r2][col] > 0:
					found_landing = true
					break
			if found_landing:
				return true
		elif ahead_h > 0:
			var floor_top := float(ahead_h) * TILE_HEIGHT
			# Wall: floor ahead is above ship - need to jump over it
			if floor_top > ship_y - 0.1:
				if current_h > 0 and ahead_h > current_h:
					if dr <= wall_trigger:
						return true
					return false
				elif current_h == 0 and floor_top > ship_y + 0.1:
					# Ship on empty tile heading toward a wall
					if dr <= wall_trigger:
						return true
					return false
	return false
