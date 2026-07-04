# Testing

Headless tests for physics, level generation, and level completability.

**Prerequisites**: Godot 4.6 (the plain build, not mono, if you also want to
export) and Python 3.10+. The commands below assume `godot` on PATH —
substitute the full path to the editor binary. All commands run from the
repo root.

## Test inventory

### 1. Autopilot regression — `Scripts/test_autopilot.gd`

Self-contained simulation of the heuristic autopilot against the first two
authored levels of each group.

    godot --headless --path . -s Scripts/test_autopilot.gd

Prints a per-level result and a success rate. This tests the *autopilot
heuristic*, not level completability — a failure here means the autopilot is
weak, not that the level is broken (use the solver for that).

### 2. Generator constraints — `tests/gen_constraints.gd`

Generates 320 tracks (80 per theme) at maximum difficulty settings and
statically verifies the invariants the generator guarantees: climbable steps,
gaps within the run-up/air-time budget, landings at or below takeoff height.

    godot --headless --path . -s tests/gen_constraints.gd

Pass: `checked 320 tracks, 0 violations`. The limit formulas in this script
mirror `LevelGenerator.chunk_begin()` — when you change one, change both.

### 3. Gameplay smokes — `tests/smoke_*.gd`

End-to-end scene tests: build pipeline, GET READY gating, music playback,
endless chunking/cleanup/death-reset.

    godot --headless --path . -s tests/smoke_music.gd
    godot --headless --path . -s tests/smoke_dark.gd
    godot --headless --path . -s tests/smoke_endless.gd
    godot --headless --path . -s tests/smoke_menu.gd

Each prints `... SMOKE OK` on success.

### 4. Reachability solver — `solve_level.py`

Proves whether a level can be completed by searching the full input space
against a Python port of the ship physics. `COMPLETABLE` always comes with a
working input tape and is trustworthy; `LIKELY NOT COMPLETABLE` /
`UNDECIDED` are budget-relative (see caveats).

Simulates **classical mode by default** (the game's default): steering
scales with throttle (25-60% of 15 u/s), locks at takeoff for the whole
jump, and the coyote window is `y < floor+0.4, -2.5 < vy < 0`. Use
`--normal` for the free-steering dev mode. Classical abilities are a
strict subset of normal, so classical-`COMPLETABLE` implies normal too.

    python solve_level.py                          # all Levels/*.txt
    python solve_level.py Levels/nebula_1.txt --budget 120
    python solve_level.py track.txt --theme 2 --tape tape.txt

Flags:

| Flag | Meaning |
|---|---|
| `--theme N` | 0 Cosmic, 1 Nebula, 2 Solar, 3 Dark (default: from filename prefix) |
| `--budget S` | wall-clock seconds per level (default 60) |
| `--k N` | ticks each input is held; 3 = 20 Hz decisions (lower = superhuman precision) |
| `--stall N` | expansions without frontier progress before giving up (default 400k) |
| `--exploits` | allow the banked air-jump (physics as shipped; default models intended physics) |
| `--normal` | simulate normal mode (free air steering) instead of classical |
| `--tape F` | write the winning input tape (`W/S` + `A/D` + `J` per line) |

Expected: all 15 authored levels report `COMPLETABLE` within seconds.

**Caveats**: routes that need deep movement tech (bounce chains, coyote-delay
jumps) can hide behind millions of states — before trusting a "no" on a
suspicious level, retry with `--stall 5000000 --budget 600`. State bucketing
can in principle cause a false "no", never a false "yes".

### 5. Track texture analyzer — `analyze_levels.py`

Quantifies how "eventful" a track is row by row, for tuning the generator
against the extracted SkyRoads roads (`tests/skyroads/`, local only). The
headline metric is the *dull run*: consecutive wide, flat, unfragmented,
unchanged rows — long dull runs are the boring stretches.

    godot --headless --path . -s tests/dump_tracks.gd
    python analyze_levels.py "tests/samples/*.txt" --summary
    python analyze_levels.py "tests/skyroads/road_*.txt" --summary

SkyRoads reference (mean): dullmax ~5.6, dull8% ~4, gap ~8%, frag ~31%,
tun ~16%, w_avg ~3.0 *on a 7-wide grid* (≈4.2 scaled to our 10), ev/row
~0.74. Generator output should sit in that neighbourhood: dullmax under
~10 on every track, dull8% near zero, ev/row 0.55+.

Authored sets are regenerated reproducibly with fixed seeds:

    godot --headless --path . -s tests/regen_levels.gd

then re-verify with the solver (step 4) — every regenerated level must be
`COMPLETABLE`. Originals live in `raw/levels_original/`.

### 6. Adversarial probes — `tests/make_adversarial.py`

Corner-case levels for validating the *solver* (and for documenting what the
movement system really allows):

    python tests/make_adversarial.py
    python solve_level.py tests/adversarial/wall_h4.txt --theme 0 --budget 120

Expected verdicts under current mechanics (theme 0, `--budget 120`).
Classical (default) kills every trick that needed mid-air steering or the
loose normal-mode coyote window; the normal column preserves the old
movement-tech snapshot (run with `--normal`):

| Level | Classical | Normal | Why |
|---|---|---|---|
| wall_h4 | COMPLETABLE | COMPLETABLE | 1.5u step, apex crossing at low speed |
| wall_h5 | LIKELY NOT | COMPLETABLE | 2.0u step needs bounce + steered coyote jump |
| gap_20 | LIKELY NOT | LIKELY NOT | 40u gap, beyond all tech in either mode |
| pogo | COMPLETABLE | COMPLETABLE | 1-row pad between gaps, straight bounce chain |
| lateral_ok | COMPLETABLE | COMPLETABLE | committed drift covers it |
| lateral_far | LIKELY NOT | COMPLETABLE | needed lip-bounce double-arc air steering |
| zigzag | COMPLETABLE | COMPLETABLE | corner-to-corner tiles are drivable slowly |
| tunnel_ok | COMPLETABLE | COMPLETABLE | positive control: forced flat tunnel |
| tunnel_climb | LIKELY NOT | LIKELY NOT | height step inside a tunnel; no jumping under the roof |
| speed_tight | LIKELY NOT | COMPLETABLE | normal-only bounce-touch chaining |
| speed_ok | COMPLETABLE | COMPLETABLE | run-up sized for the jump |
| bounce_gate | LIKELY NOT | COMPLETABLE | normal needs `--stall 5000000 --budget 600`; coyote-delay tech |

If a verdict here changes after a mechanics tweak, that is the point — the
table is a movement-tech regression snapshot, not a pass/fail suite.

## When game mechanics change

The ship physics is intentionally mirrored in several places. Change one,
sync the rest, rerun everything:

| What changed | Update |
|---|---|
| Ship movement (`Scripts/ship.gd`: accel, max/lateral speed, bounce, coyote rule, jump handling) | `solve_level.py` header constants + `tick()` logic; gap/step formulas in `LevelGenerator.chunk_begin()` and `tests/gen_constraints.gd` |
| Classical-mode rules (`ship.gd`: throttle-scaled steering, takeoff lock, classical coyote window) | `in_coyote()` + the classical branches in `solve_level.py::tick()`; the sim in `Scripts/test_autopilot.gd`; the rail-hop spacing cap in `LevelGenerator._pat_rails()` |
| Per-group gravity/jump | `LevelGenerator.GROUP_GRAVITY` / `GROUP_JUMP_VELOCITY` (single source for game + generator), and the same two arrays in `solve_level.py` |
| Ship collision box (`Scenes/Ship.tscn`) | `HALF_W/HALF_L/HALF_H` in `solve_level.py` |
| Tile size / tunnel arch geometry (`Scripts/game.gd`) | `TUNNEL_OPEN` / `TUNNEL_CEIL` and tile math in `solve_level.py`; `TILE_SIZE`-derived constants in `Scripts/test_autopilot.gd` |
| Generator segment shapes | invariants in `tests/gen_constraints.gd` |

Then, in order:

1. `godot --headless --path . -s tests/gen_constraints.gd` — generator still
   provably fair under the new physics.
2. `python solve_level.py` — all authored levels still completable. If one
   fails, the report names the row where every path dies; fix the level or
   the physics.
3. `python tests/make_adversarial.py` + spot-check the table above — shows
   what the new movement tech allows; update the table.
4. The smokes, for general breakage.

The solver's `tick()` is ~100 lines and is the ground-truth mirror of
`ship.gd::_physics_process` — when in doubt, diff those two side by side.

## Music and web build

- `python bake_music.py` — regenerates `Music/*.ogg` after editing the
  patterns in it (requires ffmpeg).
- `python serve_web.py` — serves `Builds/` with the cross-origin isolation
  headers the threaded web export needs (see README).
