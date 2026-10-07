#!/usr/bin/env python3
"""Compare RTL 6840 output toggle spacing with MAME's formula half-period=(N+1)/E, E=3.579545MHz/4,
for internally clocked 16-bit channels, using the register state implied by the MAME write log.
Usage: compare_pitch.py STIM TOGGLES [module_period_s]"""
import sys, statistics, collections
E = 3.579545e6 / 4
def main(stim, tog, period=16 / 14.366883e6):
    # timeline of config changes per channel (cycle, N, internal_clock, running)
    cr = [1, 0, 0]; msb = 0; N = [0, 0, 0]
    ev = []
    for line in open(stim):
        c, k, r, d = map(int, line.split())
        if k: continue
        if r == 0:
            if cr[1] & 1: cr[0] = d
            else: cr[2] = d
        elif r == 1: cr[1] = d
        elif r in (2, 4, 6): msb = d
        else: N[(r - 3) // 2] = (msb << 8) | d
        ev.append((c, tuple(cr), tuple(N)))
    idx = 0; cur = ((1, 0, 0), (0, 0, 0)); last = [None] * 3; lastcfg = [None] * 3
    ratios = collections.defaultdict(list)
    for line in open(tog):
        c, m = map(int, line.split())
        while idx < len(ev) and ev[idx][0] <= c: cur = (ev[idx][1], ev[idx][2]); idx += 1
        for ch in range(3):
            if m >> ch & 1:
                cfg = (cur[0][ch], cur[1][ch])
                running = not (cur[0][0] & 1)            # CR1 bit 0 = reset all timers
                prescale = 8 if (ch == 2 and cfg[0] & 1) else 1   # CR3 bit 0 = divide by 8
                if last[ch] is not None and lastcfg[ch] == cfg and (cfg[0] & 0x02) and running:
                    meas = (c - last[ch]) * period
                    exp = (cfg[1] + 1) * prescale / E
                    if cfg[1] >= 4: ratios[ch].append(meas / exp)
                last[ch] = c; lastcfg[ch] = cfg
    for ch in range(3):
        v = ratios[ch]
        if v: print(f"channel {ch+1}: {len(v)} half-periods; measured/expected median {statistics.median(v):.3f} (min {min(v):.3f}, max {max(v):.3f})")
        else: print(f"channel {ch+1}: no comparable internally clocked half-periods")
if __name__ == '__main__': main(*sys.argv[1:3], *(float(x) for x in sys.argv[3:4]))
