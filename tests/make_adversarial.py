#!/usr/bin/env python3
"""Generate adversarial corner-case levels for probing solve_level.py.

Writes tests/adversarial/*.txt (gitignored). Expected verdicts for the
CURRENT mechanics are listed in TESTING.md - re-derive them if ship physics
change. Run from the repo root:

  python tests/make_adversarial.py
  python solve_level.py tests/adversarial/wall_h4.txt --theme 0 --budget 120
"""
from pathlib import Path

OUT = Path(__file__).parent / "adversarial"
OUT.mkdir(exist_ok=True)


def lane(c0, c1, h, m="."):
    return "".join(f"{h}{m}" if c0 <= c <= c1 else ".." for c in range(10))


def comp(*segs):
    cells = [".."] * 10
    for c0, c1, h, m in segs:
        for c in range(c0, c1 + 1):
            cells[c] = f"{h}{m}"
    return "".join(cells)


full = lambda h: lane(0, 9, h)
E = ".." * 10


def w(name, rows):
    (OUT / name).write_text("\n".join(rows))
    print(f"  {name}: {len(rows)} rows")


# Walls (30 rows deep so they can't be flown around off-grid)
w("wall_h4.txt", [full(1)]*30 + [full(4)]*30 + [full(1)]*5)   # 1.5u step
w("wall_h5.txt", [full(1)]*30 + [full(5)]*30 + [full(1)]*5)   # 2.0u step
# Gaps
w("gap_20.txt", [full(1)]*40 + [E]*20 + [full(1)]*5)          # 40u
w("pogo.txt", [full(1)]*30 + [E]*5 + [full(1)]*1 + [E]*5 + [full(1)]*5)
# Lateral transfers (no overlapping columns, no gap row)
w("lateral_ok.txt", [lane(0,1,1)]*30 + [lane(7,8,1)]*20 + [full(1)]*3)
w("lateral_far.txt", [lane(0,1,1)]*30 + [lane(9,9,1)]*20 + [full(1)]*3)
# Corner-to-corner diagonal 1-wide staircase
zig = []
for c in range(2, 10):
    zig += [lane(c, c, 1)] * 3
w("zigzag.txt", zig + [full(1)]*3)
# Forced tunnels (h9 flanks prevent bypass)
walls_lead = comp((0,2,9,"."), (3,5,2,"."), (6,9,9,"."))
walls_t2 = comp((0,2,9,"."), (3,5,2,"T"), (6,9,9,"."))
walls_t3 = comp((0,2,9,"."), (3,5,3,"T"), (6,9,9,"."))
w("tunnel_ok.txt", [full(1)]*10 + [walls_lead]*3 + [walls_t2]*8 + [walls_lead]*3 + [full(1)]*5)
w("tunnel_climb.txt", [full(1)]*10 + [walls_lead]*3 + [walls_t2]*4 + [walls_t3]*4
  + [walls_t2]*4 + [walls_lead]*3 + [full(1)]*5)
# Speed-history trap: far transfer onto a short pad caps speed before a gap
w("speed_tight.txt", [lane(0,1,1)]*20 + [lane(8,9,1)]*4 + [E]*13 + [full(1)]*5)
w("speed_ok.txt", [lane(0,1,1)]*20 + [lane(8,9,1)]*4 + [full(1)]*31 + [E]*13 + [full(1)]*5)
# Staircase to h9 ledge, void valley, h6 wall (deep-tech jump routes;
# needs a raised --stall to resolve, see TESTING.md)
w("bounce_gate.txt", [full(1)]*10 + [full(3)]*3 + [full(5)]*3 + [full(7)]*3
  + [full(9)]*3 + [E]*15 + [full(6)]*20 + [full(1)]*3)
