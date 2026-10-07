# Full-core build checkpoint — 2026-10-07

The incoming production tree at `55e3300` was fast-forwarded into local `main` and compiled together with Quartus Prime Lite 17.0.2 Build 602. No production RTL or timing constraint was changed during this checkpoint. The owner's pre-existing increment-14 metadata change and root-level probe project files were preserved and excluded from the full-core project.

## Reproduction and outcome

Run from `C:\MiSTerDev\Arcade-Exidy2_MiSTer` in unsandboxed PowerShell:

```powershell
& 'C:\MiSTerDev\intelFPGA_lite\17.0\quartus\bin64\quartus_sh.exe' --flow compile Arcade-Exidy2
```

The complete flow finished on 2026-10-07 at 09:23:24 local, exit **0**, with **0 errors and 375 warnings**. Synthesis, fitting, assembly and TimeQuest completed. The selected VHDL 6840 implementation and the new reset, RAM mapping, interrupt-profile and mixer logic elaborated in the full project.

| Fitted resource | Use |
| --- | --- |
| ALMs | 15,537 / 41,910 (37%) |
| Registers | 22,424 |
| RAM blocks | 168 / 553 (30%) |
| Block memory bits | 1,179,813 / 5,662,720 (21%) |
| DSP blocks | 35 / 112 (31%) |
| PLLs | 3 / 6 (50%) |

All entries reported in `output_files/Arcade-Exidy2.sta.summary` have positive slack and zero TNS. Master PLL output 0 setup slack is **+0.021 ns**; audio PLL output 2 is **+0.235 ns**. Minimum reported hold slack is **+0.168 ns**; recovery **+3.864 ns**; removal **+0.734 ns**; minimum pulse width **+1.041 ns**. The master setup margin is only 21 ps; timing closure must be repeated after any source or constraint change.

Local test image: `output_files/Arcade-Exidy2.rbf`, 3,045,788 bytes, SHA-256 `A461194B792AEB0D5AE2C5F7FD7CF155DED48D2CF6D3585DE11A72CD6DDDD513`. Build log: `simulation/quartus-full-2026-10-07.log`. These generated files remain ignored. Release RBFs and release MRAs were not replaced, and this image has not been tested on hardware.

## Acceptance limits and next work

- TimeQuest explicitly reports that the design is **not fully constrained for setup or hold**. Generated/gated board clocks lack assignments. Critical Warning 332049 at SDC line 61 targets the absent core PLL output 1; related uncertainty constraints are also ignored. A successful full compilation is not complete timing signoff.
- The manual PLL multiplier/divider is 48/5 while the tool expects 177/7. Master setup uncertainty is 0.290 ns versus the recommended 0.380 ns: the 0.090 ns difference exceeds the reported 0.021 ns margin. Reconcile PLL and uncertainty constraints before treating the positive slack as timing closure at the real clock requirements.
- The PIA exceptions suppress asynchronous interface analysis; they do not add synchronizers. Profile writes occur during raw download reset, but the exact first-write versus synchronized audio-reset interval is not proved. Pause still crosses directly into audio CPU ready and combinational mute. See [source review](local-timing-review-2026-10-07.md).
- The 6840 asynchronous reset loads programmable counter values and maps to register/latch combinations. These warnings and reset sequencing need functional and timing review before release.
- Expansion adapter increments 1–15 remain isolated; the successful full-core build does not include them and does not prove their combined memory capacity or clock integration.

Next bounded engineering unit: inventory the unconstrained production clocks/endpoints, establish the intended clock/reset behavior from RTL, and prepare explicit timing coverage or a behavior-preserving clock-enable refactor where warranted. Do not hide runtime crossings with blanket false paths.

Hardware unit, when the owner can test: identify this RBF by hash; compare Venture, Mouse Trap, Pepper II and Hard Hat audio with baseline MRAs first, including both output channels, effect pitch, reset/reload and pause/resume. Then compare the matching candidate interrupt MRAs with the same RBF. Record room/stage transitions and `$5103` behavior separately. MAME WAV level/noise comparison and the reported Venture arrow sequence remain unresolved. W15 and game acceptance remain open.
