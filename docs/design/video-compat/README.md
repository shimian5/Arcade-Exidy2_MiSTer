# Video compatibility and native tap diagnostic

This fixture investigates the exact-source mixer elaboration issue recorded in [the prior diagnostic](../video-capture/README.md). It keeps `sys/video_mixer.sv` and all production RTL unchanged. `tools/video_compat/measure.py` generates an explicitly simulation-only `video_mixer_scope_compat.sv` from the checked-in mixer. Its transformation is source-asserted: it verifies the exact original `generate` block, then moves only the three `R_in/G_in/B_in` wire declarations to module scope and converts the branch-local initialized nets to continuous assignments with the same expressions and widths. The full original copyright/license text is preserved. JSON records before/after block hashes and the production source hash. `-Wno-PROCASSWIRE` remains explicit for the unchanged HQ2x procedural-wire compatibility warning.

Reproduce on the installed WSL Arch Linux Verilator 5.052:

```powershell
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && python3 tools/video_compat/measure.py --verilator verilator --run-dir simulation/video_compat --report docs/design/video-compat/results.json'
```

Machine-readable evidence, exact source/fixture hashes, compiler status, eight phase runs, first divergences, native pulse measurements, and the negative control are in [results.json](results.json). Full compiler and run logs are retained in ignored `simulation/video_compat/`.

## Finding

The source-asserted mixer copy removes the `R_in/G_in/B_in` implicit-net warnings and carries the expected coordinate-coded RGB through the pipeline. However, the **native uncompensated alignment check fails**. The testbench labels input coordinates at the actual `arcade_video` rising-edge capture condition (`ce_pix` high while its previous sampled value is low), before nonblocking updates. Output RGB/DE is sampled at the later `CLK_VIDEO` edge when the previous `CE_PIXEL` value causes the VGA output registers to update, then observed after NBA. Gamma remains at its default parameter `GAMMA=1`, with gamma enable low; scandoubling is disabled and the otherwise unconnected `HDMI_FREEZE` is tied low only in the fixture.

Across all eight x/y bitplane phases, DE yields 256 rows × 256 pixels and zero line-geometry errors, with an 8-master-cycle output pixel cadence. Yet each run has 256 missing source-coordinate timestamps: the current stimulus tap labels x=0 through x=254 on both row 0 and row 255, while output DE includes x=255 on every row. For phase 0, the first color divergence is output `(x=1,y=0)`, RGB `000000` versus expected `ff00ff`; in later phases the first divergence moves to x=`2^phase`, consistent with an observed one-pixel source/data versus DE offset. Color mismatch totals by phase are 65,408; 32,640; 16,256; 8,064; 3,968; 1,920; 896; and 384. These are failures, not accepted coverage; the tracker/tap origin remains unresolved and could involve the testbench sampling origin, real pipeline phase, or both. The earlier compensated pattern/preamble experiment is excluded from these native results.

At the output consumer edge, coordinate-tag timestamps for matched pixels span 10 master-clock cycles (output cadence is 8 cycles). Output HS is 16 pixels wide and its measured phase to DE start is 16 pixels. Output VS is 1,680 pixels wide (five 336-pixel lines) and the first active-row DE edge is 1,696 pixels after VS rise. These are simulation outputs after `arcade_video` sync fixing and line latching, not raw counter phase or a physical receiver contract.

The executable negative control changes `mod_shift` from the MRA value `0x37` to `0x36`. The checker detects the perturbation through total output-event count (274,096 to 280,615), VS width (1,680 to 1,720 pixels), and VS-to-active-DE phase (1,696 to 1,736 pixels). The six current MRA files all use `0x37`; this altered value is only a sensitivity check.

The next diagnostic should derive a coordinate-labelled source queue directly at the accepted RGB/HBlank/VBlank edge and relate it to the output DE event stream without inferring x from a `negedge core_pix_clk` stimulus counter. Resolve the final active sample boundary and prove the first and last source coordinate on every row before using this path to claim a transport contract. No production behavior, full game, OSD/HDMI path, physical output, or gameplay result is changed or accepted here.
