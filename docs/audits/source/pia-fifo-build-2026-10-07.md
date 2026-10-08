# Production PIA FIFO full-flow result — 2026-10-07

The PIA reply-byte timing blocker is closed at production source `016b4c9`.
All reported constrained timing passes. This is a development milestone;
legacy event-clock/latch coverage, game regressions and hardware acceptance
remain open. W15 is ACTIVE.

## Build and artifact

From the repository root in an unsandboxed PowerShell session:

```powershell
& 'C:\MiSTerDev\intelFPGA_lite\17.0\quartus\bin64\quartus_sh.exe' --flow compile Arcade-Exidy2
```

Quartus Prime Lite 17.0.2 Build 602, Cyclone V `5CSEBA6U23I7`, top `sys_top`.
Full compilation finished October 7 at 23:39:19 local host time, elapsed
13m40s, exit 0, **0 errors / 283 warnings**. Mapping, fitting, assembly and
TimeQuest completed. No isolated stage substitutes for this flow.

Ignored evidence: `simulation/full-core/016b4c9/full-flow.log`, fitted/map/STA
summaries and `Arcade-Exidy2.rbf`. The artifact is copied from the completed
production output, SHA256:

```text
E900F6E926B2D21853C9D0BF639E6E6C8E2932B226813723599A545EB0255E7B
```

Resources: 15,549/41,910 ALMs (37%), 22,952 registers, 162/553 RAM blocks
(29%), 1,179,264 RAM bits (21%), 35/112 DSP blocks (31%), 3/6 PLLs.
Release RBFs/MRAs are untouched. Revert `016b4c9` to remove this production
FIFO/reset/constraint repair; the earlier byte sampler then fails setup.

## Reported timing

Every setup/hold/recovery/removal/minimum-pulse summary has zero TNS.
Values are nanoseconds; these are the completed full flow's STA summaries.

| Domain/check | Setup | Hold |
| --- | ---: | ---: |
| Master PLL | +2.377 | +0.254 |
| Audio PLL | +16.331 | +0.250 |
| HDMI PLL | +0.449 | +0.198 |
| PH_6 | +8.246 | +1.006 |
| BCLK | +10.762 | +0.639 |
| PH_1 | +17.055 | +0.672 |
| auPH0B | +54.799 | +0.462 |
| auPH0 | +57.534 | +0.379 |

Minimum reported recovery +4.580, removal +0.787, pulse width +0.395.
Other reported framework clock domains also pass. This does not describe
unconstrained paths as timed.

## FIFO constraint and reset inspection

After the full flow, the read-only `tools/timing/report_pia_fifo.tcl` ran
against this fit and the production root/system SDCs. It adds no constraints.
Ignored reports: `simulation/timing-016b4c9/`; invocation log:
`simulation/full-core/016b4c9/timing-report.log`. Exit 0; required endpoint
collections pass (36 array FFs, 9 capture FFs, three logical Gray bits each
direction, including the fitted read-bit-2 replica).

| Targeted path | Setup/recovery | Hold/removal |
| --- | ---: | ---: |
| FIFO array to byte/notification capture | +15.228 | +0.498 |
| Write Gray to first synchronizer | +15.869 | +0.696 |
| Read Gray to first synchronizer | +16.331 | +0.494 |
| Write synchronizer interstage D | +20.476 | +0.581 |
| Read synchronizer interstage D | +68.289 | +0.465 |
| Audio reset conditioner interstage D | +68.305 | +0.512 |
| Master reset conditioner interstage D | +20.441 | +0.793 |
| Audio local reset release to state | +67.870 | +0.831 |
| Master local reset release to state | +20.279 | +0.829 |
| FIFO byte output to CPU input | +17.331 | +1.646 |
| Local reset output mask to CPU input | +18.165 | +1.202 |

The three 20 ns max-delay assignments resolve completely. Maximum reported
data delays are 3.687 ns for the bundle, 3.048 ns for write Gray, and 2.331 ns
for read Gray. Quartus 17's bound includes the reported clock relationship;
it is not a `-datapath_only` claim. The FIFO capture protocol supplies the
settling interval described in the [contract](pia-fifo-timing-contract.md).
These crossings retain normal fitted hold checks; no byte-data false path
or multicycle relaxation was added.

The new reset false path goes **through exactly four conditioner CLRN
inputs**, covering meta/release flops in each domain. Asynchronous assertion
at those pins is intentionally excepted; a missing input recovery/removal
report is not evidence of a timed input. Interstage D and local synchronized
release-to-state recovery/removal remain timed and pass. The raw audio-reset
mask was removed from the CPU data/notification outputs. Existing legacy
exceptions are unchanged. Gray synchronizer chains are recognized in the
metastability report; its estimates do not replace hardware validation.

## Functional evidence

Root independently replayed production `rtl/pia_return.v` with the actual
VHDL PIAs in ModelSim: **16 paired-PIA cases and 16 saturated streams pass**,
4,096 snapshots per stream (65,536 total). Coverage includes phase sweeps,
clock coincidence, DDR masking, initialization/data-only writes, unread
overwrites, one-audio-cycle CB2 pulses, held writes, and each reset asserted
near a master edge while traffic is pending or notification is low.
No overflow is observed under the tested source/master cadence.

Ignored evidence: `simulation/test-logs/pia-fifo-production-root.log` and
`simulation/pia_return_mailbox/modelsim-20261007-232346-301/`. Production
Verilator 5.052 stream replay also passes 4,096 snapshots; evidence:
`simulation/test-logs/pia-fifo-verilator.log`. Candidate/negative-control
results and exact source runners are documented in the contract and
`sim/pia_return_mailbox/README.md`. No ROM bytes or raw output are committed.

## Remaining timing and acceptance gates

`check_timing` still reports 3,263 no-clock nodes, 118 multiple-clock nodes,
96 latches and one loop across the design/framework. These include legacy
Exidy event logic and framework paths; the totals are not counts of Exidy
defects. They prevent a claim of complete core timing coverage. Generated
clock, PLL cross-check and uncertainty issue counts are zero. I/O warnings
remain (13 missing input delays, 129 missing output delays, one virtual clock).

The three partial-min/max warnings are exactly the new max-only crossings:
no explicit minimum bound was supplied, and their normal hold reports above
remain positive. Do not silence these with an unjustified minimum delay.
The 283-warning flow is not warning-free acceptance. Review remaining
event-clock/latch/reset contracts and relevant framework/I/O warnings before
final signoff. Broader corner/mode coverage and physical/game acceptance
remain required; these recorded summaries and targeted reports alone do not
establish all operating modes or the behavior of unconstrained endpoints.

Next bounded timing unit: classify and resolve the remaining Exidy event
paths, with endpoint evidence and meaningful regression tests. Hardware
tests should record the exact RBF/MRA, HDMI and Direct Video/S-Video settings,
reset behavior and sustained gameplay/audio. Subsequent production RTL or
constraint changes require a new full Quartus flow.
