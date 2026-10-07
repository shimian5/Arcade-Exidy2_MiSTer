# Cloud/Linux simulation environment and reproduction

How the 2026-10-06/07 cloud work was run, so it can be repeated. ROM bytes and captures are never committed; everything below that touches ROMs uses ignored `simulation/` paths or a scratch directory.

## Tools and versions
| Tool | Version used | Notes |
| --- | --- | --- |
| Verilator | 5.052 (built from tag `v5.052`) | Use 5.052. The Debian 5.020 package mishandles `$finish` inside tasks, so connected cases 25 and 26 print PASS and then fail a trailing assertion. Build: `git clone --depth 1 --branch v5.052 https://github.com/verilator/verilator`, `autoconf && ./configure --prefix=$HOME/vl5052 && make -j && make install`, then set `VERILATOR_ROOT=$HOME/vl5052/share/verilator` and put `$HOME/vl5052/bin` on `PATH`. |
| GHDL | 4.1 (mcode) | Needs `--std=08 -fsynopsys -frelaxed` (the 6840 VHDL uses `std_logic_unsigned`). Slow: roughly 20 M cycles in 5-10 minutes. |
| MAME | 0.264 (Ubuntu package) | Pinned reference is 0.288 (commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`); the Exidy driver sources fetched from that commit match the recorded hash. Captures made with 0.264 are labelled as such. Headless: `mame <set> -rompath <dir> -video none -sound none -nothrottle -autoboot_script <lua>` with `XDG_RUNTIME_DIR=/tmp`. |
| Main_MiSTer | shallow clone of upstream | Needed by `tools/expansion_adapter/connected.py` at `../Main_MiSTer`. `fpga_io.cpp`, `spi.h`, `spi.cpp` match the pinned hashes; `user_io.cpp` differs (upstream is newer; the script's string assertions still hold). |
| Quartus | 17.0.2 Lite (owner's Windows machine only) | Not run in the cloud (see below). |

## ROM staging (owner-supplied zips)
Copy each set's MAME zip into one directory named `<set>.zip` (e.g. `mtrap.zip`). Verify with `mame -rompath <dir> -verifyroms <set>`. For the connected ROM cases: `python3 tools/expansion_adapter/prepare_roms.py --rom-dir <dir> --report <scratch>.json` writes `simulation/expansion_adapter/rom-images/{mtrap,fax,fax2}.hex` and the hashes must equal `docs/design/expansion-adapter/increment-07-roms.json`.

## Captures
- Bus/frame references: `tools/reference_cases/exidy_reference.lua` (`-autoboot_script`, run from an empty directory; 3,600 frames); Venture startup/gameplay: `tools/reference_cases/venture_startup.lua` with `attract-input.flag` containing `coin-start-right-fire` or `coin-start-right-only`.
- Interrupt-latch survey over those captures: `python3 tools/reference_cases/survey_int_latch.py <run dir>...` (results in `docs/reference_cases/int-latch-survey.json`).
- Audio-CPU RAM-window trace: `tools/reference_cases/audio_ram_seq.lua` with `AUD_OUT=<csv>` and optional `AUD_FRAMES` (900 used).
- 6840/effect-port write capture: `tools/audio_6840/mame_sfx_capture.lua` (`SFX_OUT`, `SFX_FRAMES`, `SFX_INPUT=1`, `SFX_START`), then `tools/audio_6840/gen_stimulus.py`, the GHDL bench `sim/audio_6840/tb_sfx_vhdl.vhd` and `tools/audio_6840/compare_pitch.py` (commands in `docs/audits/source/a3-a4-audio-effects.md`).

## Tests
`python3 tools/run_tests.py [--traces DIR]` prints one PASS/FAIL/SKIP line per test and writes logs to `simulation/test-logs` only. Tests (all passed on 2026-10-07 with Verilator 5.052): mono mix unit test and a baseline-style mutant that must fail; interrupt cause profiles against MAME's formula and observed `$5103` values; audio reset synchronizer; reset release (module, bridge, two negative controls); the connected expansion suite (29 cases with ROM images, 26 without); audio-RAM mirror replay on Venture, Pepper II and Mouse Trap traces plus the flat map that must fail on Mouse Trap (needs `--traces` with `seq_<game>.csv`). The GHDL 6840 pitch replay is run manually. Older fixtures (`tools/sprite_fixture`, `tools/raster`, `tools/video_*`) are WSL/PowerShell-based and were not run in the cloud.

## Quartus
- The expansion probe (`python3 tools/expansion_adapter/fit_probe.py --reset-sync`) must be compiled from inside the generated directory (`simulation/expansion_adapter/fit14`) so Quartus finds `expansion_probe.qpf`: `quartus_sh --flow compile expansion_probe`. Synchronizer report: `quartus_sta -t ..\..\..\tools\expansion_adapter\report_synchronizers.tcl`.
- Full core: `quartus_sh --flow compile Arcade-Exidy2`. Timing history and the constraints added for baseline clock-domain crossings are in `docs/audits/source/audio-handshake-timing.md`.
- Running `theypsilon/quartus-lite-c5:17.0.2` in the cloud container was tried and dropped: a daemon started, Docker Hub rate-limited the pull, and the image (about 3 GB compressed) was reachable through a Google mirror, but the owner builds locally.

## Repository conventions used
Commits are authored as shimian5 <matt.alias@mattbaran.com> with no attribution trailers. ROM zips, derived images, captures and logs stay outside git (`simulation/` is ignored).
