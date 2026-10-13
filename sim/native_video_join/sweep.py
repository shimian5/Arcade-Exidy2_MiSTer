#!/usr/bin/env python3
"""Run independent native/output clock phases, each with eight complete bitplane images."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
for phase in (0,333,1000,1750):
 subprocess.run([sys.executable,str(ROOT/'sim/native_video_join/run.py'),'--clock-phase-ps',str(phase),'--run-dir',str(ROOT/f'simulation/native_video_join/phase-{phase}')],check=True)
