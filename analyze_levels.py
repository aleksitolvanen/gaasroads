#!/usr/bin/env python3
"""Track texture analyzer: quantifies how "eventful" a level is, row by row.

Used to tune the generator against the extracted SkyRoads roads
(tests/skyroads/road_*.txt). The headline metric is the "dull run":
consecutive rows that are wide (widest strip >= 5), unfragmented, flat,
tunnel-free and identical in footprint to the previous row. Long dull runs
are the boring wide-platform stretches; SkyRoads keeps them short.

Usage:
  python analyze_levels.py Levels/*.txt
  python analyze_levels.py tests/skyroads/road_*.txt --summary
"""

import argparse
import glob
import statistics
import sys

W = 10


def parse(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            line = line.ljust(2 * W)
            row = []
            for i in range(W):
                cell = line[2 * i : 2 * i + 2]
                h = int(cell[0]) if cell[0].isdigit() else 0
                row.append((h, cell[1] == "T"))
            rows.append(row)
    return rows


def strips(row):
    """Contiguous runs of solid tiles: list of (start, width, heights)."""
    out = []
    i = 0
    while i < W:
        if row[i][0] > 0:
            j = i
            while j < W and row[j][0] > 0:
                j += 1
            out.append((i, j - i, [row[k][0] for k in range(i, j)]))
            i = j
        else:
            i += 1
    return out


def analyze(rows):
    n = len(rows)
    gap_rows = 0
    frag_rows = 0
    tun_rows = 0
    widths = []
    events = 0
    dull_runs = []
    cur_dull = 0
    prev_sig = None
    for row in rows:
        st = strips(row)
        tun = any(t for h, t in row)
        if tun:
            tun_rows += 1
        if not st:
            gap_rows += 1
            events += 1
            if cur_dull:
                dull_runs.append(cur_dull)
            cur_dull = 0
            prev_sig = None
            continue
        wmax = max(s[1] for s in st)
        widths.append(wmax)
        if len(st) > 1:
            frag_rows += 1
        # row signature: footprint + heights
        sig = tuple((s[0], s[1], tuple(s[2])) for s in st)
        flat = all(len(set(s[2])) == 1 for s in st)
        eventful = len(st) > 1 or tun or not flat or sig != prev_sig
        if eventful:
            events += 1
        dull = wmax >= 5 and len(st) == 1 and flat and not tun and sig == prev_sig
        if dull:
            cur_dull += 1
        else:
            if cur_dull:
                dull_runs.append(cur_dull)
            cur_dull = 0
        prev_sig = sig
    if cur_dull:
        dull_runs.append(cur_dull)
    dull_rows_8 = sum(r for r in dull_runs if r >= 8)
    return {
        "rows": n,
        "dull_max": max(dull_runs) if dull_runs else 0,
        "dull8_pct": 100.0 * dull_rows_8 / n if n else 0.0,
        "gap_pct": 100.0 * gap_rows / n if n else 0.0,
        "frag_pct": 100.0 * frag_rows / n if n else 0.0,
        "tun_pct": 100.0 * tun_rows / n if n else 0.0,
        "w_avg": statistics.mean(widths) if widths else 0.0,
        "ev_per_row": events / n if n else 0.0,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--summary", action="store_true", help="add an aggregate line")
    args = ap.parse_args()
    files = []
    for pat in args.files:
        files.extend(glob.glob(pat) or [pat])
    hdr = f"{'file':<34}{'rows':>5} {'dullmax':>7} {'dull8%':>6} {'gap%':>5} {'frag%':>6} {'tun%':>5} {'w_avg':>6} {'ev/row':>7}"
    print(hdr)
    agg = []
    for path in files:
        try:
            rows = parse(path)
        except (OSError, ValueError) as e:
            print(f"{path}: {e}", file=sys.stderr)
            continue
        m = analyze(rows)
        agg.append(m)
        name = path.replace("\\", "/").split("/")[-1]
        print(
            f"{name:<34}{m['rows']:>5} {m['dull_max']:>7} {m['dull8_pct']:>6.1f} "
            f"{m['gap_pct']:>5.1f} {m['frag_pct']:>6.1f} {m['tun_pct']:>5.1f} "
            f"{m['w_avg']:>6.2f} {m['ev_per_row']:>7.2f}"
        )
    if args.summary and agg:
        print(
            f"{'== mean ==':<34}{statistics.mean(m['rows'] for m in agg):>5.0f} "
            f"{statistics.mean(m['dull_max'] for m in agg):>7.1f} "
            f"{statistics.mean(m['dull8_pct'] for m in agg):>6.1f} "
            f"{statistics.mean(m['gap_pct'] for m in agg):>5.1f} "
            f"{statistics.mean(m['frag_pct'] for m in agg):>6.1f} "
            f"{statistics.mean(m['tun_pct'] for m in agg):>5.1f} "
            f"{statistics.mean(m['w_avg'] for m in agg):>6.2f} "
            f"{statistics.mean(m['ev_per_row'] for m in agg):>7.2f}"
        )


if __name__ == "__main__":
    main()
