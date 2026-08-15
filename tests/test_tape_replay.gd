# Trajectory-verifies solve_level.py's physics port against the real engine:
# loads the level into Game.tscn, feeds the solver's input tape to the ship
# tick by tick, and requires the ship's per-entry trajectory to match the
# solver's own predicted trace for the opening stretch of the level. Any
# rule-level drift between the Python port and ship.gd (a constant, a coyote
# window, a bounce rule) desyncs the trace within a few entries and fails
# loudly here. Full-tape survival is NOT required: engine contact resolution
# differs from the analytic port by a few millimetres per touch, which
# accumulates into open-loop desync deep into a level - that is expected.
#
# The tape and reference trace come from the solver (two steps):
#   python solve_level.py Levels/nebula_1.txt --tape tests/tapes/nebula_1.tape --dump-trace tests/tapes/nebula_1.ref
#   godot --headless --path . -s tests/test_tape_replay.gd -- Levels/nebula_1.txt tests/tapes/nebula_1.tape tests/tapes/nebula_1.ref
#
# Optional fourth arg: ticks each tape line is held (the solver's --k, default 3).
extends SceneTree

const THEMES := {"cosmic": 0, "nebula": 1, "solar": 2, "dark": 3}
# The opening stretch that must match (runway, first bounces, first jumps),
# and how far the engine may deviate per axis before it counts as drift
const CHECK_ENTRIES := 50
const TOL_Z := 0.05
const TOL_X := 0.08
const TOL_Y := 0.12

var _feeder: TapeFeeder
var _ref: PackedStringArray = []
var _deadline := 0
var _level_name := ""

func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("usage: godot --headless --path . -s tests/test_tape_replay.gd -- <level.txt> <tape.txt> <trace.ref> [ticks-per-line]")
		quit(2)
		return
	var tape_text := FileAccess.get_file_as_string(args[1])
	var ref_text := FileAccess.get_file_as_string(args[2])
	if tape_text.strip_edges() == "" or ref_text.strip_edges() == "":
		printerr("FAIL: empty or unreadable tape/trace: %s / %s" % [args[1], args[2]])
		quit(2)
		return
	var tape: Array[String] = []
	for line in tape_text.split("\n"):
		if line.strip_edges() != "":
			tape.append(line)
	for line in ref_text.split("\n"):
		if line.strip_edges() != "":
			_ref.append(line)

	_level_name = args[0].get_file()
	var level_path: String = args[0]
	if not level_path.begins_with("res://") and not level_path.is_absolute_path():
		level_path = "res://" + level_path

	var gs = root.get_node("GameState")
	gs.selected_level = level_path
	gs.selected_group = THEMES.get(_level_name.split("_")[0], 0)
	gs.run_records = false
	gs.is_endless = false
	gs.generated_content = ""
	gs.gen_params = {}
	gs.autopilot = false

	_feeder = TapeFeeder.new()
	_feeder.tape = tape
	if args.size() > 3:
		_feeder.k = maxi(1, int(args[3]))

	print("replaying %s (%d inputs x %d ticks) on %s" % [args[1].get_file(), tape.size(), _feeder.k, _level_name])
	_deadline = Time.get_ticks_msec() + 120000
	change_scene_to_file("res://Scenes/Game.tscn")

func _process(_delta) -> bool:
	if _deadline == 0:
		return false
	if Time.get_ticks_msec() > _deadline:
		printerr("FAIL: timeout before %d entries were traced (%s)" % [CHECK_ENTRIES, _level_name])
		quit(1)
		return true
	var game = current_scene
	if game == null or game.get_class() != "Node3D":
		return false
	var ship = game.get_node_or_null("Ship")
	if ship == null:
		return false
	if _feeder.get_parent() == null:
		_feeder.ship = ship
		root.add_child(_feeder)
	var traced := _feeder.trace.size()
	if traced > CHECK_ENTRIES or game._finishing:
		_verdict(mini(traced, CHECK_ENTRIES))
		return true
	if ship._state == 2:  # EXPLODING
		if traced >= CHECK_ENTRIES:
			_verdict(CHECK_ENTRIES)
		else:
			printerr("FAIL: ship exploded after only %d/%d traced entries (%s)" % [traced, CHECK_ENTRIES, _level_name])
			quit(1)
		return true
	return false

func _verdict(n: int):
	var worst := 0.0
	for i in n:
		if i >= _ref.size():
			break
		var e := _feeder.trace[i].split(" ")
		var r := _ref[i].split(" ")
		var dz := absf(e[1].to_float() - r[1].to_float())
		var dx := absf(e[2].to_float() - r[2].to_float())
		var dy := absf(e[3].to_float() - r[3].to_float())
		worst = maxf(worst, maxf(dz, maxf(dx, dy)))
		if dz > TOL_Z or dx > TOL_X or dy > TOL_Y:
			printerr("FAIL: trajectory diverged from the solver at entry %d: dz=%.3f dx=%.3f dy=%.3f (%s)" % [i, dz, dx, dy, _level_name])
			printerr("  solver: %s" % _ref[i])
			printerr("  engine: %s" % _feeder.trace[i])
			quit(1)
			return
	print("TAPE REPLAY OK: %s (%d entries match the solver's trace, worst deviation %.3f)" % [_level_name, n, worst])
	quit(0)

# Applies one tape line per k physics ticks, before the ship's own tick.
# Direction/throttle are level-based and land same-frame; the jump channel
# needs edge semantics and frame-offset handling - see the comments inside.
class TapeFeeder extends Node:
	var ship: CharacterBody3D
	var tape: Array[String] = []
	var k := 3
	var idx := 0
	var trace: PackedStringArray = []
	var _sub := 0
	var _held := {}
	var _jump_armed := false

	func _ready():
		process_physics_priority = -1

	func _physics_process(_delta):
		if ship == null or ship.frozen:
			return
		if _sub == 0 and idx < tape.size():
			trace.append("%d %.3f %.3f %.3f %.3f %.3f" % [idx, ship.global_position.z, ship.global_position.x, ship.global_position.y, ship._vertical_velocity, ship.current_speed])
		var line := "..."
		if idx < tape.size():
			line = tape[idx]
		_press("ui_up", line[0] == "W")
		_press("ui_down", line[0] == "S")
		_press("ui_left", line.length() > 1 and line[1] == "A")
		_press("ui_right", line.length() > 1 and line[1] == "D")
		# A press at physics frame T reads as just-pressed at T+1, and any
		# re-press before the read destroys the pending edge - so the jump
		# channel feeds the NEXT tick's tape line with a single edge per
		# fire window. The gate mirrors the solver's per-tick jump attempt
		# (no firing while ascending, never on a bounce-response frame);
		# re-arming on gate closure lets a long J run fire again the way
		# the solver's model can (e.g. after a mid-run landing).
		var next_line := "..."
		var nidx := idx if _sub + 1 < k else idx + 1
		if nidx < tape.size():
			next_line = tape[nidx]
		var want_jump: bool = next_line.length() > 2 and next_line[2] == "J"
		# Predict next-tick vy (one gravity step) so the gate matches what
		# the solver evaluates on the tick the press actually lands
		var vy: float = ship._vertical_velocity
		var vy_next: float = vy if ship.is_on_floor() else vy - ship.gravity / 60.0
		var gate_open: bool = vy_next <= 0.5 and not (ship.is_on_floor() and vy < -1.0)
		if want_jump and gate_open and not _jump_armed:
			Input.action_release("ui_accept")
			Input.action_press("ui_accept")
			_jump_armed = true
		elif not want_jump:
			Input.action_release("ui_accept")
			_jump_armed = false
		elif not gate_open:
			_jump_armed = false
		if idx < tape.size():
			_sub += 1
			if _sub >= k:
				_sub = 0
				idx += 1

	func _press(action: String, pressed: bool):
		if _held.get(action, false) == pressed:
			return
		_held[action] = pressed
		if pressed:
			Input.action_press(action)
		else:
			Input.action_release(action)
