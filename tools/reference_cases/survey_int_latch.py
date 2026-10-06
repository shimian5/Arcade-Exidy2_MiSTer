#!/usr/bin/env python3
"""Summarize $5101 writes and $5103 reads from exidy_reference.lua bus.csv captures.
Usage: survey_int_latch.py RUN_DIR [RUN_DIR ...]  (set name = directory name)."""
import csv, collections, sys
from pathlib import Path
def survey(run):
    w, r = collections.Counter(), collections.Counter()
    for row in csv.DictReader(open(Path(run) / 'bus.csv')):
        a, d = row['address'], int(row['data'], 16)
        if row['kind'] == 'W' and a == '5101': w[d] += 1
        if row['kind'] == 'R' and a == '5103': r[d] += 1
    gated = sum(v for k, v in w.items() if (k & 0x80) and not (k & 0x10))
    return dict(set=Path(run).name, w5101=sum(w.values()), distinct5101={f'{k:02x}': v for k, v in sorted(w.items())},
                sprite1_gated_writes=gated, r5103=sum(r.values()), values5103={f'{k:02x}': v for k, v in sorted(r.items())})
if __name__ == '__main__':
    for run in sys.argv[1:]: print(survey(run))
