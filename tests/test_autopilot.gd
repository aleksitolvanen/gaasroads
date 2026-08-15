# Autopilot regression: runs the shared Autopilot heuristic (the same code
# ship.gd drives with the P key) against the first two authored levels of
# each group, under that group's real gravity/jump physics.
#
# Run:  godot --headless --path . -s tests/test_autopilot.gd
# Pass: success rate printed; exit 0 at 4/6 or better. This gauges heuristic
# strength, not level completability - use solve_level.py for proofs.
extends SceneTree

const TILE_SIZE := 2.0
const TILE_HEIGHT := 0.5
const PASS_FLOOR := 4

func _initialize():
	print("=== Autopilot Simulation Test ===")
	var results := {"success": 0, "wall": 0, "tunnel_wall": 0, "fell": 0, "timeout": 0}

	# Known-completable levels (first 2 of each group) with their theme index
	var level_files := [
		"res://Levels/nebula_1.txt", "res://Levels/nebula_2.txt",
		"res://Levels/solar_1.txt", "res://Levels/solar_2.txt",
		"res://Levels/dark_1.txt", "res://Levels/dark_2.txt",
	]
	var level_names := [
		"Nebula 1", "Nebula 2",
		"Solar 1", "Solar 2", "Dark 1", "Dark 2",
	]
	var level_themes := [1, 1, 2, 2, 3, 3]

	var total := level_files.size()
	for i in total:
		var content := FileAccess.get_file_as_string(level_files[i])
		var result := _simulate(content, level_themes[i])
		results[result.type] += 1
		var status := "OK" if result.type == "success" else "%s at row=%d col=%.1f speed=%.0f y=%.2f" % [result.type, result.row, result.col, result.speed, result.y]
		print("  %s: %s" % [level_names[i], status])

	print("\n=== Results (%d levels) ===" % total)
	for key in results:
		if results[key] > 0:
			print("  %s: %d (%.0f%%)" % [key, results[key], float(results[key]) / float(total) * 100])
	print("Success rate: %d/%d" % [results["success"], total])
	quit(0 if results["success"] >= PASS_FLOOR else 1)

func _simulate(content: String, theme: int) -> Dictionary:
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

	# Physics constants - the group's real physics, from the single source
	var dt := 1.0 / 60.0
	var max_speed := LevelGenerator.SHIP_MAX_SPEED
	var accel := LevelGenerator.SHIP_ACCEL
	var lat_speed := LevelGenerator.SHIP_LATERAL_SPEED
	var grav: float = LevelGenerator.GROUP_GRAVITY[theme]
	var jump_vel: float = LevelGenerator.GROUP_JUMP_VELOCITY[theme]
	var air_time := 2.0 * jump_vel / grav
	var bounce := 0.45

	# Ship state — collision box is 0.3 tall, ship.y is center
	var ship_half_h := 0.15
	var pos := Vector3(9.0, 1.0, 0.0)
	var speed := 12.0
	var vy := 0.0
	var on_floor := false
	var last_floor_y := 0.5
	var can_jump := true
	# classical mode (the game default): steering scales with throttle and
	# locks for the duration of a jump
	var jump_airborne := false
	var locked_lateral := 0.0
	var level_end_z := -(rows - 1) * TILE_SIZE
	var max_ticks := int(180.0 / dt)

	for _tick in max_ticks:
		var current_row := int(-pos.z / TILE_SIZE)
		var col_f := pos.x / TILE_SIZE

		if pos.z < level_end_z:
			return {"type": "success", "row": current_row, "col": col_f, "speed": speed, "y": pos.y}

		if current_row < 0 or current_row >= rows:
			return {"type": "fell", "row": current_row, "col": col_f, "speed": speed, "y": pos.y}

		# Autopilot - the shared heuristic the game ships
		var ap := Autopilot.compute(grid, tunnels, cols, pos, speed, max_speed,
			lat_speed, on_floor, can_jump, vy, air_time)

		# Speed
		if speed < ap.target_speed - 1.0:
			speed += accel * dt
		elif speed > ap.target_speed + 1.0:
			speed -= accel * dt
		speed = clampf(speed, 0, max_speed)

		# Lateral — classical: throttle-scaled, locked while jump-airborne
		var eff_lateral: float = ap.dir * lat_speed * (0.25 + 0.35 * speed / max_speed)
		pos.x += (locked_lateral if jump_airborne else eff_lateral) * dt

		# Banked jump expires with the coyote window (mirrors ship.gd)
		var near_floor := on_floor or (pos.y < last_floor_y + ship_half_h + 0.4 and vy < 0.0 and vy > -2.5)
		if not on_floor and not near_floor:
			can_jump = false

		# Jump
		if ap.jump and (on_floor or can_jump):
			vy = jump_vel
			can_jump = false
			on_floor = false
			jump_airborne = true
			locked_lateral = eff_lateral

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
					jump_airborne = false
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
