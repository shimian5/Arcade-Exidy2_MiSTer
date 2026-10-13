# Production RGB generate-scope correction — 2026-10-12

The original `sys/video_mixer.sv` declared R_in/G_in/B_in inside generate branches, then referenced those names from outside those scopes. The actual-source Verilator fixture failed its independent RGB FIFO oracle; the old fixture needed an ignored compatibility copy to obtain colors. The production correction declares the nets once at module scope and drives them with the same branch expressions. No gamma/blank/freeze timing logic changes.

The actual corrected source passes every one of 65,536 active pixels for each of eight coordinate bitplanes: 524,288 pixel comparisons, all 256 rows and both edge columns. Input/line errors are zero, with a constant 18-master-clock pipeline latency. The original-scope source is rejected by the same oracle, and a wrong expected RGB negative control is also rejected. Results are ignored under `simulation/video_scope/production/`; the preserved original file is under `simulation/video_scope/video_mixer_original.sv`.

Replay with `tools/video_scope/measure.py` under the pinned WSL Verilator 5.052 environment. The existing compatibility helper now recognizes the fixed production declaration block and compiles it directly instead of silently rewriting it. Original reports remain historical evidence for their recorded source hashes.

Full production Quartus flow and targeted STA are pending. This synthetic source-raster/mixer fixture uses gamma bypass and FX0, with the unconnected HDMI_FREEZE child input tied low for deterministic testing. It does not qualify gamma table writes, effects, OSD, the full game renderer, CRT transport or physical video output. The correction is a separate reviewable commit before the CRT converter is integrated.
