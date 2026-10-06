# Venture startup and horizontal movement reference

Venture's apparent startup stall was a short capture window, not a demonstrated hang. The retained 15-second `run05` ends during a startup scan. A zero-input 60-second run reaches the attract display by about frame 1800 (30 seconds): the first observed main-CPU read of `$5103` is frame 1720 (28.68 seconds), followed by regular PIA/IRQ activity. The earlier scan traverses ROM data through `$06–$09`; at the source clock (`11.289 MHz / 16`) and an estimated 620 cycles per byte, a 32 KiB scan would take about 29 seconds. This is a timing explanation consistent with the trace, not a claimed ROM checksum diagnosis.

The reset vector is `$8000`. Startup code at `$89FD–$8A15` writes patterns across zero-page `$00–$FF`, reads them back, and branches on mismatch. The separate helper near `$8B8B` performs an eight-step table transform while scanning data. The full disassembly is retained only in ignored output. Venture's default DSW is `$B0`: 1C/1C, three lives, 20,000 bonus, Free Play off. Lua input field value `1` means active.

Two identical 60-second right+Button 1 captures (`active03`, `active04`) pass validation and strict comparison. They reach the maze and contain 189,581 CPU bus events through frame 3600, 94,675 events at/after frame 3000, 2,990 observed `$5103` acknowledgement reads, 160,986 PIA reads, and 13 identical decoded 256×256 frames. During frames 2400–2519, the input port reads `$EB` (right and Button 1 active); sprite coordinate write data at `$5000` and `$5080` have 82 and 81 distinct values respectively.

A one-run right-only control (`right_only01`) reads `$FB` during the same movement interval. Comparing passive writes with `active03`, the player coordinate at `$5000/$5040` follows the same sequence in both runs, moving right on screen. The second object's `$5080` coordinate diverges beginning at frame 2436, after Button 1 is asserted; `$50C0` differs on two frames. This supports a reproducible right-plus-fire input case and a fire-correlated second-object movement. It does not prove that the second object is the arrow/projectile described in the report. The exact arrow identity and a production-core comparison remain open; these MAME captures do not reproduce the forum defect by themselves.

## Reproduction

Run from the repository root in PowerShell. The script uses the supplied NAS ROM path read-only, creates fresh per-run private state under ignored `simulation/venture_startup/`, retains the exact Lua script and command, mutes host output at −32 dB while keeping sound emulation enabled, and stops at 60 emulated seconds. Choose unused run names.

```powershell
& tools/reference_cases/venture_startup.ps1 -Run activeA -Seconds 60 -InputProbe
& tools/reference_cases/venture_startup.ps1 -Run activeB -Seconds 60 -InputProbe
python tools/reference_cases/validate_startup.py simulation/venture_startup/activeA
python tools/reference_cases/validate_startup.py simulation/venture_startup/activeB
python tools/reference_cases/compare_runs.py simulation/venture_startup/activeA simulation/venture_startup/activeB

# Matched movement control: right held, Button 1 released.
& tools/reference_cases/venture_startup.ps1 -Run rightOnlyA -Seconds 60 -RightOnlyProbe
python tools/reference_cases/validate_startup.py simulation/venture_startup/rightOnlyA
```

The frozen Lua hash for the accepted pair is `C24811A73AE47A74D9EC8215EC28A9612FDA0E4BACDECADE31D47488F97FE157`; both runs used MAME `0.288 (mame0288)` executable SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`, Venture ROM ZIP SHA-256 `AF340219D7FA4BF9D0A2A9FFABA7053189A6A2542D63B8CF2D3B74358DB72BCD`, and official MAME source commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`. The selected `exidy.cpp` SHA-256 is `0F58186AD90F0592454C505FF10FBCA948EBA14E7815704B2D24B13F69327486`. The exact options and output hashes are in each ignored `run-manifest.json`; screenshots, ROM-derived disassembly, and traces stay ignored.

`tools/reference_cases/run_case.ps1` remains a short 16-second generic probe and is not the Venture gameplay route. Use `venture_startup.ps1` for these 60-second cases. Passive bus taps record actual CPU accesses; the harness does not poll the side-effecting `$5103` register.
