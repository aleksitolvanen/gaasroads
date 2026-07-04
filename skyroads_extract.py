#!/usr/bin/env python3
"""Extract SkyRoads (1993) roads from ROADS.LZS into GaasRoads track files.

For local analysis and inspiration only - do not ship converted originals.
Format documented by the community:
  https://moddingwiki.shikadi.net/wiki/SkyRoads_level_format
  https://moddingwiki.shikadi.net/wiki/SkyRoads_compression

Usage:
  python skyroads_extract.py [path\\to\\ROADS.LZS] [out_dir]

Tile mapping (7 SkyRoads columns centered on our columns 2-8):
  road -> height 1, half-height block -> 2, full-height block -> 3,
  tunnel -> T at road height, burning tiles -> gap (they kill on touch).
"""
import struct
import sys
from pathlib import Path

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else r"D:\Games\freegames\skyroads\ROADS.LZS")
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else "tests/skyroads")


class Bits:
    def __init__(self, data):
        self.data = data
        self.pos = 0

    def read(self, n):
        v = 0
        for _ in range(n):
            byte = self.data[self.pos >> 3]
            bit = (byte >> (7 - (self.pos & 7))) & 1
            v = (v << 1) | bit
            self.pos += 1
        return v


def decompress(data, out_len):
    w1, w2, w3 = data[0], data[1], data[2]
    bits = Bits(data[3:])
    out = bytearray()
    while len(out) < out_len:
        if bits.read(1) == 0:                      # short reference
            dist = bits.read(w2) + 2
            cnt = bits.read(w1) + 2
        elif bits.read(1) == 0:                    # long reference
            dist = bits.read(w3) + (1 << w2) + 2
            cnt = bits.read(w1) + 2
        else:                                      # literal
            out.append(bits.read(8))
            continue
        for _ in range(cnt):
            out.append(out[-dist])
    return bytes(out[:out_len])


def convert(tiles, rows):
    # Tile bits: 0-3 floor colour (0 = none), 4-7 top block colour,
    # 8 tunnel, 9 half-height block, 10 full-height block.
    # Heights: floor -> 1, half block -> 2, full block -> 3, tunnel -> 1T.
    # Burning floor (colour 12) kills on touch -> gap.
    lines = []
    for r in range(rows):
        cells = [".."] * 10
        for c in range(7):
            v = tiles[r * 7 + c]
            if v == 0:
                continue
            tunnel = v & 0x100
            half = v & 0x200
            full = v & 0x400
            floor_col = v & 0x0F
            if tunnel:
                tile = "1T"
            elif full:
                tile = "3."
            elif half:
                tile = "2."
            elif floor_col == 12:
                tile = ".."
            elif floor_col:
                tile = "1."
            else:
                tile = ".."
            cells[c + 2] = tile
        lines.append("".join(cells))
    return lines


def main():
    raw = SRC.read_bytes()
    first_off = struct.unpack_from("<H", raw, 0)[0]
    entries = []
    pos = 0
    while pos < first_off:
        off, length = struct.unpack_from("<HH", raw, pos)
        entries.append((off, length))
        pos += 4
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"{len(entries)} roads in {SRC}")
    for i, (off, length) in enumerate(entries):
        gravity, fuel, oxygen = struct.unpack_from("<HHH", raw, off)
        comp = raw[off + 222: entries[i + 1][0] if i + 1 < len(entries) else len(raw)]
        road = decompress(comp, length)
        rows = length // 14
        tiles = struct.unpack_from(f"<{rows * 7}H", road, 0)
        lines = convert(tiles, rows)
        solid = sum(1 for ln in lines if ln != ".." * 10)
        tun = sum(ln.count("T") for ln in lines)
        blocks = sum(ln.count("2.") + ln.count("3.") for ln in lines)
        name = "road_00_demo" if i == 0 else f"road_{i:02d}"
        (OUT / f"{name}.txt").write_text("\n".join(lines))
        print(f"  {name}: {rows} rows, gravity={gravity} fuel={fuel} oxygen={oxygen}, "
              f"{solid} solid rows, {blocks} blocks, {tun} tunnel tiles")


if __name__ == "__main__":
    main()
