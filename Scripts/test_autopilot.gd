extends SceneTree

const TILE_SIZE := 2.0
const TILE_HEIGHT := 0.5

func _initialize():
	print("=== Autopilot Simulation Test ===")
	var results := {"success": 0, "wall": 0, "tunnel_wall": 0, "fell": 0, "timeout": 0}
	var total := 100
	var crash_details := []

	for i in total:
		var params := {
			"length": 200 + (i % 5) * 50,
			"max_height": 3 + (i % 3),
			"tunnel_weight": 8 + (i % 5) * 2,
			"narrow_weight": 12 + (i % 4) * 3,
			"gap_weight": 8 + (i % 4) * 2,
			"tunnel_lane_weight": 6 + (i % 4) * 2,
			"sharpness": 0.08 + (i % 4) * 0.04,
			"seed": i * 7919 + 42,
			"min_height": 1,
		}
		var content := LevelGenerator.generate(params)
		var result := _simulate(content, i)
		results[result.type] += 1
		if result.type != "success":
			crash_details.append("Level %d: %s at row=%d col=%.1f speed=%.0f y=%.2f" % [i, result.type, result.row, result.col, result.speed, result.y])
			if crash_details.size() <= 20:
				print(crash_details[-1])

	print("\n=== Results (%d levels) ===" % total)
	for key in results:
		if results[key] > 0:
			print("  %s: %d (%.0f%%)" % [key, results[key], float(results[key]) / float(total) * 100])
	print("Success rate: %.0f%%" % (float(results["success"]) / float(total) * 100))

	if crash_details.size() > 20:
		print("\n(Showing first 20 of %d crashes)" % crash_details.size())
	quit()

func _simulate(content: String, level_idx: int) -> Dictionary:
	var lines := content.split("\n")
	while lines.size() > 0 and lines[-1].strip_edges() == "":
		lines.remove_at(lines.size() - 1)

	var runway_row := "..".repeat(2) + "1.".repeat(6) + "..".repeat(2)
	var full_lines: Array[String] = []
	for _i in 24:
		full_lines.append(runway_row)
	for line in lines:
		full_lines.append(line)

	var rows := full_lines.size()
	var cols := 10

	var grid: Array[Array] = []
	var tunnels: Array[Array] = []
	for r in rows:
		var floor_row: Array[int] = []
		floor_row.resize(cols)
		floor_row.fill(0)
		var tunnel_row: Array[bool] = []
		tunnel_row.resize(cols)
		tunnel_row.fill(false)
		var line: String = full_lines[r]
		for ci in range(0, line.length(), 2):
			var tile_idx := ci / 2
			if tile_idx >= cols:
				break
			var h_char := line[ci]
			var m_char := line[ci + 1] if ci + 1 < line.length() else "."
			if h_char >= "1" and h_char <= "9":
				floor_row[tile_idx] = h_char.unicode_at(0) - "0".unicode_at(0)
			if m_char == "T" or m_char == "t":
				tunnel_row[tile_idx] = true
		grid.append(floor_row)
		tunnels.append(tunnel_row)

	# Physics constants
	var dt := 1.0 / 60.0
	var max_speed := 30.0
	var accel := 12.0
	var lat_speed := 15.0
	var jump_vel := 8.0
	var grav := 20.0
	var bounce := 0.45

	# Ship state — collision box is 0.3 tall, ship.y is center
	var ship_half_h := 0.15
	var pos := Vector3(9.0, 1.0, 0.0)
	var speed := 12.0
	var vy := 0.0
	var on_floor := false
	var last_floor_y := 0.5
	var can_jump := true
	var level_end_z := -(rows - 1) * TILE_SIZE
	var max_ticks := int(180.0 / dt)

	for _tick in max_ticks:
		var current_row := int(-pos.z / TILE_SIZE)
		var col_f := pos.x / TILE_SIZE
		var current_col := clampi(roundi(col_f), 0, cols - 1)

		if pos.z < level_end_z:
			return {"type": "success", "row": current_row, "col": col_f, "speed": speed, "y": pos.y}

		if current_row < 0 or current_row >= rows:
			return {"type": "fell", "row": current_row, "col": col_f, "speed": speed, "y": pos.y}

		var current_h: int = grid[current_row][current_col]

		# Autopilot
		var ap := _autopilot(grid, tunnels, cols, pos, speed, max_speed, on_floor, can_jump, current_row, col_f, current_col, current_h, vy)

		# Speed
		if speed < ap.target_speed - 1.0:
			speed += accel * dt
		elif speed > ap.target_speed + 1.0:
			speed -= accel * dt
		speed = clampf(speed, 0, max_speed)

		# Lateral
		pos.x += ap.dir * lat_speed * dt

		# Jump
		if ap.jump and (on_floor or can_jump):
			vy = jump_vel
			can_jump = false
			on_floor = false

		# Gravity
		if not on_floor:
			vy -= grav * dt

		# Move
		var prev_z := pos.z
		pos.z -= speed * dt
		pos.y += vy * dt

		# Floor / collision check
		var new_row := int(-pos.z / TILE_SIZE)
		var new_col := clampi(roundi(pos.x / TILE_SIZE), 0, cols - 1)

		if new_row >= 0 and new_row < rows and new_col >= 0 and new_col < cols:
			var fh: int = grid[new_row][new_col]
			var ship_bottom := pos.y - ship_half_h
			var ship_top := pos.y + ship_half_h
			if fh > 0 and ship_top > 0:
				var floor_top := float(fh) * TILE_HEIGHT
				# Wall check: only if ship overlaps tile in y-axis (tile goes 0 to floor_top)
				var prev_row := int(-prev_z / TILE_SIZE)
				if new_row != prev_row and ship_bottom < floor_top - 0.15 and ship_top > 0:
					var prev_fh: int = 0
					if prev_row >= 0 and prev_row < rows and new_col < cols:
						prev_fh = grid[prev_row][new_col]
					if prev_fh == 0 or fh > prev_fh:
						var is_tun: bool = tunnels[new_row][new_col]
						var crash_type := "tunnel_wall" if is_tun else "wall"
						return {"type": crash_type, "row": new_row, "col": col_f, "speed": speed, "y": pos.y}

				if ship_bottom <= floor_top and pos.y > 0:
					if vy < -1.0:
						vy = absf(vy) * bounce
						can_jump = true
					else:
						vy = 0
						can_jump = true
					pos.y = floor_top + ship_half_h
					on_floor = true
					last_floor_y = floor_top
				else:
					on_floor = false
			else:
				on_floor = false
		else:
			on_floor = false

		if pos.y < -10:
			return {"type": "fell", "row": new_row, "col": col_f, "speed": speed, "y": pos.y}

	return {"type": "timeout", "row": int(-pos.z / TILE_SIZE), "col": pos.x / TILE_SIZE, "speed": speed, "y": pos.y}

func _autopilot(grid: Array, tunnels: Array, cols: int, pos: Vector3, speed: float, max_speed: float, on_floor: bool, can_jump: bool, current_row: int, col_f: float, current_col: int, current_h: int, vert_vel: float) -> Dictionary:
	var airborne := not on_floor
	var jump_look := maxi(6, int(speed / 3.0))
	var jump_rows := speed * 0.8 / TILE_SIZE

	# Fix current_h when ship is between tiles
	if current_h == 0:
		for dc in [-1, 1]:
			var adj: int = current_col + dc
			if adj >= 0 and adj < cols and current_row < grid.size() and adj < grid[current_row].size():
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
		# Floor continuity bonus — prefer columns with unbroken floor
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

	# Look ahead for very narrow sections — pre-align
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

	# Jump — gaps: jump early. Walls: jump LATE (peak near wall for best clearance)
	var need_jump := false
	var wall_ahead := false
	var check_col := clampi(roundi(col_f), 0, cols - 1)
	if on_floor or can_jump:
		need_jump = _check_col_jump(grid, current_row, check_col, current_h, jump_look, speed, pos.y)
		if not need_jump and best_col != check_col:
			need_jump = _check_col_jump(grid, current_row, best_col, current_h, jump_look, speed, pos.y)
		# Check for walls ahead (for speed management)
		for dr in range(1, jump_look + 1):
			var r := current_row + dr
			if r >= grid.size() or check_col >= grid[r].size():
				break
			if grid[r][check_col] > 0 and current_h > 0 and grid[r][check_col] > current_h:
				wall_ahead = true
				break

	# Speed — go fast, only brake for narrow paths and big lateral moves
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
	if absf(diff) > TILE_SIZE * 3:
		target_speed = minf(target_speed, 18.0)

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

func _check_col_jump(grid: Array, current_row: int, col: int, current_h: int, jump_look: int, spd: float, ship_y: float) -> bool:
	# Wall jump: peak at 0.4s, so ideal distance = speed * 0.4 / TILE_SIZE
	var wall_trigger := maxi(3, int(spd * 0.4 / TILE_SIZE))
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
			# Wall: floor ahead is above ship — need to jump over it
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
