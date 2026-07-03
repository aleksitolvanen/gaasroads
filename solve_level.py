#!/usr/bin/env python3
"""Reachability solver: proves whether a level can be completed.

Ports the ship physics (Scripts/ship.gd, normal mode) and searches the full
input space with a best-first sweep along the track, deduplicating states
into buckets. A COMPLETABLE verdict comes with a working input tape; NOT
COMPLETABLE means the entire (bucketed) state space drains before the goal,
and the report shows the row where every path dies. Margins are conservative,
so frame-perfect tricks may be rejected - by design.

Usage:
  python solve_level.py                    # all Levels/*.txt
  python solve_level.py Levels/nebula_1.txt --budget 120
  python solve_level.py file.txt --theme 2 --tape tape.txt
"""
import argparse
import heapq
import math
import sys
import time
from pathlib import Path

DT = 1.0 / 60.0
ACCEL = 12.0
MAX_SPEED = 30.0
LAT_SPEED = 15.0
BOUNCE = 0.45
HALF_W = 0.35        # ship half width
HALF_L = 0.5         # ship half length
HALF_H = 0.15        # ship half height
SNAP = 0.12
WALL_EPS = 0.05
TUNNEL_OPEN = 0.55   # max |x - tunnel center| to fit through the arch
TUNNEL_CEIL = 1.1

GROUP_GRAVITY = [20.0, 20.0, 12.0, 8.0]
GROUP_JUMP = [8.0, 8.0, 10.0, 7.8]
THEMES = {"cosmic": 0, "nebula": 1, "solar": 2, "dark": 3}

# thr, lat, jump
INPUTS = [(t, l, j) for t in (1, 0, -1) for l in (0, -1, 1) for j in (False, True)]


def load_level(path):
    tops, tun = [], []
    runway = [0.5 if 2 <= c <= 7 else 0.0 for c in range(10)]
    for _ in range(24):
        tops.append(runway)
        tun.append([False] * 10)
    for line in Path(path).read_text().splitlines():
        if not line.strip():
            continue
        row, trow = [0.0] * 10, [False] * 10
        for ci in range(0, min(len(line), 20), 2):
            ch = line[ci]
            if "1" <= ch <= "9":
                row[ci // 2] = int(ch) * 0.5
            if ci + 1 < len(line) and line[ci + 1] in "Tt":
                trow[ci // 2] = True
        tops.append(row)
        tun.append(trow)
    return tops, tun


def solve(tops, tun, grav, jump_v, budget_s, k=3, max_states=4_000_000, strict=True, stall_limit=400_000):
    rows = len(tops)
    goal_u = (rows - 1) * 2.0
    ncols = 10

    def cols_at(x):
        c0 = int(math.floor((x - HALF_W + 1.0) / 2.0))
        c1 = int(math.floor((x + HALF_W + 1.0) / 2.0))
        return max(0, c0), min(ncols - 1, c1)

    def rows_at(u):
        r0 = int(math.floor((u - HALF_L + 1.0) / 2.0))
        r1 = int(math.floor((u + HALF_L + 1.0) / 2.0))
        return max(0, r0), min(rows - 1, r1)

    def bucket(s):
        u, x, y, vy, spd, cj, lfy = s
        ub = int(u * 2)
        xb = int(x * 2)
        sb = int(spd)
        bottom = y - HALF_H
        r0, r1 = rows_at(u)
        c0, c1 = cols_at(x)
        grounded = vy == 0.0 and any(
            abs(tops[r][c] - bottom) <= SNAP and tops[r][c] > 0.0
            for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)
        )
        if grounded:
            return (1, ub, xb, sb)
        return (0, ub, xb, int((y + 11.0) * 2.5), int((vy + 31.0) / 1.5), sb, cj, int(lfy * 2))

    def tick(s, thr, lat, jmp):
        # returns (state, dead, done)
        u, x, y, vy, spd, cj, lfy = s
        spd = min(MAX_SPEED, max(0.0, spd + thr * ACCEL * DT))
        bottom = y - HALF_H

        # support under current position
        r0, r1 = rows_at(u)
        c0, c1 = cols_at(x)
        top = -1.0
        for r in range(r0, r1 + 1):
            for c in range(c0, c1 + 1):
                t = tops[r][c]
                if t > 0.0 and bottom - SNAP <= t <= bottom + WALL_EPS and t > top:
                    top = t
        onf = top >= 0.0 and vy <= 0.0
        if onf:
            y = top + HALF_H
            lfy = y
            vy = 0.0
            cj = True
        else:
            vy -= grav * DT
            # The game banks can_jump forever after leaving the floor (one
            # free air-jump - an exploit). Strict mode expires it with the
            # coyote window so verdicts reflect intended physics.
            if strict and cj and not (y < lfy + 0.55 and vy > -2.5):
                cj = False

        in_tunnel = any(tun[r][c] for r in range(r0, r1 + 1) for c in range(c0, c1 + 1))
        # vy guard: the real jump is edge-triggered, so it can't re-fire while
        # still ascending from the previous press
        if jmp and not in_tunnel and vy <= 0.5 and (cj or onf or (y < lfy + 0.55 and vy > -2.5)):
            vy = jump_v
            cj = False
            onf = False

        nx = x + lat * LAT_SPEED * DT
        ny = y + vy * DT
        nu = u + spd * DT
        nbottom = ny - HALF_H

        # lateral walls at current rows
        nc0, nc1 = cols_at(nx)
        for r in range(r0, r1 + 1):
            for c in range(nc0, nc1 + 1):
                if (c < c0 or c > c1) and tops[r][c] > bottom + WALL_EPS:
                    nx = x  # blocked sideways
                    nc0, nc1 = c0, c1
                    break

        # forward walls / tunnel arches on newly entered rows; judge by the
        # ship's height at the moment its front crosses the row's face, so a
        # descent onto a plateau counts as landing while a mid-tick rise
        # can't cheat over a wall
        nr0, nr1 = rows_at(nu)
        for r in range(r1 + 1, nr1 + 1):
            f = 0.0
            if nu > u:
                f = max(0.0, min(1.0, (2.0 * r - 1.0 - (u + HALF_L)) / (nu - u)))
            cross_bottom = bottom + f * (nbottom - bottom) - 0.02
            blocked = False
            fatal_speed = 5.0
            for c in range(nc0, nc1 + 1):
                t = tops[r][c]
                if tun[r][c] and t > 0.0:
                    fatal_speed = 8.0
                    misaligned = abs(nx - c * 2.0) > TUNNEL_OPEN
                    if nbottom > t + WALL_EPS or misaligned or vy > 0.5:
                        blocked = True  # arch face, roof span, or bad approach
                elif t > cross_bottom + WALL_EPS:
                    blocked = True
            if blocked:
                if spd > fatal_speed:
                    return None, True, False
                # epsilon keeps the wall row out of next tick's overlap set
                nu = min(nu, 2.0 * r - 1.0 - HALF_L - 0.01)
                nr0, nr1 = rows_at(nu)
                break

        # tunnel ceiling
        if vy > 0.0:
            for r in range(nr0, nr1 + 1):
                for c in range(nc0, nc1 + 1):
                    if tun[r][c] and tops[r][c] > 0.0:
                        cap = tops[r][c] + TUNNEL_CEIL - HALF_H
                        if ny > cap:
                            ny = cap
                            vy = 0.0

        # landing
        if vy < 0.0:
            land = -1.0
            for r in range(nr0, nr1 + 1):
                for c in range(nc0, nc1 + 1):
                    t = tops[r][c]
                    if t > 0.0 and ny - HALF_H <= t <= bottom + WALL_EPS and t > land:
                        land = t
            if land >= 0.0:
                ny = land + HALF_H
                if vy < -1.0:
                    vy = -vy * BOUNCE
                else:
                    vy = 0.0
                cj = True
                lfy = ny

        # Below every possible floor top (min 0.5) minus snap: can never land
        if vy < 0.0 and ny - HALF_H < 0.5 - SNAP:
            return None, True, False
        if nu >= goal_u:
            return (nu, nx, ny, vy, spd, cj, lfy), False, True
        return (nu, nx, ny, vy, spd, cj, lfy), False, False

    from collections import deque

    start = (0.0, 9.0, 1.0, 0.0, 12.0, True, 1.0)
    sb = bucket(start)
    visited = {sb}
    expanded = set()
    parents = {}
    heap = [(-0.0, 0, sb, start)]
    fifo = deque([(sb, start, 0)])
    best_u = 0.0
    states = 0
    stall = 0
    t0 = time.monotonic()

    while heap or fifo:
        if states % 2048 == 0 and time.monotonic() - t0 > budget_s:
            return "UNDECIDED", best_u, states, None
        if states > max_states:
            return "UNDECIDED", best_u, states, None
        if stall > stall_limit:
            return "LIKELY NOT COMPLETABLE", best_u, states, None
        # Mostly greedy by progress, but every 8th expansion is FIFO so early
        # branch points can't be starved by a hopeless far-ahead frontier
        key = None
        if fifo and (states % 8 == 0 or not heap):
            key, s, ticks = fifo.popleft()
        elif heap:
            _, ticks, key, s = heapq.heappop(heap)
        if key in expanded:
            continue
        expanded.add(key)
        states += 1
        # jump input is a no-op unless it can actually fire
        can_fire = s[3] <= 0.5 and (s[5] or (s[2] < s[6] + 0.55 and s[3] > -2.5))
        for idx, (thr, lat, jmp) in enumerate(INPUTS):
            if jmp and not can_fire:
                continue
            cur = s
            dead = done = False
            for _ in range(k):
                cur, dead, done = tick(cur, thr, lat, jmp)
                if dead or done:
                    break
            if dead:
                continue
            nkey = bucket(cur)
            if not done and nkey in visited:
                continue
            visited.add(nkey)
            parents[nkey] = (key, idx)
            if cur[0] > best_u:
                best_u = cur[0]
                stall = 0
            else:
                stall += 1
            if done:
                tape = []
                walk = nkey
                while walk != sb:
                    walk, i = parents[walk]
                    tape.append(i)
                tape.reverse()
                return "COMPLETABLE", cur[0], states, tape
            heapq.heappush(heap, (-cur[0], ticks + k, nkey, cur))
            fifo.append((nkey, cur, ticks + k))

    return "NOT COMPLETABLE", best_u, states, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--theme", type=int, default=None)
    ap.add_argument("--budget", type=float, default=60.0)
    ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--tape", default=None)
    ap.add_argument("--exploits", action="store_true",
                    help="allow banked air-jumps (physics as shipped)")
    ap.add_argument("--stall", type=int, default=400_000)
    args = ap.parse_args()

    files = args.files or sorted(str(p) for p in Path("Levels").glob("*.txt"))
    any_fail = False
    for f in files:
        theme = args.theme
        if theme is None:
            theme = THEMES.get(Path(f).stem.split("_")[0], 0)
        tops, tun = load_level(f)
        t0 = time.monotonic()
        verdict, u, states, tape = solve(
            tops, tun, GROUP_GRAVITY[theme], GROUP_JUMP[theme], args.budget,
            args.k, strict=not args.exploits, stall_limit=args.stall
        )
        dt = time.monotonic() - t0
        row = u / 2.0 - 24  # file-relative row reached
        extra = ""
        if verdict == "COMPLETABLE":
            extra = f"tape {len(tape)} inputs ({len(tape) * args.k / 60.0:.1f}s)"
            if args.tape:
                keys = {1: "W", 0: ".", -1: "S"}
                lines = [
                    keys[INPUTS[i][0]]
                    + {0: ".", -1: "A", 1: "D"}[INPUTS[i][1]]
                    + ("J" if INPUTS[i][2] else ".")
                    for i in tape
                ]
                Path(args.tape).write_text("\n".join(lines) + "\n")
                extra += f" -> {args.tape}"
        else:
            any_fail = True
            extra = f"furthest row {row:.0f}"
        print(f"{Path(f).name:<15} theme={theme} {verdict:<16} {dt:6.1f}s {states:>8} states  {extra}")
    sys.exit(1 if any_fail else 0)


if __name__ == "__main__":
    main()
