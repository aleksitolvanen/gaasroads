class_name LevelGenerator

const W := 10

static func generate(p: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = p.get("seed", randi())
	var target: int = p.get("length", 200)
	var min_h: int = p.get("min_height", 1)
	var max_h: int = p.get("max_height", 4)
	var tw: int = p.get("tunnel_weight", 10)
	var nw: int = p.get("narrow_weight", 15)
	var gw: int = p.get("gap_weight", 10)
	var tlw: int = p.get("tunnel_lane_weight", 8)
	var sharpness: float = p.get("sharpness", 0.15)

	var rows: Array[String] = []
	_add_flat(rows, 1, 8)

	while rows.size() < target:
		_add_flat(rows, 1, 2)
		var prog := minf(1.0, float(rows.size()) / float(target))
		var st := _pick(rng, tw, nw, gw, tlw, prog)
		var sl := rng.randi_range(10, 25 + int(prog * 10))
		match st:
			0: _wide(rng, rows, sl, min_h, max_h, prog)
			1: _narrow(rng, rows, sl, min_h, max_h, sharpness)
			2: _three(rng, rows, sl, min_h, max_h, sharpness)
			3: _tunnel(rng, rows, sl, min_h, max_h)
			4: _chicane(rng, rows, sl, min_h, max_h, sharpness)
			5: _gaps(rng, rows, sl, min_h, max_h, prog)
			6: _tunnel_lane(rng, rows, sl, min_h, max_h, sharpness)

	_add_flat(rows, 1, 6)
	return "\n".join(PackedStringArray(rows))

static func _e() -> Array:
	var r := []
	r.resize(W)
	for i in W:
		r[i] = ".."
	return r

static func _f(r: Array, a: int, b: int, h: int, m := "."):
	for i in range(maxi(0, a), mini(W, b)):
		r[i] = str(h) + m

static func _s(r: Array) -> String:
	return "".join(PackedStringArray(r))

static func _flat(h: int) -> String:
	var r := _e()
	_f(r, 0, W, h)
	return _s(r)

static func _add_flat(rows: Array, h: int, n: int):
	for _i in n:
		rows.append(_flat(h))

static func _ch(rng: RandomNumberGenerator, h: int, min_h: int, max_h: int) -> int:
	return clampi(h + [-1, 1][rng.randi() % 2], min_h, max_h)

static func _pick(rng: RandomNumberGenerator, tw: int, nw: int, gw: int, tlw: int, prog: float) -> int:
	var w := [maxi(5, 25 - int(prog * 15)), nw + int(prog * 8), maxi(3, nw / 2), tw, 8 + int(prog * 5), gw + int(prog * 5), tlw + int(prog * 5)]
	var total := 0
	for v in w:
		total += v
	if total <= 0:
		return 0
	var roll := rng.randi() % total
	var cum := 0
	for i in w.size():
		cum += w[i]
		if roll < cum:
			return i
	return 0

# Gradual lane shift: move position toward target over several rows
static func _gradual_shift(rng: RandomNumberGenerator, rows: Array, from_pos: int, to_pos: int, lw: int, h: int, sharpness: float):
	var dist := absi(to_pos - from_pos)
	if dist == 0:
		return
	# More rows for gradual shifts, fewer for sharp
	var shift_rows := maxi(2, int(float(dist) / maxf(0.05, sharpness)))
	var dir := 1 if to_pos > from_pos else -1
	var pos_f := float(from_pos)
	var step := float(to_pos - from_pos) / float(shift_rows)
	for _i in shift_rows:
		pos_f += step
		var cur_pos := int(round(pos_f))
		var r := _e()
		# Fill a wider bridge during transition
		var lo := mini(cur_pos, cur_pos - dir)
		var hi := maxi(cur_pos + lw, cur_pos + lw - dir)
		_f(r, lo, hi, h)
		rows.append(_s(r))

static func _wide(rng: RandomNumberGenerator, rows: Array, sl: int, min_h: int, max_h: int, prog: float):
	var w := rng.randi_range(maxi(5, 8 - int(prog * 4)), W)
	var off := rng.randi_range(0, W - w)
	var h := rng.randi_range(min_h, max_h)
	for _i in sl:
		if rng.randf() < 0.12:
			h = _ch(rng, h, min_h, max_h)
		var r := _e()
		_f(r, off, off + w, h)
		if rng.randf() < 0.05 + prog * 0.12:
			var gp := rng.randi_range(off, off + w - 2)
			r[gp] = ".."
			if gp + 1 < off + w and rng.randf() < 0.4:
				r[gp + 1] = ".."
		rows.append(_s(r))

static func _narrow(rng: RandomNumberGenerator, rows: Array, sl: int, min_h: int, max_h: int, sharpness: float):
	var lw := 1 if rng.randf() < 0.5 else 2
	var positions := [0, 1, (W - lw) / 2, W - lw - 1, W - lw]
	var pos: int = positions[rng.randi() % positions.size()]
	var h := rng.randi_range(min_h, max_h)
	var shift_at := rng.randi_range(sl / 3, sl * 2 / 3)
	for i in sl:
		if rng.randf() < 0.06:
			h = _ch(rng, h, min_h, max_h)
		var r := _e()
		_f(r, pos, pos + lw, h)
		rows.append(_s(r))
		if i == shift_at:
			var candidates := []
			for p in positions:
				if absi(p - pos) >= 3:
					candidates.append(p)
			if candidates.size() > 0:
				var new_pos: int = candidates[rng.randi() % candidates.size()]
				_gradual_shift(rng, rows, pos, new_pos, lw, h, sharpness)
				pos = new_pos

static func _three(rng: RandomNumberGenerator, rows: Array, sl: int, min_h: int, max_h: int, sharpness: float):
	var lp := [0, 4 + rng.randi_range(-1, 1), W - 1]
	var hs := [rng.randi_range(min_h, max_h), rng.randi_range(min_h, max_h), rng.randi_range(min_h, max_h)]
	for _i in sl:
		for j in 3:
			if rng.randf() < 0.05:
				hs[j] = _ch(rng, hs[j], min_h, max_h)
		var r := _e()
		for j in 3:
			_f(r, lp[j], lp[j] + 1, hs[j])
		if rng.randf() < 0.12:
			var j := rng.randi_range(0, 1)
			_f(r, lp[j] + 1, lp[j + 1], mini(hs[j], hs[j + 1]))
		rows.append(_s(r))

static func _tunnel(rng: RandomNumberGenerator, rows: Array, sl: int, min_h: int, max_h: int):
	var tw := rng.randi_range(2, 4)
	var tp := rng.randi_range(0, W - tw)
	var h := rng.randi_range(min_h, mini(max_h, 4))
	for _i in 3:
		var r := _e()
		_f(r, maxi(0, tp - 2), mini(W, tp + tw + 2), h)
		rows.append(_s(r))
	for _i in maxi(1, sl - 6):
		var r := _e()
		_f(r, tp, tp + tw, h, "T")
		rows.append(_s(r))
	for _i in 3:
		var r := _e()
		_f(r, maxi(0, tp - 2), mini(W, tp + tw + 2), h)
		rows.append(_s(r))

static func _chicane(rng: RandomNumberGenerator, rows: Array, sl: int, min_h: int, max_h: int, sharpness: float):
	var lw := rng.randi_range(2, 3)
	var lpos := rng.randi_range(0, 2)
	var rpos := rng.randi_range(W - lw - 2, W - lw)
	var positions := [lpos, rpos]
	var cur := rng.randi() % 2
	var h := rng.randi_range(min_h, max_h)
	var seg := rng.randi_range(4, 7)
	var count := 0
	for _i in sl:
		var r := _e()
		_f(r, positions[cur], positions[cur] + lw, h)
		rows.append(_s(r))
		count += 1
		if count >= seg:
			count = 0
			var old_pos: int = positions[cur]
			cur = 1 - cur
			_gradual_shift(rng, rows, old_pos, positions[cur], lw, h, sharpness)
			seg = rng.randi_range(3, 7)

static func _tunnel_lane(rng: RandomNumberGenerator, rows: Array, sl: int, min_h: int, max_h: int, sharpness: float):
	var pos := rng.randi_range(1, W - 2)
	var h := rng.randi_range(min_h, mini(max_h, 3))
	# Lead-in: narrow lane
	var lead := rng.randi_range(4, 8)
	for _i in lead:
		var r := _e()
		_f(r, pos, pos + 1, h)
		rows.append(_s(r))
	# Tunnel section
	var tunnel_len := rng.randi_range(maxi(8, sl / 2), sl)
	for _i in tunnel_len:
		var r := _e()
		_f(r, pos, pos + 1, h, "T")
		rows.append(_s(r))
	# Exit and optionally shift to new position
	for _i in 3:
		var r := _e()
		_f(r, pos, pos + 1, h)
		rows.append(_s(r))
	if rng.randf() < 0.6:
		var new_pos := rng.randi_range(1, W - 2)
		while absi(new_pos - pos) < 3:
			new_pos = rng.randi_range(1, W - 2)
		_gradual_shift(rng, rows, pos, new_pos, 1, h, sharpness)
		# Second tunnel at new position
		var tunnel_len2 := rng.randi_range(6, tunnel_len)
		for _i in tunnel_len2:
			var r := _e()
			_f(r, new_pos, new_pos + 1, h, "T")
			rows.append(_s(r))
		for _i in 3:
			var r := _e()
			_f(r, new_pos, new_pos + 1, h)
			rows.append(_s(r))

static func _gaps(rng: RandomNumberGenerator, rows: Array, sl: int, min_h: int, max_h: int, prog: float):
	var pw := rng.randi_range(maxi(3, 6 - int(prog * 3)), 8)
	var off := rng.randi_range(0, W - pw)
	var h := rng.randi_range(min_h, max_h)
	var i := 0
	while i < sl:
		var pl := rng.randi_range(3, 6)
		for _j in mini(pl, sl - i):
			if rng.randf() < 0.08:
				h = _ch(rng, h, min_h, max_h)
			var r := _e()
			_f(r, off, off + pw, h)
			rows.append(_s(r))
			i += 1
		var gl := rng.randi_range(1, mini(3, 1 + int(prog * 2)))
		for _j in mini(gl, sl - i):
			rows.append(_s(_e()))
			i += 1
