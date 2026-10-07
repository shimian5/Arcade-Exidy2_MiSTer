# Handoff for the next (local) agent — 2026-10-07

Work is now on `main`, including production tree `55e3300`. Latest local results and timing work are in [STOPPING_POINT.md](STOPPING_POINT.md). Read in this order: this file, [STOPPING_POINT.md](STOPPING_POINT.md), [WORKPLAN.md](WORKPLAN.md), [docs/cloud-environment.md](docs/cloud-environment.md). Goal and completion rule are in WORKPLAN.md (every Exidy 6502 game working; evidence required, no unproven "done").

## Standing owner rules
- Commits authored as **shimian5 <matt.alias@mattbaran.com>**; no attribution trailers; no assistant/vendor credits in commits, comments or docs. Set `git config user.name/user.email` before committing.
- Never commit ROM bytes, assembled ROM images, captures, WAVs or test output. Generated data lives under the ignored `simulation/` or a scratch dir. Treat the NAS ROM library as read-only.
- Do not open a PR unless asked. Quartus: full flow from an **unsandboxed PowerShell** (`quartus_sh --flow compile Arcade-Exidy2`), never isolated stages for acceptance. On 2026-10-07 the owner authorized the local orchestrator to run Quartus directly; the earlier owner-only execution restriction is superseded.
- Tests: new tests are committed as source; their output is not printed or committed (`tools/run_tests.py` is quiet by design).
- Keep docs in step with every result; update STOPPING_POINT.md and the WORKPLAN log/table/issue register. Check a WORKPLAN box only at DONE.

## What exists now (all after baseline `911d923`)
Production RTL edits, each unbuilt-together and unproven on hardware. Revert any single one by reverting its commit.

| # | Change | Commit(s) | Files |
| - | --- | --- | --- |
| 1 | Mono mix of both audio groups (A1) | `76c5760` | `rtl/audio_mix.v`, `rtl/audio_board.v`, `rtl/index.qip` |
| 2 | Profile-selected collision wiring for `$5103`, selected by `pcb[7:6]` (profile 0 = unchanged baseline) | `f8c32b8`, candidates `f4a6375` | `rtl/int_cause.v`, `rtl/Exidy2.v`, `tools/sprite_fixture/run_fixture.py`, `candidates/mra/*` |
| 3 | Audio RAM as the 128-byte 6532 mirror (A2; fixes Mouse Trap polling `0x0178`) | `62af0ba` | `rtl/audio_ram_map.v`, `rtl/audio_board.v` |
| 4 | 6840: real E clock (`CLK_DIV` generic, 1 in `audio_board.v`), immediate load, timer-3 ÷8 prescale (A4) | `afe83a0` | `modules/6840/berzerk_sound_fx.vhd`, `rtl/audio_board.v` |
| 5 | Timing: false paths for the PIA 9B↔8B handshake, static profile byte `mod_other[*]`, and the synchronizer's first flop; audio-clock reset synchronizer | `a768479`, `c4e70ba`, `70fb5df` | `Arcade-Exidy2.sdc`, `rtl/reset_sync.v`, `rtl/audio_board.v` |

Release MRAs and RBFs under `releases/` are untouched. Candidate MRAs enabling profile 1/2 are in `candidates/mra` (Venture index-1 byte `0x50`, Pepper II/Hard Hat `0xB0`; Teeter Torture would be `0xD0`; Mouse Trap stays `0x10`).

Isolated expansion adapter (CVSD/FAX loading, W02): increments 1-15 in `docs/design/expansion-adapter/`; not wired into the core.

## First actions (local)
1. `git pull`; run `python tools/run_tests.py` (needs Verilator 5.052; on this Windows setup use WSL as the older scripts do). Expect all PASS.
2. Full-core Quartus build of the branch head. The last owner timing report (before commit `70fb5df`) had the master clock met and the audio clock about −0.3 ns, all from `mod_other[4]`; the false path for it is not yet built. Compare against a baseline build (`git worktree add ..\baseline bfd1b5c`) if any failure remains, and read the failing path *source and destination* before changing anything: every failure so far was a baseline clock-domain crossing, not the new logic (see `docs/audits/source/audio-handshake-timing.md`). Next suspects: `pause` into the audio CPU `rdy` and the mono mute.
3. If timing closes: test on hardware with the owner — audio (effects should be two octaves higher than before; both ears; Mouse Trap audio), then baseline MRAs versus `candidates/mra` for Venture, Pepper II and Hard Hat.
4. Rerun `tools/sprite_fixture/run_fixture.py` under WSL (edited to pin profile 0; the pinned MAME `exidy.cpp` copy goes in `simulation/reference_sources/`, its SHA-256 is checked).

## Open work, rough priority
- **Verify what was built**: items 1-5 above on hardware/against MAME WAVs. A4's noise generator and output level, 8253 clocks (A5), Targ/Spectar discrete audio (A7) are unverified.
- **I05 Venture arrow**: not reproduced. S1 (sprite-1 enable gating, `$5101` bits 7/4) is *not* supported as the cause in the startup-to-maze capture; a MAME route into a room (poll game RAM) or the forum author's exact input sequence is needed, then compare against the core.
- **I07 Mouse Trap voices**: the voice ROM loading/transport is designed and verified in isolation; no Z80/CVSD (MC3417) core exists (W09). The Mouse Trap audio-CPU RAM aliasing (A2) is fixed but is not the voice fix.
- **W10-W12**: Side Trak, Teeter Torture (spinner choice owed by owner), FAX/FAX 2 (extra `fxl-12b` PROM, banks 24-31, answer-button mapping owed), clone/bootleg profiles. Existing ROM availability is not support.
- **Expansion adapter integration**: bind actual clocks/CPU/audio, PLL-lock-derived reset, whole-core fit.
- **W06-W07 CRT/native video, W13-W16**: see WORKPLAN; not started beyond designs/fixtures.
- Interrupt-latch residuals: S5 (language/table DIP bits for Targ/Spectar/Side Trak), S6 (glitch review of the async clear on `rCPU_IRQ`), room/stage transitions.
- Owner inputs still owed: Teeter Torture control device, FAX button mapping, CRT model/adapter/settings, which RBF/MRA runs on hardware.

## Gotchas learned
- Verilator 5.020 (Debian) gives false failures (`$finish` inside tasks); use 5.052.
- GHDL needs `--std=08 -fsynopsys -frelaxed`; the 6840 VHDL leaves registers uninitialized, so GHDL runs need initial values added for simulation only (FPGA power-up is 0).
- `modules/6840/index.qip` selects the **VHDL** 6840; the neighboring `.v` is not built.
- `Exidy2.v` is Verilog-2001 (`.do` is a port name); lint with `--language 1364-2005`.
- `pcb` is the MRA index-1 byte: bits [1:0] palette/profile, [4] CPU-board audio, [5] char layout, [7:6] new interrupt profile. Mouse Trap and Venture share `0x10` but need different collision wiring in MAME (14/00 vs 04/04) — that is why `[7:6]` exists.
- Quartus probe projects must be compiled from inside their generated directory.
- MAME captures in the repo's evidence used 0.264 where noted; the pin is 0.288 (local `C:\MiSTerDev\mame`).
- Zero-input attract rarely exercises gameplay paths; scripted input (see `tools/reference_cases/venture_startup.lua`) is needed.

## Environment locally (from WORKPLAN)
Core `C:\MiSTerDev\Arcade-Exidy2_MiSTer`; MAME `C:\MiSTerDev\mame\mame.exe`, ROM destination `C:\MiSTerDev\mame\roms`; NAS ROMs `\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)`; Quartus 17.0.2 at `C:\MiSTerDev\intelFPGA_lite\17.0\quartus\bin64`; Victory CRT reference `C:\MiSTerDev\Arcade-Victory_MiSTer`; WSL distro `archlinux` (Verilator 5.052). Forum: https://misterfpga.org/viewtopic.php?t=7747. The WORKPLAN's Sol/Luna model-assignment convention applies if that tooling is available locally; the cloud session did not use it.
