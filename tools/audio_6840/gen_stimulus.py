#!/usr/bin/env python3
"""Convert a MAME audio-CPU effect-port capture (time_s,addr,data) into RTL stimulus lines
'cycle kind reg data' for berzerk_sound_fx; kind 0 = 6840 (cs), 1 = sfxctrl (vs).
cycle = write time in periods of the module clock (default 3.579545 MHz / 4 = 0.894886 MHz is the
6502 PH0 rate; the RTL feeds the module with the 14.366883 MHz / 16 pulse)."""
import csv, sys
def main(src, dst, period):
    out = []
    for r in csv.DictReader(open(src)):
        a = int(r['addr'], 16); d = int(r['data'], 16); t = float(r['time_s'])
        c = round(t / period)
        if 0x2800 <= a <= 0x2fff: out.append(f"{c} 0 {a & 7} {d}")
        elif 0x3000 <= a <= 0x37ff: out.append(f"{c} 1 {a & 3} {d}")
    open(dst, 'w').write("\n".join(out) + "\n")
    print(len(out), "stimulus lines; last cycle", out[-1].split()[0])
if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 16 / 14.366883e6)
