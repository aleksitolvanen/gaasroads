class_name LevelGenerator

# Stage-based track generator with per-track personality. chunk_begin draws
# a "style" from the seed: a pattern palette (random weight multipliers, some
# patterns absent entirely), a procedural intensity envelope (2-3 waves with
# varied peaks and breathers, one of three finale types), a base height and
# width bias. Stages are filled with phrases - a pattern repeated with
# jittered knobs and rising intensity. A signature pattern recurs across the
# track at rising difficulty.
# All geometry obeys the jump-physics limits computed in chunk_begin, so
# tracks are completable with plain jumps by construction;
# tests/gen_constraints.gd verifies invariants, solve_level.py proves runs.

const W := 10

# Per-group ship physics (Cosmic, Nebula, Solar, Dark). Lives here rather
# than in an autoload so this class stays usable from headless -s scripts;
# the ship setup reads these too.
const GROUP_GRAVITY: Array[float] = [20.0, 20.0, 12.0, 8.0]
const GROUP_JUMP_VELOCITY: Array[float] = [8.0, 8.0, 10.0, 7.8]

enum { PAT_RHYTHM, PAT_CHICANE, PAT_STAIRS, PAT_TUNNEL, PAT_ISLANDS, PAT_LEDGE, PAT_SPLIT, PAT_SPEEDWAY, PAT_GATES, PAT_RAILS, PAT_CHECKER }
const PATTERN_POOL := [PAT_RHYTHM, PAT_CHICANE, PAT_STAIRS, PAT_TUNNEL, PAT_ISLANDS, PAT_LEDGE, PAT_SPLIT, PAT_GATES, PAT_RAILS, PAT_CHECKER, PAT_SPEEDWAY]

static func generate(p: Dictionary) -> String:
	var state := chunk_begin(p)
	var rows: Array[String] = []
	while not state.done:
		rows.append_array(chunk_next(state))
	return "\n".join(PackedStringArray(rows))

static func chunk_begin(p: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = p.get("seed", randi())
	var theme: int = clampi(p.get("theme", 0), 0, 3)
	var grav: float = GROUP_GRAVITY[theme]
	var jv: float = GROUP_JUMP_VELOCITY[theme]
	# Completability limits from the group's jump physics (tile height 0.5):
	# max_step = tallest climbable wall in tile units (jump peak jv^2/2g with
	# a 15% margin); air_time = full flat-ground jump duration.
	var jump_peak := jv * jv / (2.0 * grav)
	var max_step := maxi(1, int(jump_peak * 0.85 / 0.5))
	var lim := {
		"max_step": max_step,
		"entry_h": 1 + max_step,
		"air_time": 2.0 * jv / grav,
	}
	var weights: int = p.get("tunnel_weight", 10) + p.get("narrow_weight", 15) \
		+ p.get("gap_weight", 10) + p.get("tunnel_lane_weight", 8)
	var base_diff := clampf(0.45 + 0.04 * (p.get("max_height", 4) - 3)
		+ float(weights) / 250.0, 0.3, 1.0)
	# Difficulty lottery: the same settings can roll anything from a cruise
	# to a gauntlet. diff_boost is the endless-mode distance ramp. Authored
	# sets pass an explicit "difficulty" to keep their curated ramp.
	var droll := rng.randf()
	if p.has("difficulty"):
		base_diff = float(p["difficulty"])
	else:
		var dmult := 1.0
		if droll < 0.18:
			dmult = 0.65
		elif droll < 0.42:
			dmult = 0.85
		elif droll < 0.72:
			dmult = 1.0
		elif droll < 0.92:
			dmult = 1.2
		else:
			dmult = 1.4
		base_diff *= dmult
	base_diff = clampf(base_diff + float(p.get("diff_boost", 0.0)), 0.22, 1.0)

	# --- per-track personality ---
	var mults := {}
	var nonzero := 0
	for pat in PATTERN_POOL:
		var roll := rng.randf()
		var m := 0.0
		if roll < 0.28:
			m = 0.0          # not part of this track's vocabulary
		elif roll < 0.55:
			m = 0.5
		elif roll < 0.85:
			m = 1.5
		else:
			m = 3.0
		mults[pat] = m
		if m > 0.0:
			nonzero += 1
	if nonzero < 3:
		mults[PAT_RHYTHM] = 1.0
		mults[PAT_CHICANE] = 1.0
		mults[PAT_STAIRS] = 1.0
	# strong explicit weights override the palette lottery
	if p.get("tunnel_weight", 10) + p.get("tunnel_lane_weight", 8) / 2 >= 20:
		mults[PAT_TUNNEL] = maxf(mults[PAT_TUNNEL], 0.75)
	if p.get("narrow_weight", 15) >= 25:
		mults[PAT_CHICANE] = maxf(mults[PAT_CHICANE], 0.75)
	if p.get("gap_weight", 10) >= 20:
		mults[PAT_RHYTHM] = maxf(mults[PAT_RHYTHM], 0.75)
	# every track keeps at least one road-fragmenting texture
	if mults[PAT_RAILS] == 0.0 and mults[PAT_CHECKER] == 0.0:
		mults[PAT_RAILS] = 0.75
	var fin := rng.randi_range(0, 2)  # 0 speedway, 1 signature climax, 2 rush
	if p.has("finale"):
		fin = int(p["finale"])
	var style := {
		"mults": mults,
		"base_h": [1, 1, 2, 2, 3][rng.randi() % 5] if p.get("max_height", 4) >= 4 else 1 + rng.randi() % 2,
		"width_bias": rng.randi_range(-1, 1),
		"envelope": _make_envelope(rng),
		"finale": fin,
	}

	var state := {
		"rng": rng, "p": p, "lim": lim, "style": style,
		"target": p.get("length", 200),
		"rows": 0, "done": false,
		"diff": base_diff,
		"iface": {"pos": 2, "w": 6, "h": maxi(1, p.get("min_height", 1))},
		"sig": 0,
	}
	state.sig = _pick_pattern(rng, p, 0.6, style)
	# spice patterns don't carry a whole track as its recurring theme
	if state.sig == PAT_LEDGE:
		state.sig = PAT_CHICANE
	elif state.sig == PAT_SPLIT:
		state.sig = PAT_RHYTHM
	# half of all tracks are themed on a road-fragmenting texture - the
	# SkyRoads look - regardless of what the filler palette rolled
	if rng.randf() < 0.5:
		state.sig = PAT_RAILS if rng.randf() < 0.6 else PAT_CHECKER
	return state

# Random intensity envelope: intro, 2-3 waves (build, peak, breather) with
# rising peaks, then a finale and outro. Fractions and levels all jittered.
static func _make_envelope(rng: RandomNumberGenerator) -> Array:
	var env: Array = []
	var f := rng.randf_range(0.04, 0.09)
	env.append([f, "cruise", rng.randf_range(0.08, 0.2)])
	var waves := 2 + (1 if rng.randf() < 0.45 else 0)
	# one wave may spike well past the track's baseline difficulty
	var spike_at := rng.randi_range(0, waves - 1) if rng.randf() < 0.3 else -1
	var ladder := rng.randf_range(0.45, 0.7)
	var body := 1.0 - f - 0.22
	for wi in waves:
		var t := float(wi) / maxf(1.0, float(waves - 1))
		var peak := lerpf(ladder, 1.0, t) * rng.randf_range(0.85, 1.1)
		if wi == spike_at:
			peak *= 1.5
		var wf := body / float(waves)
		var a := wf * rng.randf_range(0.3, 0.45)
		f += a
		env.append([f, "sig" if rng.randf() < 0.4 else "phrase", peak * rng.randf_range(0.55, 0.75)])
		var b := wf * rng.randf_range(0.35, 0.5)
		f += b
		env.append([f, "sig" if rng.randf() < 0.6 else "phrase", peak])
		f += wf - a - b
		env.append([f, "cruise", rng.randf_range(0.06, 0.18)])
	f += 0.15
	env.append([f, "finale", rng.randf_range(0.75, 1.0)])
	env.append([1.0, "cruise", rng.randf_range(0.1, 0.25)])
	return env

# Emits one stage segment (a phrase or a cruise) per call so endless mode
# can spread generation across frames.
static func chunk_next(state: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if state.done:
		return out
	var rng: RandomNumberGenerator = state.rng
	var style: Dictionary = state.style
	var target: int = state.target
	if state.rows >= target:
		_connect(state, out, 1, 8, maxi(1, state.p.get("min_height", 1)))
		_lane_rows(state, out, 5)
		state.done = true
		state.rows += out.size()
		return out
	var f := float(state.rows) / float(target)
	var envelope: Array = style.envelope
	var env: Array = envelope[envelope.size() - 1]
	for e in envelope:
		if f < e[0]:
			env = e
			break
	var intensity := clampf(float(env[2]) * float(state.diff), 0.05, 1.0)
	var budget := maxi(8, int((float(env[0]) - f) * target))
	match env[1]:
		"cruise":
			_stage_cruise(state, out, budget)
		"sig":
			_phrase(state, out, state.sig, intensity, budget)
		"finale":
			match int(style.finale):
				0:
					_phrase(state, out, PAT_SPEEDWAY, intensity, budget)
				1:
					_phrase(state, out, state.sig, clampf(intensity + 0.15, 0.05, 1.0), budget)
				_:
					# rush: a gauntlet of short different patterns
					for _i in 3:
						var pat3 := _pick_pattern(rng, state.p, intensity, style)
						_build_pattern(state, out, pat3, intensity, maxi(10, budget / 3))
		_:
			var pat := _pick_pattern(rng, state.p, intensity, style)
			_phrase(state, out, pat, intensity, budget)
	state.rows += out.size()
	return out

# ---------------- pattern selection ----------------

static func _pick_pattern(rng: RandomNumberGenerator, p: Dictionary, it: float, style: Dictionary) -> int:
	var tw: int = p.get("tunnel_weight", 10)
	var nw: int = p.get("narrow_weight", 15)
	var gw: int = p.get("gap_weight", 10)
	var tlw: int = p.get("tunnel_lane_weight", 8)
	var base: Array = [
		12 + gw,
		10 + nw,
		14 if p.get("max_height", 4) >= 3 else 0,
		tw + tlw / 2,
		(6 + gw / 2) if it >= 0.3 else 0,
		(4 + nw / 2) if it >= 0.45 else 0,
		8 if it >= 0.25 and it <= 0.8 else 0,
		14,
		18 + nw,
		14 + gw,
		(10 + gw / 2) if it >= 0.55 else 0,
	]
	var mults: Dictionary = style.mults
	var w: Array = []
	var total := 0
	for i in PATTERN_POOL.size():
		var v := int(float(base[i]) * float(mults[PATTERN_POOL[i]]))
		w.append(v)
		total += v
	if total <= 0:
		return PAT_RHYTHM
	var roll := rng.randi() % total
	var cum := 0
	for i in w.size():
		cum += w[i]
		if roll < cum:
			return PATTERN_POOL[i]
	return PAT_RHYTHM

# ---------------- phrases and stages ----------------

# A phrase = the same pattern 1-3 times, each repetition harder, with short
# in-lane breaths between. Knob jitter inside patterns keeps repetitions
# recognizable but not identical.
static func _phrase(state: Dictionary, out: Array, pat: int, intensity: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	# re-center the flow after narrow sections so tracks use the full road
	if ifc.w <= 3:
		_connect(state, out, clampi(1 + rng.randi_range(0, 4), 0, W - 5), 5, ifc.h)
	# often run the phrase elevated for visual variety
	if pat != PAT_STAIRS and pat != PAT_TUNNEL and rng.randf() < 0.45:
		var lift := 1 + (1 if rng.randf() < 0.4 and state.lim.max_step >= 2 else 0)
		var eh := mini(state.iface.h + lift, mini(6, state.p.get("max_height", 4)))
		if eh != state.iface.h:
			_connect(state, out, state.iface.pos, state.iface.w, eh)
	var reps := 1
	if pat != PAT_SPEEDWAY:
		if budget >= 28 and rng.randf() < 0.85:
			reps = 2
		if budget >= 52 and rng.randf() < 0.55:
			reps = 3
	var per := budget / reps
	for r in reps:
		var it := clampf(intensity + rng.randf_range(0.06, 0.14) * r, 0.05, 1.0)
		_build_pattern(state, out, pat, it, per)
		if r < reps - 1:
			_lane_rows(state, out, 1 + rng.randi_range(1, 3))

static func _stage_cruise(state: Dictionary, out: Array, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var style: Dictionary = state.style
	var w := clampi(5 + rng.randi_range(0, 4) + int(style.width_bias), 4, W)
	var pos := rng.randi_range(0, W - w)
	var h: int = int(style.base_h) if ifc.h > int(style.base_h) and rng.randf() < 0.5 else mini(ifc.h, 4)
	_connect(state, out, pos, w, h)
	# hard tracks breathe less
	var cap := 6 + int((1.0 - float(state.diff)) * 12.0) + rng.randi_range(0, 4)
	_lane_rows(state, out, clampi(budget - 2, 4, cap))

static func _build_pattern(state: Dictionary, out: Array, pat: int, it: float, budget: int):
	match pat:
		PAT_RHYTHM: _pat_rhythm(state, out, it, budget)
		PAT_CHICANE: _pat_chicane(state, out, it, budget)
		PAT_STAIRS: _pat_stairs(state, out, it, budget)
		PAT_TUNNEL: _pat_tunnel(state, out, it, budget)
		PAT_ISLANDS: _pat_islands(state, out, it, budget)
		PAT_LEDGE: _pat_ledge(state, out, it, budget)
		PAT_SPLIT: _pat_split(state, out, it, budget)
		PAT_SPEEDWAY: _pat_speedway(state, out, it, budget)
		PAT_GATES: _pat_gates(state, out, it, budget)
		PAT_RAILS: _pat_rails(state, out, it, budget)
		PAT_CHECKER: _pat_checker(state, out, it, budget)

# ---------------- pattern vocabulary ----------------

# Evenly spaced gaps on a straight lane: a jump rhythm.
static func _pat_rhythm(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var w := clampi(5 - int(it * 3.5) + rng.randi_range(0, 1) + int(state.style.width_bias), 1, 6)
	var pos := clampi(ifc.pos + (ifc.w - w) / 2 + rng.randi_range(-1, 1), 0, W - w)
	_connect(state, out, pos, w, ifc.h)
	var solid := maxi(2, 6 - int(it * 4.0) + rng.randi_range(-1, 1))
	var g := mini(1 + int(it * 1.6), _max_gap_rows(solid + 2, state.lim))
	var reps := clampi(budget / (solid + g), 2, 6)
	for i in reps:
		_lane_rows(state, out, solid)
		if i < reps - 1:
			for _j in g:
				out.append(_row_str(_cells()))
	_lane_rows(state, out, 2)

# Lane swinging across the road with bridged transitions; sometimes a
# three-stop weave instead of two.
static func _pat_chicane(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var w := clampi(4 - int(it * 2.5) + (1 if rng.randf() < 0.3 else 0), 1, 4)
	var seg := clampi(6 - int(it * 3.0) + rng.randi_range(-1, 1), 3, 7)
	var stops: Array = [rng.randi_range(0, 1), W - w - rng.randi_range(0, 1)]
	if rng.randf() < 0.35:
		stops.insert(1, (W - w) / 2 + rng.randi_range(-1, 1))
	var side := rng.randi() % stops.size()
	var swings := clampi(budget / (seg + 4), 2, 4)
	# climbing chicanes: each swing steps a level, so cutting straight
	# across the void means landing into a wall instead of a free ride
	var climb := 0
	if rng.randf() < 0.45:
		climb = 1 if rng.randf() < 0.75 else -1
	var hcap: int = mini(state.p.get("max_height", 4), 6)
	_connect(state, out, stops[side], w, ifc.h)
	for i in swings:
		_lane_rows(state, out, seg)
		if i < swings - 1:
			side = (side + 1 + (rng.randi() % (stops.size() - 1))) % stops.size()
			_shift_lane(state, out, stops[side], w, clampi(int((1.4 - it) * 6.0) + rng.randi_range(-1, 1), 2, 8))
			if climb != 0:
				ifc.h = clampi(ifc.h + climb, 1, hcap)
				state.iface.h = ifc.h

# Climb in legal steps; sometimes descend, sometimes stay on the ridge.
static func _pat_stairs(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var lim: Dictionary = state.lim
	var max_h: int = mini(state.p.get("max_height", 4), 8)
	var w := clampi(6 - int(it * 3.0) + rng.randi_range(0, 1), 3, 6)
	var pos := clampi(ifc.pos + (ifc.w - w) / 2 + rng.randi_range(-1, 1), 0, W - w)
	var base: int = ifc.h
	_connect(state, out, pos, w, base)
	var step: int = 1 if it < 0.4 or lim.max_step < 2 or rng.randf() < 0.3 else 2
	var climbs := clampi(1 + int(it * 2.0) + rng.randi_range(0, 1), 1, (max_h - base) / step)
	if climbs < 1:
		_lane_rows(state, out, mini(budget, 8))
		return
	var plateau := rng.randi_range(2, 4)
	for i in climbs:
		ifc.h += step
		_lane_rows(state, out, plateau)
	_lane_rows(state, out, rng.randi_range(3, 6))
	if rng.randf() < 0.45:
		ifc.h = base
		_lane_rows(state, out, 3)

# Lead-in, tunnel bore, lead-out.
static func _pat_tunnel(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var lim: Dictionary = state.lim
	var h: int = clampi(ifc.h, 1, mini(4, lim.entry_h))
	var w := 2 if it >= 0.4 or rng.randf() < 0.4 else 3
	var pos := clampi(ifc.pos + (ifc.w - w) / 2 + rng.randi_range(-2, 2), 1, W - w - 1)
	# walled bore: thread the tunnel, or - when the wall is jumpable - climb
	# onto the massif and ride the top
	var walled: bool = rng.randf() < clampf(0.3 + it * 0.4, 0.3, 0.7)
	var flank_h := 0
	if walled:
		flank_h = mini(h + (2 if it < 0.6 or rng.randf() < 0.5 else 4), 9)
	var wall_a := clampi(pos - rng.randi_range(2, 3), 0, pos)
	var wall_b := clampi(pos + w + rng.randi_range(2, 3), pos + w, W)
	_connect(state, out, clampi(pos - 1, 0, W - w - 2), w + 2, h)
	_lane_rows(state, out, 3)
	var tlen := clampi(int(5.0 + it * 14.0 + rng.randi_range(0, 6)), 5, maxi(5, budget - 10))
	for _i in tlen:
		var r := _cells()
		if walled:
			_fill(r, wall_a, wall_b, flank_h)
		_fill(r, pos, pos + w, h, "T")
		out.append(_row_str(r))
	state.iface = {"pos": clampi(pos - 1, 0, W - w - 2), "w": w + 2, "h": h}
	_lane_rows(state, out, 3)

# Short pads separated by gaps: either alternating around a line or
# drifting steadily across the road.
static func _pat_islands(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var lim: Dictionary = state.lim
	var w := clampi(3 - (1 if it > 0.6 else 0) + (1 if rng.randf() < 0.25 else 0), 2, 4)
	var pad := clampi(4 - int(it * 2.0) + rng.randi_range(0, 1), 2, 5)
	var g := mini(1 + (1 if it > 0.7 else 0), _max_gap_rows(pad, lim))
	var off := 1 + int(it)
	var drift: bool = rng.randf() < 0.4
	var base := clampi(ifc.pos + (ifc.w - w) / 2, off, W - w - off)
	if drift:
		base = clampi(base, 0, W - w - 1)
	_connect(state, out, base, w, ifc.h)
	var reps := clampi(budget / (pad + g), 3, 7)
	var side := 1
	var dirn := 1 if base < (W - w) / 2 else -1
	for i in reps:
		var pos: int
		if drift:
			pos = clampi(base + dirn * off * i, 0, W - w)
		else:
			pos = clampi(base + side * off, 0, W - w)
		for _j in (pad if i < reps - 1 else 3):
			var r := _cells()
			_fill(r, pos, pos + w, ifc.h)
			out.append(_row_str(r))
		state.iface = {"pos": pos, "w": w, "h": ifc.h}
		ifc = state.iface
		side = -side
		if i < reps - 1:
			for _j in g:
				out.append(_row_str(_cells()))

# A narrow ledge along one edge; sometimes switches edges halfway.
static func _pat_ledge(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var w := 2 - (1 if it > 0.65 else 0)
	var pos := 0 if rng.randi() % 2 == 0 else W - w
	_connect(state, out, pos, w, ifc.h)
	var len_ := clampi(budget, 8, 12)
	if rng.randf() < 0.4 and budget >= 14:
		_lane_rows(state, out, len_ / 2)
		var other := W - w - pos
		_shift_lane(state, out, other, w, clampi(int((1.5 - it) * 7.0), 3, 9))
		_lane_rows(state, out, len_ / 2)
	else:
		_lane_rows(state, out, len_)

# Fork: a wide safe lane beside a narrow direct one, then merge.
static func _pat_split(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var safe_w := rng.randi_range(3, 4)
	var risky_w := 2 - (1 if it > 0.6 else 0)
	var flip: bool = rng.randi() % 2 == 0
	var len_ := clampi(budget - 6, 8, 16)
	_connect(state, out, 0, W, ifc.h)
	_lane_rows(state, out, 2)
	for _i in len_:
		var r := _cells()
		if flip:
			_fill(r, 0, risky_w + 1, ifc.h)
			_fill(r, W - safe_w, W, ifc.h)
		else:
			_fill(r, 0, safe_w, ifc.h)
			_fill(r, W - risky_w - 1, W - 1, ifc.h)
		out.append(_row_str(r))
	state.iface = {"pos": 0, "w": W, "h": ifc.h}
	_lane_rows(state, out, 2)

# Full-throttle straight with speed-gated gaps: the jump only connects at
# 75-100% throttle, and the run-up is sized so that speed is guaranteed to
# be reachable from a standstill.
static func _pat_speedway(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var lim: Dictionary = state.lim
	var w := rng.randi_range(7, 9)
	var pos := rng.randi_range(0, W - w)
	_connect(state, out, pos, w, ifc.h)
	var req := clampf(lerpf(0.55, 1.0, it) + rng.randf_range(-0.05, 0.05), 0.5, 1.0)
	var air: float = lim.air_time
	var g := maxi(2, int(req * 30.0 * air / 2.0) - 1)
	# run-up long enough to reach the required speed from zero (accel 12)
	var runup := maxi(8, int(ceil(pow(req * 30.0, 2.0) / 48.0)) + 2)
	# shrink the requirement until the set piece fits this stage
	while req > 0.5 and runup + g + 6 > budget:
		req -= 0.1
		g = maxi(2, int(req * 30.0 * air / 2.0) - 1)
		runup = maxi(8, int(ceil(pow(req * 30.0, 2.0) / 48.0)) + 2)
	var gaps := 2 if budget >= 2 * (runup + g) + 6 else 1
	# extra hard: the far side is a narrow strip you must aim for mid-flight
	var narrow_landing: bool = it > 0.8 and rng.randf() < 0.55
	var land_w := 1 if it > 0.9 and rng.randf() < 0.5 else 2
	var hh: int = state.iface.h
	_lane_rows(state, out, runup)
	for i in gaps:
		for _j in g:
			out.append(_row_str(_cells()))
		if narrow_landing:
			var lp := clampi(pos + (w - land_w) / 2 + rng.randi_range(-1, 1), 0, W - land_w)
			for _k in rng.randi_range(4, 7):
				var r := _cells()
				_fill(r, lp, lp + land_w, hh)
				out.append(_row_str(r))
			state.iface = {"pos": lp, "w": land_w, "h": hh}
			_connect(state, out, pos, w, hh)
		if i < gaps - 1:
			_lane_rows(state, out, runup)
	_lane_rows(state, out, 6)

# SkyRoads-style gates: a solid lane punctuated by block rows on a rhythm.
# Slot gates wander across the lane; at high intensity some gates are full
# walls to jump over; wide lanes sometimes get double slots.
static func _pat_gates(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var w := clampi(7 - int(it * 3.0) + rng.randi_range(0, 1) + int(state.style.width_bias), 3, 8)
	var pos := clampi(ifc.pos + (ifc.w - w) / 2 + rng.randi_range(-1, 1), 0, W - w)
	_connect(state, out, pos, w, ifc.h)
	var interval := clampi(5 - int(it * 3.0) + rng.randi_range(-1, 1), 2, 7)
	var block_h: int = mini(ifc.h + 2, 9)
	var slot_w := clampi(3 - int(it * 2.0), 1, 3)
	var wall_chance := rng.randf_range(0.1, 0.5) if it > 0.5 else 0.0
	var reps := clampi(budget / (interval + 1), 3, 8)
	var slot_side := rng.randi_range(0, 2)
	for i in reps:
		_lane_rows(state, out, interval)
		var r := _cells()
		_fill(r, pos, pos + w, block_h)
		if rng.randf() >= wall_chance:
			var sp: int = pos
			if slot_side == 1:
				sp = pos + (w - slot_w) / 2
			elif slot_side == 2:
				sp = pos + w - slot_w
			_fill(r, sp, sp + slot_w, ifc.h)
			if w >= 6 and rng.randf() < 0.3:
				var sp2 := pos + w - slot_w if slot_side == 0 else pos
				_fill(r, sp2, sp2 + slot_w, ifc.h)
			slot_side = (slot_side + 1 + rng.randi_range(0, 1)) % 3
		out.append(_row_str(r))
	_lane_rows(state, out, 2)

# SkyRoads-style rail lattice: 2-4 thin parallel rails over the void.
# Rails drop out for a stretch (hop to a neighbour) and grow gate blocks
# at high intensity.
static func _pat_rails(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var rw := 1 if it > 0.45 or rng.randf() < 0.5 else 2
	var nrails := clampi(4 - int(it * 2.0), 2, 4)
	var spacing := rw + rng.randi_range(1, 2)
	var span := mini((nrails - 1) * spacing + rw, W)
	var base := rng.randi_range(0, W - span)
	var rails: Array = []
	for i in nrails:
		rails.append(base + i * spacing)
	_connect(state, out, base, span, ifc.h)
	_lane_rows(state, out, 1)
	var h: int = ifc.h
	var segs := clampi(budget / 6, 3, 7)
	var gate_chance := clampf(it - 0.35, 0.0, 0.45)
	var drop_chance := clampf(0.25 + it * 0.35, 0.25, 0.6)
	for s in segs:
		var seg_len := rng.randi_range(3, 6)
		var dropped := -1
		if s > 0 and rng.randf() < drop_chance:
			dropped = rng.randi() % nrails
			# hop window: all rails present so the switch is never a teleport
			for _hw in 2:
				var hr := _cells()
				for i in nrails:
					_fill(hr, rails[i], rails[i] + rw, h)
				out.append(_row_str(hr))
		for r_i in seg_len:
			var r := _cells()
			for i in nrails:
				if i != dropped:
					_fill(r, rails[i], rails[i] + rw, h)
			if r_i == seg_len - 1 and rng.randf() < gate_chance:
				var gi := rng.randi() % nrails
				if gi != dropped:
					_fill(r, rails[gi], rails[gi] + rw, mini(h + 2, 9))
			out.append(_row_str(r))
	# converge: all rails present once more, then continue on one of them
	for _hw in 2:
		var cr := _cells()
		for i in nrails:
			_fill(cr, rails[i], rails[i] + rw, h)
		out.append(_row_str(cr))
	var keep: int = rails[rng.randi() % nrails]
	state.iface = {"pos": keep, "w": rw, "h": h}
	_lane_rows(state, out, 2)

# A lane with rhythmic bites taken out of alternating sides: a slalom
# within the road. Bites get wider and deeper with intensity.
static func _pat_checker(state: Dictionary, out: Array, it: float, budget: int):
	var rng: RandomNumberGenerator = state.rng
	var ifc: Dictionary = state.iface
	var w := clampi(6 - int(it * 1.5) + rng.randi_range(0, 1), 4, 7)
	var pos := clampi(ifc.pos + (ifc.w - w) / 2 + rng.randi_range(-1, 1), 0, W - w)
	_connect(state, out, pos, w, ifc.h)
	var clean := clampi(4 - int(it * 2.0), 1, 4)
	var bite := clampi(1 + int(it * 2.0) + rng.randi_range(0, 1), 1, w - 2)
	var deep := 1 + (1 if it > 0.65 and rng.randf() < 0.5 else 0)
	var reps := clampi(budget / (clean + deep), 3, 9)
	var side := rng.randi() % 2
	for i in reps:
		_lane_rows(state, out, clean)
		for _d in deep:
			var r := _cells()
			_fill(r, pos, pos + w, ifc.h)
			if side == 0:
				_erase(r, pos, pos + bite)
			else:
				_erase(r, pos + w - bite, pos + w)
			out.append(_row_str(r))
		side = 1 - side
	_lane_rows(state, out, 2)

# ---------------- connectors and row helpers ----------------

# Bring the current interface to the target lane and height: lateral bridge
# first (contiguous fill covering both spans per row), then legal height
# steps (climbs limited to max_step per landing).
static func _connect(state: Dictionary, out: Array, tpos: int, tw_: int, th: int):
	var ifc: Dictionary = state.iface
	if tpos != ifc.pos or tw_ != ifc.w:
		var sharp: float = state.p.get("sharpness", 0.12)
		var dist := absi(tpos - ifc.pos)
		var steps := clampi(int(float(maxi(dist, 1)) * clampf(0.6 - sharp, 0.15, 0.6) * 2.0), 2, 10)
		var pos_f := float(ifc.pos)
		var stepv := float(tpos - ifc.pos) / float(steps)
		var prev: int = ifc.pos
		var prev_w: int = ifc.w
		for _i in steps:
			pos_f += stepv
			var cur := clampi(roundi(pos_f), 0, W - tw_)
			var r := _cells()
			_fill(r, mini(cur, prev), maxi(cur + tw_, prev + prev_w), ifc.h)
			out.append(_row_str(r))
			prev = cur
			prev_w = tw_
		state.iface = {"pos": tpos, "w": tw_, "h": ifc.h}
		ifc = state.iface
	if th != ifc.h:
		var lim: Dictionary = state.lim
		while ifc.h < th:
			ifc.h = mini(ifc.h + int(lim.max_step), th)
			_lane_rows(state, out, 3)
		if ifc.h > th:
			ifc.h = th
			_lane_rows(state, out, 2)

# Quick lane switch used inside patterns (bounded bridge).
static func _shift_lane(state: Dictionary, out: Array, tpos: int, tw_: int, steps: int):
	var ifc: Dictionary = state.iface
	var pos_f := float(ifc.pos)
	var stepv := float(tpos - ifc.pos) / float(steps)
	var prev: int = ifc.pos
	for _i in steps:
		pos_f += stepv
		var cur := clampi(roundi(pos_f), 0, W - tw_)
		var r := _cells()
		_fill(r, mini(cur, prev), maxi(cur + tw_, prev + tw_), ifc.h)
		out.append(_row_str(r))
		prev = cur
	state.iface = {"pos": tpos, "w": tw_, "h": ifc.h}

static func _lane_rows(state: Dictionary, out: Array, n: int):
	var ifc: Dictionary = state.iface
	for _i in n:
		var r := _cells()
		_fill(r, ifc.pos, ifc.pos + ifc.w, ifc.h)
		out.append(_row_str(r))

static func _max_gap_rows(runup_rows: int, lim: Dictionary) -> int:
	# Top speed reachable over the run-up from a standstill (accel 12,
	# max speed 30), then rows crossed in one full jump, minus a landing row
	var v := minf(30.0, sqrt(2.0 * 12.0 * float(runup_rows) * 2.0))
	var air_time: float = lim.air_time
	return maxi(1, int(v * air_time / 2.0) - 1)

static func _cells() -> Array:
	var r := []
	r.resize(W)
	for i in W:
		r[i] = ".."
	return r

static func _fill(r: Array, a: int, b: int, h: int, m := "."):
	for i in range(maxi(0, a), mini(W, b)):
		r[i] = str(h) + m

static func _erase(r: Array, a: int, b: int):
	for i in range(maxi(0, a), mini(W, b)):
		r[i] = ".."

static func _row_str(r: Array) -> String:
	return "".join(PackedStringArray(r))
