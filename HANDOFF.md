# Handoff for the next (local) agent — 2026-10-07

Work is now on `main`, including production tree `55e3300`. Latest local results and timing work are in [STOPPING_POINT.md](STOPPING_POINT.md). Read in this order: this file, [STOPPING_POINT.md](STOPPING_POINT.md), [WORKPLAN.md](WORKPLAN.md), [docs/cloud-environment.md](docs/cloud-environment.md). Goal and completion rule are in WORKPLAN.md (every Exidy 6502 game working; evidence required, no unproven "done").

## Standing owner rules
- Commits authored as **shimian5 <matt.alias@mattbaran.com>**; no attribution trailers; no assistant/vendor credits in commits, comments or docs. Set `git config user.name/user.email` before committing.
- Never commit ROM bytes, assembled ROM images, captures, WAVs or test output. Generated data lives under the ignored `simulation/` or a scratch dir. Treat the NAS ROM library as read-only.
- Do not open a PR unless asked. Quartus: full flow from an **unsandboxed PowerShell** (`quartus_sh --flow compile Arcade-Exidy2`), never isolated stages for acceptance. On 2026-10-07 the owner authorized the local orchestrator to run Quartus directly; the earlier owner-only execution restriction is superseded.
- Tests: new tests are committed as source; their output is not printed or committed (`tools/run_tests.py` is quiet by design).
- Keep docs in step with every result; update STOPPING_POINT.md and the WORKPLAN log/table/issue register. Check a WORKPLAN box only at DONE.

## What exists now (all after baseline `911d923`)
Latest completed production flow is `07a49c5`: compilation succeeds, master setup remains -0.439 ns; audio and all five added counter clocks pass reported setup/hold. Valid-mask read timing and reset recovery/removal pass. The isolated bit-5 placement full flow completed: assignments were honored, worst byte setup improved to -0.330 ns and byte hold passes at +0.528 ns, but all eight bits still fail setup. The tighter setup-target flow completed but its original-SDC replay is worse (-0.431 ns, byte hold +0.565 ns); reject that fit and its constraint. The next opposite-edge proposal requires functional verification before a fit. Production inputs and releases are unchanged. Read [latest build evidence](docs/audits/source/pia-data-valid-build-2026-10-07.md), [placement experiment](docs/audits/source/pia-placement-trial.md), [steering trial](docs/audits/source/pia-setup-steering-trial.md) and [data/valid contract](docs/audits/source/pia-data-valid-candidate.md). Whole-design clock coverage and hardware remain open. Revert individual edits using the table; successful compilation is not signoff.

The seven apparent Venture response mismatches were analyzer artifacts: per-CPU MAME timestamps regress across callbacks, so sorting them reordered causality. Callback-row analysis yields 5,790 matching Venture responses and zero mismatches; the other three captured games also have zero. Earlier cross-CPU latency bounds are withdrawn. This resolves those seven cases, not the independent RTL coherence or hardware acceptance gates. See [corrected analysis](docs/audits/source/pia-response-mismatch-review.md).

| # | Change | Commit(s) | Files |
| - | --- | --- | --- |
| 1 | Mono mix of both audio groups (A1) | `76c5760` | `rtl/audio_mix.v`, `rtl/audio_board.v`, `rtl/index.qip` |
| 2 | Profile-selected collision wiring for `$5103`, selected by `pcb[7:6]` (profile 0 = unchanged baseline) | `f8c32b8`, candidates `f4a6375` | `rtl/int_cause.v`, `rtl/Exidy2.v`, `tools/sprite_fixture/run_fixture.py`, `candidates/mra/*` |
| 3 | Audio RAM as the 128-byte 6532 mirror (A2; fixes Mouse Trap polling `0x0178`) | `62af0ba` | `rtl/audio_ram_map.v`, `rtl/audio_board.v` |
| 4 | 6840: real E clock (`CLK_DIV` generic, 1 in `audio_board.v`), immediate load, timer-3 ÷8 prescale (A4) | `afe83a0` | `modules/6840/berzerk_sound_fx.vhd`, `rtl/audio_board.v` |
| 5 | Timing: false paths for the PIA 9B↔8B handshake, static profile byte `mod_other[*]`, and the synchronizer's first flop; audio-clock reset synchronizer | `a768479`, `c4e70ba`, `70fb5df` | `Arcade-Exidy2.sdc`, `rtl/reset_sync.v`, `rtl/audio_board.v` |
| 6 | Audio-domain pause sampling for CPU ready and mixer mute | `30dbc10`, attribute quoting `594b8dd` | `rtl/pause_sync.v`, `rtl/audio_board.v`, `rtl/index.qip` |
| 7 | Derive actual fixed PLL clocks and uncertainty; remove stale clock overrides | `07a1f21` | `Arcade-Exidy2.sdc` |
| 8 | Whole-byte PIA reply staging; completed flow still fails on source DDR masking | `3341f08` | `rtl/pia_return.v`, `rtl/audio_board.v`, `rtl/index.qip` |
| 9 | First-stage-only pause exception and forced synchronizer identification; built, audio setup passes | `81f85e2` | `Arcade-Exidy2.sdc`, `rtl/pause_sync.v` |
| 10 | Audio source byte register before the master PIA return stage; adds about 92 ns total; paired tests pass, completed fit still fails master setup | `2fafa6b` | `rtl/pia_return.v`, `rtl/audio_board.v` |
| 11 | Destination return reset matches asynchronous PIA9 reset; paired tests pass, built but byte setup still fails | `9198c76` | `rtl/pia_return.v` |
| 12 | Five verified generated divider clocks; complete fit passes their reported setup/hold, no new exception | `444211d` | `Arcade-Exidy2.sdc` |
| 13 | Normal PIA byte data register with asynchronously reset output-valid mask; seven-phase paired tests pass; built, byte setup still -0.439 ns | `07a49c5` | `rtl/pia_return.v` |

Release MRAs and RBFs under `releases/` are untouched. Candidate MRAs enabling profile 1/2 are in `candidates/mra` (Venture index-1 byte `0x50`, Pepper II/Hard Hat `0xB0`; Teeter loader candidate uses `0xD0` but controls/NMI are not integrated; Mouse Trap stays `0x10`).

Isolated expansion adapter (CVSD/FAX loading, W02): increments 1-15 in `docs/design/expansion-adapter/`; not wired into the core.

## First actions (local)
1. Read the completed `07a49c5` reports and snapshot. Data/valid reset tests and mask/reset timing pass, but every byte bit still fails setup. Review exact routing/clock skew and a bounded physical packing/placement experiment before changing latency or protocol; keep the reply chain timed. The prepared Teeter patch remains unapplied. The corrected coverage diagnostic successfully reports actual no-clock endpoints and resolved group membership; event-path coverage remains open.
2. Fresh local MAME RAM replay is complete: 11 PASS, 0 FAIL, 0 SKIP ([evidence](docs/audits/source/local-audio-ram-replay.md)). Local guarded GHDL 6840 pitch replay is also complete; remaining waveform/noise/level references are open. Portable tools need literal paths; absence from PATH does not mean unavailable.
3. After a repair, run a complete unsandboxed PowerShell Quartus flow. Generated clocks, programmable resets and existing PIA exceptions still require coverage review.
4. When a timing-accepted candidate is ready, follow [hardware checklist](docs/audits/hardware/audio-irq-candidate-checklist.md) with HDMI and Direct Video/S-Video. Sprite fragment replay already passes; Venture arrow remains unresolved.

## Open work, rough priority
- **Verify what was built**: items 1-5 above on hardware/against MAME WAVs. A4's noise generator and output level, 8253 clocks (A5), Targ/Spectar discrete audio (A7) are unverified.
- **I05 Venture arrow**: not reproduced. S1 (sprite-1 enable gating, `$5101` bits 7/4) is *not* supported as the cause in the startup-to-maze capture; a MAME route into a room (poll game RAM) or the forum author's exact input sequence is needed, then compare against the core.
- **I07 Mouse Trap voices**: the voice ROM loading/transport is designed and verified in isolation; local Z80 source exists, but speech CPU/CVSD (MC3417) integration remains absent (W09). See [reuse audit](docs/design/mousetrap-speech-reuse.md). The Mouse Trap audio-CPU RAM aliasing (A2) is fixed but is not the voice fix.
- **W10-W12**: Side Trak, Teeter Torture (spinner plus joystick/D-pad mapping required, using local Super Off Road/VCO reference), FAX/FAX 2 (question-bank integration, banks 24-31 policy, four answer buttons per player required in MRA), clone/bootleg profiles. Pinned MAME loads `fxl-12b` but does not consume it; a PROM decode requires independent hardware evidence. Existing ROM availability is not support.
- **Expansion adapter integration**: bind actual clocks/CPU/audio, PLL-lock-derived reset, whole-core fit.
- **W06-W07 CRT/native video, W13-W16**: see WORKPLAN; not started beyond designs/fixtures.
- Interrupt-latch residuals: S5 (language/table DIP bits for Targ/Spectar/Side Trak), S6 (glitch review of the async clear on `rCPU_IRQ`), room/stage transitions.
- Owner supplied HDMI and Direct Video → S-Video → 15 kHz JVC display, Teeter spinner plus joystick/D-pad, and FAX four answer buttons per player. Still record exact display/adapter/settings, running RBF/MRA and hardware sensitivity/layout results.

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
