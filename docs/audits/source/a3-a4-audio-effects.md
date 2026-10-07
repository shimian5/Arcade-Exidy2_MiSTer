# A3/A4: effect ports and the 6840 sound-effect timer (2026-10-07)

References: MAME 0.288 pin sources (`exidysound.cpp`, commit `27a8d9e8…`); captures on MAME 0.264 (package), Venture/Pepper II/Hard Hat/Mouse Trap/Teeter Torture with scripted coin/start (and right+fire for Venture). Audio-CPU write taps over `0x1800–0x3FFF` (`tools/reference_cases` Lua kept in the scratch only; stimulus converter `tools/audio_6840/gen_stimulus.py`).

## A3 — `$2000` filter port and `$3000` effect control
- `$2000` (`filter_w`): MAME only logs it. Every captured game writes a single constant (`0x24` or `0x25`, 2–19 writes per 60 s). It has no modeled sonic effect; no action.
- `$3000–$3003` (`sfxctrl_w`): used heavily (Venture 1,324 writes/60 s, mostly the three per-channel volumes at levels 7/6/0, plus the noise-clock/channel-1 mute register). The RTL decodes it (`io30_37`, `addr[1:0]`) and the module implements the register map. No action; correctness of the register semantics is part of A4.

## A4 — `berzerk_sound_fx.vhd` versus MAME's 6840 model
The selected implementation is the VHDL (`modules/6840/index.qip`); the Verilog neighbor is not built (a replay of it gave the same pitch result).

Method: the timestamped 6840/`$3000` writes from the Venture capture (3,840 writes; scripted coin/start/right/fire gameplay) are replayed through the production VHDL in GHDL (`sim/audio_6840/tb_sfx_vhdl.vhd`, module clock 14.366883 MHz / 16 as in `audio_board.v`). Output-toggle spacing is compared with MAME's rule (16-bit mode toggles every N+1 E-clocks, E = 3.579545 MHz/4, prescale ÷8 on timer 3 when CR3 bit 0 is set) using the register state implied by the same writes (`tools/audio_6840/compare_pitch.py`). A window of the capture is used (cycles ≥32 M, earlier writes applied first); the baseline VHDL needed initial values added for simulation only (`hdiv`, counters, outputs), since GHDL starts them as 'U'; on the FPGA they power up at 0.

| Measure (median measured/expected half-period) | Baseline VHDL | Fixed VHDL |
| --- | --- | --- |
| timer 1 | 3.986 | 0.997 |
| timer 2 | 3.986 | 0.997 |
| timer 3 (prescale ÷8 applied in expectation) | 0.498 | 0.997 |

- **Pitch was 4× low (two octaves).** The module divided its clock by 4, but `audio_board.v` already feeds it the 0.898 MHz `auPH0B` pulse (the 6502 PH0 rate = the 6840 E clock). Fixed with a `CLK_DIV` generic (default 4, unchanged for other users) and `#(.CLK_DIV(1))` in `audio_board.v`. The residual 0.3% (0.997) is the audio PLL (14.366883 MHz) against the nominal 14.318 MHz.
- **Timer 3 prescaler missing** (÷8 when CR3 bit 0 set; Venture uses it): added. Baseline timer 3 therefore ran 8× fast relative to MAME on top of the 4× slow clock (net 0.498).
- **Immediate load missing:** every LSB write in all five captures has CR4 clear, so MAME loads the counter at once; the baseline waited for the old period to expire (up to 65,536 counts). Added. Without it, with the clock fixed, an effect start could lag by up to ~73 ms.
- Volume: the VHDL table is already linear (0,9,…,64), unlike the Verilog neighbor's Berzerk exponential one. Its full-scale (64) is 2× an 8253 channel (32) after the filters' input scaling; MAME uses equal levels. Not changed (level calibration needs a waveform comparison).

## Not covered / limits
- This replay checks timer timing semantics, not the audible waveform. Noise generation (explosions/crash use the 128-bit LFSR, `sfxctrl` bit 0 noise-clock select) and the mixed output level versus MAME's WAV were not compared.
- Simulation is of the VHDL entity alone with the real captured writes; whole-board audio-CPU execution was not simulated.
- Not built in Quartus: generic override of a VHDL entity from Verilog, `integer` `hdiv` and the new prescale/load logic need the full-flow compile.
- MAME captures used 0.264 (package) rather than the pinned 0.288.

## Replay
```
python3 tools/audio_6840/gen_stimulus.py <capture.csv> stim.txt          # capture: time_s,addr,data
ghdl -a --std=08 -fsynopsys -frelaxed modules/6840/berzerk_sound_fx.vhd sim/audio_6840/tb_sfx_vhdl.vhd
ghdl --elab-run --std=08 -fsynopsys -frelaxed tb_sfx_vhdl -gSTIM=stim.txt -gOUTF=toggles.txt -gCYCLES=<n> -gCLK_DIV=1
python3 tools/audio_6840/compare_pitch.py stim.txt toggles.txt
```
