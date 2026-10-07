# PIA source-stage full-flow result

The production inputs at `2fafa6b` completed the full unsandboxed PowerShell project flow on 2026-10-07 at 11:10:06 local, exit 0, zero errors and 295 warnings, in 14m09s. Release files were not replaced. **Timing still fails.**

| Check | Result |
|---|---|
| Master setup | -0.375 ns; TNS -2.268 ns |
| Audio setup | +26.713 ns |
| Minimum hold | +0.248 ns |
| Nominal HDMI setup | +0.493 ns |
| Resources | 15,556 ALMs; 22,577 registers; 168 RAM blocks; 1,179,813 RAM bits; 35 DSPs; 3 PLLs |
| RBF SHA-256 | `600143ECE701C7EEA0A1C03D1B64110A1C25F0193CC0A7B1D0DD7F4323CAD9C7` |

The eight worst setup paths now run directly from `audio_byte_stage` to `main_byte`, not from the audio PIA's DDR mask. The worst bit 4 has relationship 3.150 ns, clock skew -0.739 ns and data delay 2.456 ns. Its destination reset mux still occupies a LUT, with 2.119 ns interconnect to that feeder. The next candidate replaces only the destination's synchronous reset with the existing PIA9 asynchronous reset contract; the byte stays timed and its latency is unchanged. Paired PIA and actual Verilog tests pass, including reset assertion between master edges. A fresh full fit must verify D-path, recovery/removal and hold.

Both pause registers are now recognized in the metastability report. The report's aggregate incalculable fraction is 0.985; aggregate MTBF is not acceptance evidence. The first-stage-only pause exception does not waive the second stage or byte transfers. Hardware pause/hiscore duration gates remain open.

Post-fit clock discovery successfully resolves five divider Q pins and their PLL parents. Read-only diagnostic constraints produce source-derived periods BCLK 177.168 ns, PH1/PH6 1417.344 ns, and auPH0/auPH0B 1113.664 ns. They expose hold failures hidden by the previous incomplete clock model: worst -5.461 ns from static profile `mod_other[7]` to EIR3 on PH6, with additional joystick/graphics-to-EIR paths. No exception was added for these paths. The next full flow includes the five guarded generated clocks so the fitter can address actual relationships. Static-profile transfer and real interrupt-latch captures still require source/destination review; blanket waivers are not appropriate.

Logs and snapshots are ignored under `simulation/`: `quartus-pia-source-pause-2026-10-07.log`, `full-core/2fafa6b/`, `timing-2fafa6b/`, `timing-counter-clocks-2fafa6b/`, and `timing-counter-diagnostic-2fafa6b/`. The read-only replays are diagnostics of the completed fit, not substitutes for a full build and not evidence about the subsequently changed reset RTL.
