# A5: observed Venture 8253 mode 0/3 output characterization

Date: 2026-10-07. The fixture instantiates the selected `modules/k580vi53/k580vi53.v` unchanged. It measures only the external `out[]` pins while writing actual Venture 8253 control-word forms. This is a source-derived RTL test, not hardware acceptance or audio-path equivalence.

## Result

Mode 0 output behavior passed the selected observable checks: count 5 remains low for five input ticks and asserts on the sixth; binary count zero asserts after 65,536 count clocks following the RTL reload edge; and OUT remains high for 12 more ticks after terminal count while the internal counter wraps. The zero case matches Intel's 16-bit binary interpretation of zero as 65,536 and MAME's mode-0 terminal behavior. The test also programs count 4 LSB-first, waits through an LSB-only stage, then writes the MSB and observes terminal output after the reload sequence. Reads are tied off in the Exidy integration, so the model's internal wrap does not itself imply audible output toggles.

Mode 3 with even count 6 measured 3 high / 3 low input ticks across four consecutive steady-state periods, matching the reference square-wave split. Canonical mode 3 with odd count 5 measured 3 high / 2 low across four periods. Raw captured control word `BE` (counter 2, LSB/MSB, raw mode 7, binary), which MAME decodes as mode 3, also measured 3 high / 2 low across four periods. At every observed transition, hierarchical diagnostic values showed the expected reload/count pair (`0006` or `0005`), establishing that the steady waveform follows the programmed count rather than startup residue. The 3/2 assertions remain strict in both invocations; both pass.

The bounded Venture capture has control words `30`/`70`/`B0` (mode 0, channels 0/1/2) and `3E`/`7E`/`BE` (raw mode 7, binary LSB/MSB, channels 0/1/2). Counts were 118/112/99 for mode 0 and 95/73/80 for raw mode 7, respectively. The synthetic count values 5 and 6 in the bench deliberately exercise odd/even phase arithmetic; they are test values, not a claim that those exact divisors were used by the captured game.

## Fixture and checks

`sim/audio_8253/tb_8253_modes.sv` instantiates the actual `k580vi53` top and connects all three channel clocks/gates. It drives bus writes with a multi-cycle `wr` pulse, then advances the timer inputs and samples external outputs. Checks cover mode-0 start, terminal transition, terminal-high hold through wrap, LSB-then-MSB write ordering, binary zero, mode-3 even high/low lengths, and raw mode-7 odd behavior. Reset is applied only before programming. This matters because the selected RTL reset does not clear the CE counter; independent channels are used for the initial mode-0/mode-3 cases instead of assuming reset clears all timer state. The fixture drives `rd=0`, matching the write-only Exidy map.

A `+NEGATIVE` control inserts a deliberately false expectation after mode 0 count 5 has asserted OUT. It produces a failed assertion in the ignored negative log, confirming the testbench catches a controlled output mismatch. The normal canonical mode-3 run, the captured raw mode-7 run, and the negative control are separately retained as `run.log`, `mode7.log`, and `negative.log`.

## Live clock, reprogramming, and warm reset

`sim/audio_8253/tb_8253_live.sv` adds a separate continuous-clock case. The PIT input is a one-audio-clock pulse every eight `clk_sys` periods; the bench counts the detected falling edges. Bus writes assert for one audio clock and begin 16 audio clocks apart, giving two PIT edges between CPU writes, matching the selected audio T65 enable cadence. Gate remains high. No timer clock is paused around writes or reset.

The live sequence starts with mode 0 count 6, switches the same channel to mode 3 count 6, rewrites LSB/MSB from 6 to 5 without a mode-control write, writes raw captured mode 7 (`3E` on channel 0) with count 5, asserts reset for 16 audio clocks while PIT edges continue, then reprograms mode 0 count 6. The mode-3 6→5 byte write straddles an output edge: the LSB write is logged at PIT edge 52, the old count-6 waveform falls at edge 53, and the MSB write completes at edge 54. The intervening partial phase is treated as a captured transient, not used to redefine steady-state timing. After the next phase edge, four consecutive stable periods measure 3/2 ticks. This follows the Intel/MAME mode-3 rule that a new count takes effect at an output phase boundary; the current partial phase is not asserted as a complete new-count phase.

The live fixture passes mode 3 count 6 at 3/3 for three consecutive intervals following the 0→3 switch, mode 3 count 5 at 3/2 for four intervals after reprogramming, and raw mode 7 count 5 at 3/2 for four intervals. Warm reset advances the PIT edge count while held, leaves gate high, and subsequent mode-0 reprogramming reaches terminal output. `live.log` records each CPU write, output transition, PIT-edge index, count/reload diagnostic pair, steady interval, and assertion. These results characterize this RTL and modeled write cadence; they do not prove the full board's exact reset pulse or CPU bus waveform.

Verilator 5.052 compiled the unchanged source with `--binary --timing -Wno-fatal`. Full compiler output and run logs are in ignored `simulation/a5-8253-rtl/`. The compile reports pre-existing `WIDTHTRUNC`, `CASEX`, and `CASEINCOMPLETE` warnings in the selected RTL; no warning suppression beyond `-Wno-fatal` was used.

From the repository root, the commands are:

```powershell
New-Item -ItemType Directory -Force simulation/a5-8253-rtl | Out-Null
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && verilator --binary --timing -Wno-fatal --top-module tb_8253_modes --Mdir /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/simulation/a5-8253-rtl/obj_dir sim/audio_8253/tb_8253_modes.sv modules/k580vi53/k580vi53.v >simulation/a5-8253-rtl/compile.log 2>&1'
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && simulation/a5-8253-rtl/obj_dir/Vtb_8253_modes >simulation/a5-8253-rtl/run.log 2>&1'
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && simulation/a5-8253-rtl/obj_dir/Vtb_8253_modes +MODE7 >simulation/a5-8253-rtl/mode7.log 2>&1'
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && simulation/a5-8253-rtl/obj_dir/Vtb_8253_modes +NEGATIVE >simulation/a5-8253-rtl/negative.log 2>&1'
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && verilator --binary --timing -Wno-fatal --top-module tb_8253_live --Mdir /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/simulation/a5-8253-rtl/live_obj sim/audio_8253/tb_8253_live.sv modules/k580vi53/k580vi53.v >simulation/a5-8253-rtl/live_compile.log 2>&1'
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && simulation/a5-8253-rtl/live_obj/Vtb_8253_live >simulation/a5-8253-rtl/live.log 2>&1'
```

The canonical mode-3, raw mode-7, and live-timing runs pass. The negative-control command intentionally returns a nonzero status for its deliberate wrong expectation. The first two mode-3 runs record four consecutive high/low intervals and counter/reload values at every output edge.

## Reference and evidence limits

The Intel [8253/8253-5 data sheet](https://www.cpcwiki.eu/imgs/e/e3/8253.pdf) defines the 16-bit binary counter behavior, mode 0 terminal-count OUT, and mode 3 square-wave high/low count split. MAME's [`pit8253.cpp`](https://github.com/mamedev/mame/blob/master/src/devices/machine/pit8253.cpp) independently documents mode 0 terminal behavior, mode 3 intervals `ceil(n/2)` high and `floor(n/2)` low, zero as 65,536 binary counts, and its mode decode where raw mode 7 aliases mode 3. MAME's mode behavior is an external reference, not code reused by this fixture. The pinned local MAME 0.288 Exidy source confirms the game's PIT write mapping, clocks, gates, and OUT mixing; the generic PIT implementation is not bundled locally, so the online MAME source is identified as the independent model reference rather than asserted to be the exact executable revision.

This test does not instantiate or compare MAME, capture PCM, inspect counter reads, exercise other modes/BCD, or establish audible equivalence in captured play. Production RTL, QIP, MRA, and constraints were not edited; no Quartus build was run.

## Provenance

| Item | SHA-256 |
|---|---|
| Selected RTL `modules/k580vi53/k580vi53.v` | `0AF9A0EABB51FF6D12B402071D211ACE14C57AF9A7220760912C0D8DFFF6D5F6` |
| Fixture `sim/audio_8253/tb_8253_modes.sv` | `C5973F97D8AB89978A3713FFEB864F244416A02408E23304BC3294CEC6DC827A` |
| Live-clock fixture `sim/audio_8253/tb_8253_live.sv` | `18C2AB9D38469B23A7BA71F5F711602D2BE55A85D82CB5A9248A3BE787F87D43` |
| Pinned MAME Exidy sound integration source | `57C0EDC71E9FAF0A37E48EEF406586E95A95902EF0F9E53275A7AD3326FAD660` |
| Venture write capture from prior local run | `E583557848BA015360C4D545DF2933FB78BAC88AD74DB305091BC6BA88B33AED` |

